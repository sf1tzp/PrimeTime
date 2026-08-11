#!/usr/bin/env bash
# Distribution signing (#44, #46, #115): hardened runtime + secure timestamp,
# App Sandbox entitlements on the outer app. (The MAS variant signs through
# scripts/package-mas.sh instead — different certs, no hardened runtime.)
#
# codesign without --deep signs only the outer bundle, so Sparkle's nested
# executables are signed explicitly first, inside-out (Apple's recommended
# order; --deep would also strip Downloader.xpc's sandbox entitlements).
#
# Usage: sign-app.sh <app-bundle> <identity>
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$1"
IDENTITY="$2"
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"

sign() { codesign --force --options runtime --timestamp --sign "$IDENTITY" "$@"; }

# The app's sandbox claim (#115) — embedding it in the signature is what
# turns the sandbox on; there is no build-time step.
APP_ENTITLEMENTS="$ROOT/scripts/MomentTally.entitlements"

# Hardened-runtime library validation only loads libraries from the same
# team, and the self-signed dev cert has no Team ID — so a dev-signed app
# would refuse to load the bundled Sparkle at launch. Disable validation for
# the dev identity only (merged into a copy of the sandbox entitlements, so
# the dev build stays sandboxed too); Developer ID (both signatures share
# the real team) stays strict.
EXEC_FLAGS=()
if [[ "$IDENTITY" != "Developer ID Application"* ]]; then
    DEV_ENTITLEMENTS="$(mktemp -t dev-entitlements).plist"
    HELPER_ENTITLEMENTS="$(mktemp -t dev-helper-entitlements).plist"
    trap 'rm -f "$DEV_ENTITLEMENTS" "$HELPER_ENTITLEMENTS"' EXIT
    cp "$APP_ENTITLEMENTS" "$DEV_ENTITLEMENTS"
    /usr/libexec/PlistBuddy \
        -c "Add :com.apple.security.cs.disable-library-validation bool true" \
        "$DEV_ENTITLEMENTS"
    APP_ENTITLEMENTS="$DEV_ENTITLEMENTS"
    # Sparkle's helper executables get only the validation exception — they
    # are not sandboxed themselves (the installer's whole job is to work
    # outside the app's sandbox).
    cat > "$HELPER_ENTITLEMENTS" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.cs.disable-library-validation</key>
	<true/>
</dict>
</plist>
EOF
    EXEC_FLAGS=(--entitlements "$HELPER_ENTITLEMENTS")
fi

# Downloader.xpc ships with its own sandbox entitlements — preserve them.
# (Unused while the app holds network.client itself, but kept stock per
# Sparkle's signing guidance.)
sign --preserve-metadata=entitlements "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
sign "$SPARKLE/Versions/B/XPCServices/Installer.xpc"
sign ${EXEC_FLAGS[@]+"${EXEC_FLAGS[@]}"} "$SPARKLE/Versions/B/Autoupdate"
sign ${EXEC_FLAGS[@]+"${EXEC_FLAGS[@]}"} "$SPARKLE/Versions/B/Updater.app"
sign "$SPARKLE"
# The bundled CLI (#80): nested code, signed before the outer bundle. It
# links everything statically — library validation stays strict. Deliberately
# *not* sandboxed: it is its own process (the app's sandbox never extends to
# it), has no bundle identity to hang a container on, and its job is plain
# filesystem access to the store from a terminal.
sign "$APP/Contents/Helpers/moment-tally"
sign --entitlements "$APP_ENTITLEMENTS" "$APP"

codesign --verify --strict --verbose=2 "$APP"
