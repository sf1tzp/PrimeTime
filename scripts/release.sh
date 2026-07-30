#!/usr/bin/env bash
# Release pipeline (#45): tag → build → bundle → sign → notarize → staple →
# package → publish. Run via `just release`; every step is also runnable on
# its own (see the justfile), so the pipeline stays debuggable by hand even
# once CI wraps it.
#
#   preflight  clean tree, HEAD at an exact vX.Y.Z tag, tools present
#   sign-dist  release build + .app assembly + Developer ID signing
#   notarize   notarytool submit, wait, staple the ticket
#   assess     Gatekeeper's verdict on the stapled bundle
#   package    dist/PrimeTime-<version>.zip of the stapled bundle
#              (zip over DMG — Sparkle appcasts consume zips directly)
#   appcast    EdDSA-sign the zip and generate dist/appcast/appcast.xml (#46);
#              the app's SUFeedURL is the mirror's stable
#              releases/latest/download/appcast.xml redirect, so publishing
#              the appcast as a release asset *is* the feed update
#   publish    GitHub release on the public mirror: artifact, appcast, notes
#   cask bump  point sf1tzp/homebrew-tap's primetime cask at the new release
#
# Versioning: semver git tags (vX.Y.Z) are the source of truth. bundle-app.sh
# stamps the tag into CFBundleShortVersionString and the commit count into
# CFBundleVersion; the Help tab renders both.
#
# Secrets stay in the login keychain — the "Developer ID Application"
# identity and the notarytool profile ("primetime-notary"; one-time setup:
# xcrun notarytool store-credentials primetime-notary). Publishing needs the
# gh CLI authenticated against github.com (brew install gh && gh auth login).
#
# Usage:
#   git tag v1.2.0 && git push origin v1.2.0
#   just release                # full pipeline
#   just release --no-publish   # everything except the GitHub release
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIRROR="sf1tzp/PrimeTime"

PUBLISH=1
for arg in "$@"; do
    case "$arg" in
        --no-publish) PUBLISH=0 ;;
        *) echo "unknown flag: $arg (supported: --no-publish)" >&2; exit 2 ;;
    esac
done

# --- preflight ---------------------------------------------------------------
[[ -z "$(git -C "$ROOT" status --porcelain)" ]] \
    || { echo "preflight: working tree is dirty — commit or stash first" >&2; exit 1; }

TAG="$(git -C "$ROOT" describe --tags --exact-match 2>/dev/null)" \
    || { echo "preflight: HEAD carries no tag — release from an exact vX.Y.Z tag" >&2; exit 1; }
