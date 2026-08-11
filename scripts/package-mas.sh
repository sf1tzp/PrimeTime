#!/usr/bin/env bash
# Mac App Store packaging (#115): sign the MAS bundle and wrap it in a signed
# installer .pkg for upload to App Store Connect (Transporter, or
# `xcrun altool --upload-package`). The store pipeline differs from the
# Developer ID one (sign-app.sh) on every axis:
#
#   certificates  "Apple Distribution" signs the app, "Mac Installer
#                 Distribution" signs the .pkg — neither is the Developer ID
#                 pair, and notarytool plays no part: App Review replaces
#                 notarization for store builds.
#   entitlements  scripts/MomentTally-MAS.entitlements, plus the two App Store
#                 identity keys injected here (com.apple.application-identifier
#                 = TEAMID.bundle-id, com.apple.developer.team-identifier) —
#                 the store requires them and validates both against the
#                 embedded provisioning profile.
#   runtime       no --options runtime: hardened runtime is a notarization
#                 concept; store builds rely on the sandbox alone (this is
#                 what Xcode does for App Store archives too).
#   profile       a "Mac App Store" provisioning profile must ride at
#                 Contents/embedded.provisionprofile; pass its path via
#                 MAS_PROFILE. (Create it in the developer portal once the
#                 distribution certs exist.)
#
# No nested code to sign: the MAS bundle has no frameworks, XPC services, or
# helpers — one codesign of the outer bundle covers everything.
#
# Usage: package-mas.sh <app-bundle> [<app-identity>] [<installer-identity>]
# Env:
#   TEAM_ID      Apple Developer team (default: 2GY54R95TD)
#   MAS_PROFILE  path to the Mac App Store .provisionprofile (optional until
#                the store certs/profile exist; a warning reminds you)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$1"
# Full identity names carry "…: Name (TEAMID)"; the prefix is enough for
# codesign to find the cert once it exists in the keychain. Older installer
# certs may be named "3rd Party Mac Developer Installer" — pass that if
# that's what `security find-identity -v` shows.
APP_IDENTITY="${2:-Apple Distribution}"
PKG_IDENTITY="${3:-Mac Installer Distribution}"
TEAM_ID="${TEAM_ID:-2GY54R95TD}"

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"

if [[ -n "${MAS_PROFILE:-}" ]]; then
    cp "$MAS_PROFILE" "$APP/Contents/embedded.provisionprofile"
    # A browser-downloaded profile carries com.apple.quarantine, which App
    # Store Connect rejects anywhere in a submission (error 91109) — and cp
    # propagates it (or, when overwriting, keeps the destination's old
    # xattrs, since the inode survives). Clear them on the copy.
    xattr -c "$APP/Contents/embedded.provisionprofile"
else
    echo "warning: no MAS_PROFILE — App Store Connect will reject the upload" \
         "without Contents/embedded.provisionprofile" >&2
fi

# The MAS entitlements plus the team-specific identity keys, injected into a
# throwaway copy so the checked-in file stays team-free.
ENTITLEMENTS="$(mktemp -t mas-entitlements).plist"
trap 'rm -f "$ENTITLEMENTS"' EXIT
cp "$ROOT/scripts/MomentTally-MAS.entitlements" "$ENTITLEMENTS"
/usr/libexec/PlistBuddy \
    -c "Add :com.apple.application-identifier string $TEAM_ID.$BUNDLE_ID" \
    -c "Add :com.apple.developer.team-identifier string $TEAM_ID" \
    "$ENTITLEMENTS"

codesign --force --timestamp --sign "$APP_IDENTITY" \
         --entitlements "$ENTITLEMENTS" "$APP"
codesign --verify --strict --verbose=2 "$APP"

# productbuild wraps the .app in the installer package the store ingests —
# store apps upload as .pkg, not .zip/.dmg; /Applications is where the
# store installs it.
PKG="$ROOT/dist/$(basename "$APP" .app)-$VERSION-mas.pkg"
productbuild --component "$APP" /Applications --sign "$PKG_IDENTITY" "$PKG"
echo "Packaged $PKG ($BUNDLE_ID $VERSION, team $TEAM_ID)"
