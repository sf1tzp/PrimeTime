#!/usr/bin/env bash
# One-shot own-machine data migration for the PrimeTime -> Moment Tally
# rename (#195). macOS's container-migration.plist mechanism only moves
# *pre-sandbox* paths into a freshly created container — it cannot move one
# container's data into another — so the old sandboxed app's data needs this
# by-hand step. Zero external users (#195 decision), so a script in scripts/
# is the whole ceremony.
#
# What it does, in order:
#   1. moves the old container's app-data folder
#      (~/Library/Containers/tools.primetime.PrimeTime/Data/Library/
#       Application Support/tools.primetime.PrimeTime) into the new
#      container's mirror path under the new bundle id — or, if the old
#      container has none, moves a pre-sandbox leftover from
#      ~/Library/Application Support/tools.primetime.PrimeTime instead
#   2. renames primetime.sqlite (+ -wal/-shm) to momenttally.sqlite
#      (LocalBackend would self-heal this on next launch anyway — done here
#      so the moved folder is immediately coherent)
#   3. copies the old preferences plist into the new container under the
#      new domain, then kicks cfprefsd so it isn't served from cache
#
# The Traggo device token migrates in-app (Keychain.swift chains the legacy
# service identifiers), so the keychain needs nothing here.
#
# Preconditions: MomentTally.app has launched at least once (so macOS has
# created + initialised the new container), and neither app is running.
set -euo pipefail

OLD_ID="tools.primetime.PrimeTime"
NEW_ID="com.streetfortress.MomentTally"
OLD_CONTAINER="$HOME/Library/Containers/$OLD_ID"
NEW_CONTAINER="$HOME/Library/Containers/$NEW_ID"
OLD_DATA="$OLD_CONTAINER/Data/Library/Application Support/$OLD_ID"
PLAIN_DATA="$HOME/Library/Application Support/$OLD_ID"
NEW_DATA="$NEW_CONTAINER/Data/Library/Application Support/$NEW_ID"

[[ "$(uname)" == Darwin ]] || { echo "error: macOS only" >&2; exit 1; }

if pgrep -x MomentTally >/dev/null || pgrep -x PrimeTime >/dev/null; then
    echo "error: quit the app first (MomentTally/PrimeTime is running)" >&2
    exit 1
fi

if [[ ! -d "$NEW_CONTAINER/Data" ]]; then
    echo "error: no container at $NEW_CONTAINER —" >&2
    echo "       launch MomentTally.app once (then quit it) so macOS creates it" >&2
    exit 1
fi

# --- 1. app data ------------------------------------------------------------
SOURCE=""
if [[ -d "$OLD_DATA" ]]; then
    SOURCE="$OLD_DATA"
elif [[ -d "$PLAIN_DATA" ]]; then
    # Pre-sandbox leftover (a dev build's, or a pre-#115 install that never
    # ran sandboxed) — same shape, different root.
    SOURCE="$PLAIN_DATA"
fi

if [[ -z "$SOURCE" ]]; then
    echo "app data: nothing to migrate (no $OLD_DATA or $PLAIN_DATA)"
elif [[ -e "$NEW_DATA/momenttally.sqlite" || -e "$NEW_DATA/primetime.sqlite" ]]; then
    echo "app data: $NEW_DATA already holds a store — not overwriting." >&2
    echo "          Old data stays at: $SOURCE" >&2
else
    mkdir -p "$(dirname "$NEW_DATA")"
    if [[ -d "$NEW_DATA" ]]; then
        # The new app's first launch created an (empty, store-less) folder;
        # move the old contents into it rather than replacing the folder.
        mv "$SOURCE"/* "$NEW_DATA"/ 2>/dev/null || true
        rmdir "$SOURCE" 2>/dev/null || true
    else
        mv "$SOURCE" "$NEW_DATA"
    fi
    echo "app data: moved $SOURCE -> $NEW_DATA"
fi

# --- 2. store filename ------------------------------------------------------
for suffix in "" "-wal" "-shm"; do
    if [[ -e "$NEW_DATA/primetime.sqlite$suffix" \
          && ! -e "$NEW_DATA/momenttally.sqlite$suffix" ]]; then
        mv "$NEW_DATA/primetime.sqlite$suffix" "$NEW_DATA/momenttally.sqlite$suffix"
        echo "store: renamed primetime.sqlite$suffix -> momenttally.sqlite$suffix"
    fi
done

# --- 3. preferences ---------------------------------------------------------
OLD_PREFS="$OLD_CONTAINER/Data/Library/Preferences/$OLD_ID.plist"
NEW_PREFS="$NEW_CONTAINER/Data/Library/Preferences/$NEW_ID.plist"
if [[ ! -f "$OLD_PREFS" ]]; then
    echo "prefs: nothing to migrate (no $OLD_PREFS)"
elif [[ -f "$NEW_PREFS" ]]; then
    echo "prefs: $NEW_PREFS already exists — not overwriting"
else
    mkdir -p "$(dirname "$NEW_PREFS")"
    cp "$OLD_PREFS" "$NEW_PREFS"
    # cfprefsd caches by domain; make it re-read the plist we just planted.
    killall cfprefsd 2>/dev/null || true
    echo "prefs: copied $OLD_PREFS -> $NEW_PREFS"
fi

echo "done. The old container ($OLD_CONTAINER) keeps only what wasn't moved;"
echo "delete it once the new app has been seen working with the migrated data."
