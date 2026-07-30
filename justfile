
build:
  swift build && codesign --force --sign "TraggoMenuApp Dev" .build/debug/PrimeTime

run-dev: build
  ./.build/debug/PrimeTime

run:
  ./.build/debug/PrimeTime

# --- Distribution (#44) ---

# Assemble dist/PrimeTime.app from a release build (arm64-only).
bundle:
  scripts/bundle-app.sh

# Sign the bundle for distribution: hardened runtime + secure timestamp.
# Pass identity="TraggoMenuApp Dev" for a local pipeline check without the
# Developer ID cert (spctl will reject it, codesign --verify still passes).
sign-dist identity="Developer ID Application: Steven Fitzpatrick (2GY54R95TD)": bundle
  codesign --force --options runtime --timestamp --sign "{{identity}}" dist/PrimeTime.app
  codesign --verify --strict --verbose=2 dist/PrimeTime.app

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
# staple → package dist/PrimeTime-<version>.zip → GitHub release on the
# public mirror. Pass --no-publish to stop after packaging.
release *flags:
  scripts/release.sh {{flags}}
