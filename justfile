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

# --- Release (#45) ---

# Full pipeline from an exact vX.Y.Z tag on HEAD: build → sign → notarize →
# staple → package dist/PrimeTime-<version>.zip → appcast → GitHub release on
# the public mirror → cask bump on sf1tzp/homebrew-tap. Pass --no-publish to
# stop after the appcast.
release *flags:
  scripts/release.sh {{flags}}
