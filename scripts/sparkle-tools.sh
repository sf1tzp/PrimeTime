#!/usr/bin/env bash
# Fetch Sparkle's CLI tools (generate_keys, sign_update, generate_appcast) and
# print their bin directory. The tools ship in the release tarball, not the
# SPM package, so this downloads the tarball matching the version pinned in
# Package.resolved and caches it under .build/sparkle-tools/<version>.
#
# Usage: BIN="$(scripts/sparkle-tools.sh)"; "$BIN/generate_appcast" ...
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

VERSION="$(/usr/bin/python3 -c '
import json
with open("'"$ROOT"'/Package.resolved") as f:
    pins = json.load(f)["pins"]
print(next(p["state"]["version"] for p in pins if p["identity"] == "sparkle"))
')"

DEST="$ROOT/.build/sparkle-tools/$VERSION"
if [[ ! -x "$DEST/bin/generate_appcast" ]]; then
    mkdir -p "$DEST"
    TARBALL="https://github.com/sparkle-project/Sparkle/releases/download/$VERSION/Sparkle-$VERSION.tar.xz"
    echo "fetching Sparkle tools $VERSION" >&2
    curl -fsSL "$TARBALL" | tar -xJ -C "$DEST" bin
fi
echo "$DEST/bin"