[[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] \
    || { echo "preflight: tag '$TAG' is not semver (vX.Y.Z)" >&2; exit 1; }
VERSION="${TAG#v}"

for tool in just xcrun ditto; do
    command -v "$tool" >/dev/null \
        || { echo "preflight: '$tool' not found" >&2; exit 1; }
done
if (( PUBLISH )); then
    command -v gh >/dev/null \
        || { echo "preflight: publishing needs the gh CLI (brew install gh && gh auth login);" \
                  "or run with --no-publish" >&2; exit 1; }
fi

echo "==> releasing $TAG"

# --- build → sign → notarize → staple → assess -------------------------------
just --justfile "$ROOT/justfile" sign-dist
just --justfile "$ROOT/justfile" notarize
just --justfile "$ROOT/justfile" assess

# --- package ------------------------------------------------------------------
ARTIFACT="$ROOT/dist/PrimeTime-$VERSION.zip"
ditto -c -k --keepParent "$ROOT/dist/PrimeTime.app" "$ARTIFACT"
echo "==> packaged $ARTIFACT"

# --- release notes -------------------------------------------------------------
# Commit subjects since the previous tag; edit dist/RELEASE_NOTES.md between
# `just release --no-publish` and a manual publish for hand-written notes
# (then re-run the appcast step too — it embeds these notes).
NOTES="$ROOT/dist/RELEASE_NOTES.md"
PREV="$(git -C "$ROOT" describe --tags --abbrev=0 "$TAG^" 2>/dev/null || true)"
{
    echo "## PrimeTime $VERSION"
    echo
    git -C "$ROOT" log --format='- %s' "${PREV:+$PREV..}$TAG"
} > "$NOTES"

# --- appcast (#46) -------------------------------------------------------------
# A staging dir with only this release's zip: generate_appcast signs every
# archive it finds, and dist/ also holds the unsigned notarize-upload.zip.
# One entry per appcast is enough — the feed URL always points at the latest
# release's copy, and Sparkle only ever offers the newest version anyway.
# The EdDSA private key comes from the login keychain (generate_keys; #45's
# secrets decision), the tools from scripts/sparkle-tools.sh.
SPARKLE_BIN="$("$ROOT/scripts/sparkle-tools.sh")"
APPCAST_DIR="$ROOT/dist/appcast"
rm -rf "$APPCAST_DIR" && mkdir -p "$APPCAST_DIR"
cp "$ARTIFACT" "$APPCAST_DIR/"
cp "$NOTES" "$APPCAST_DIR/PrimeTime-$VERSION.md"   # embedded as the entry's notes
"$SPARKLE_BIN/generate_appcast" \
    --download-url-prefix "https://github.com/$MIRROR/releases/download/$TAG/" \
    --link "https://github.com/$MIRROR" \
    --embed-release-notes \
    -o "$APPCAST_DIR/appcast.xml" \
    "$APPCAST_DIR"
echo "==> appcast at $APPCAST_DIR/appcast.xml"

# --- publish -------------------------------------------------------------------
if (( !PUBLISH )); then
    echo "==> skipping publish (--no-publish); artifact and notes are in dist/"
    exit 0
fi

# The gitea repo push-mirrors to $MIRROR on an interval; the tag must have
# arrived there (and still point at our commit) before the release can hang
# off it. If this fails, wait for the mirror sync or trigger it in gitea.
LOCAL_SHA="$(git -C "$ROOT" rev-parse "$TAG")"
MIRROR_SHA="$(gh api "repos/$MIRROR/git/ref/tags/$TAG" --jq .object.sha 2>/dev/null)" \
    || { echo "publish: tag $TAG not on $MIRROR yet — wait for the push-mirror sync" >&2; exit 1; }
[[ "$MIRROR_SHA" == "$LOCAL_SHA" ]] \
    || { echo "publish: $TAG on $MIRROR points at $MIRROR_SHA, local is $LOCAL_SHA" >&2; exit 1; }

gh release create "$TAG" "$ARTIFACT" "$APPCAST_DIR/appcast.xml" \
    --repo "$MIRROR" \
    --title "PrimeTime $VERSION" \
    --notes-file "$NOTES" \
    --verify-tag
echo "==> published https://github.com/$MIRROR/releases/tag/$TAG"

# --- cask bump (#47) -----------------------------------------------------------
# Point the tap's cask at the release just published. Sparkle keeps installed
# apps current either way, so a failed bump is an inconvenience, not an
# outage — rerun these steps by hand if the push races another update.
TAP="sf1tzp/homebrew-tap"
SHA256="$(shasum -a 256 "$ARTIFACT" | cut -d' ' -f1)"
TAP_DIR="$(mktemp -d)"
gh repo clone "$TAP" "$TAP_DIR" -- --depth 1 --quiet
sed -i '' \
    -e "s/^  version .*/  version \"$VERSION\"/" \
    -e "s/^  sha256 .*/  sha256 \"$SHA256\"/" \
    "$TAP_DIR/Casks/primetime.rb"
git -C "$TAP_DIR" commit -aqm "primetime $VERSION"
git -C "$TAP_DIR" push -q
rm -rf "$TAP_DIR"
echo "==> cask bumped to $VERSION on $TAP"
