#!/usr/bin/env bash
# Distribution signing (#44, #46): hardened runtime + secure timestamp.
#
# codesign without --deep signs only the outer bundle, so Sparkle's nested
# executables are signed explicitly first, inside-out (Apple's recommended
# order; --deep would also strip Downloader.xpc's sandbox entitlements).
#
# Usage: sign-app.sh <app-bundle> <identity>
set -euo pipefail

APP="$1"
IDENTITY="$2"
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"

sign() { codesign --force --options runtime --timestamp --sign "$IDENTITY" "$@"; }

# Hardened-runtime library validation only loads libraries from the same
# team, and the self-signed dev cert has no Team ID — so a dev-signed app
# would refuse to load the bundled Sparkle at launch. Disable validation for
# the dev identity only; Developer ID (both signatures share the real team)
# stays strict.
EXEC_FLAGS=()
if [[ "$IDENTITY" != "Developer ID Application"* ]]; then
    ENTITLEMENTS="$(mktemp -t dev-entitlements).plist"
    trap 'rm -f "$ENTITLEMENTS"' EXIT
    cat > "$ENTITLEMENTS" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.cs.disable-library-validation</key>
	<true/>
</dict>
</plist>
EOF
    EXEC_FLAGS=(--entitlements "$ENTITLEMENTS")
fi

sign --preserve-metadata=entitlements "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
sign "$SPARKLE/Versions/B/XPCServices/Installer.xpc"
sign ${EXEC_FLAGS[@]+"${EXEC_FLAGS[@]}"} "$SPARKLE/Versions/B/Autoupdate"
sign ${EXEC_FLAGS[@]+"${EXEC_FLAGS[@]}"} "$SPARKLE/Versions/B/Updater.app"
sign "$SPARKLE"
sign ${EXEC_FLAGS[@]+"${EXEC_FLAGS[@]}"} "$APP"

codesign --verify --strict --verbose=2 "$APP"
