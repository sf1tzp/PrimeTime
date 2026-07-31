build:
  swift build

run:
  ./.build/debug/PrimeTime

demo:
  ./.build/debug/PrimeTime --demo

# --- Distribution (#44) ---

# Assemble dist/PrimeTime.app from a release build (arm64-only).
bundle:
  scripts/bundle-app.sh

# Sign the bundle for distribution: hardened runtime + secure timestamp, with
# Sparkle's nested executables signed first (see scripts/sign-app.sh).
# Run `just sign-dist "TraggoMenuApp Dev"` for a local pipeline check without
# the Developer ID cert (spctl will reject it, codesign --verify still passes).
sign-dist identity="Developer ID Application: Steven Fitzpatrick (2GY54R95TD)": bundle
  scripts/sign-app.sh dist/PrimeTime.app "{{identity}}"

# Submit the signed bundle for notarization and staple the ticket. The zip is
# only the submission vehicle; the distributable is repacked post-staple by
# `just release`. One-time setup: xcrun notarytool store-credentials primetime-notary
notarize profile="primetime-notary":
  ditto -c -k --keepParent dist/PrimeTime.app dist/notarize-upload.zip
  xcrun notarytool submit dist/notarize-upload.zip --keychain-profile {{profile}} --wait
  xcrun stapler staple dist/PrimeTime.app

# Gatekeeper's verdict on the bundle (passes only once signed with a Developer
# ID cert and notarized; the dev cert is expected to fail here).
assess:
  spctl --assess --type execute --verbose dist/PrimeTime.app


# Tag HEAD for release and push the tag. Accepts "1.2.3" or "v1.2.3" — any
# leading v is stripped before re-adding, so "vv1.2.3" can't happen. The final
# tag must match release.sh's preflight regex (vX.Y.Z, no prerelease/build).
tag version:
  #!/usr/bin/env bash
  set -euo pipefail
  v="{{version}}"
  v="${v#v}"
  [[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
      || { echo "error: 'v$v' is not vX.Y.Z semver" >&2; exit 1; }
  git tag "v$v" && git push origin "v$v"

# --- Release (#45) ---

# Full pipeline from an exact vX.Y.Z tag on HEAD: build → sign → notarize →
# staple → package dist/PrimeTime-<version>.zip → appcast → GitHub release on
# the public mirror → cask bump on sf1tzp/homebrew-tap. Pass --no-publish to
# stop after the appcast.
release *flags:
  scripts/release.sh {{flags}}

# --- Server distribution (#75) ---

# Server image + Helm chart off the same vX.Y.Z tag: docker/nerdctl build →
# helm package → push to GHCR (public) and the internal gitea registry (#48).
# Runs anywhere with docker-or-nerdctl + helm + gh — no Mac needed. The GHCR
# side normally rides CI (.github/workflows/release-server.yml, triggered by
# the mirrored tag); this is the by-hand fallback and the internal-registry
# path. Pass --no-publish to build without pushing, --no-internal to skip gitea.
release-server *flags:
  scripts/release-server.sh {{flags}}

# The whole release off the tag on HEAD: app (Mac-bound) then server image +
# chart. Mac-only — and it needs docker/nerdctl + helm there too; on Apple
# Silicon the image cross-builds to linux/amd64 (see release-server.sh).
# NB `just release release-server` does NOT do this: release's variadic
# {{flags}} would swallow "release-server" as an argument.
release-all: release release-server
