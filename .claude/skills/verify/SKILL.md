---
name: verify
description: Build, launch, and drive TraggoMenuBar to verify changes against the live traggo.lofi server.
---

# Verifying TraggoMenuBar

## Build & launch

```bash
just build          # swift build + codesign with "TraggoMenuApp Dev"
./.build/debug/TraggoMenuBar > /tmp/app.log 2>&1 &   # plain bash background; wait ~5-10s
```

**Keychain gotcha (fixed 2026-07-23 on macmini):** if launches prompt for the
login-keychain password after every rebuild, the "TraggoMenuApp Dev" cert has
no codeSign trust entry (`security find-identity -v -p codesigning` shows 0
valid), so the ACL's cert-anchored requirement can never validate. Fix once
per machine:

```bash
security find-certificate -c "TraggoMenuApp Dev" -p > /tmp/dev-cert.pem
security add-trusted-cert -r trustRoot -p codeSign \
  -k ~/Library/Keychains/login.keychain-db /tmp/dev-cert.pem   # user confirms a dialog
```

(Setting "Always Trust" in Keychain Access can silently fail to persist —
verify with `security dump-trust-settings`.) A launch stuck in
`SecItemCopyMatching` (state `SN`, ~0 CPU, never appears in System Events)
means a dialog is waiting; only the user can dismiss it.

## Driving it (System Events / AX)

- The status item is `menu bar item 1 of menu bar 2`; its label is "Timer" when
  idle, "● M:SS" while running.
- The popover is the untitled window: `window ""`. Its rows are unnamed buttons
  of `group 1` in layout order (idle: Foo, Meeting, Log, Calendar, History,
  Settings…, Quit; running: Stop first).
- Settings window is `window "Traggo Menu App Settings"`; switch tabs via
  `click button "<Label>" of toolbar 1`. Tab content lives under
  `group 1 of group 1`; the week navigator is buttons 1-4 (prev, Today, next,
  refresh); log rows are unnamed buttons of `UI element 1 of scroll area 1`.
- Buttons expose no names/titles — identify by `position`/`size`.
- Deleting opens a `sheet 1` with `button "Cancel"` and `button 2` (= Delete).

## Hard-won caveats

- **Never verify text entry via AX**: `set value of text field` bypasses the
  SwiftUI binding (Save then persists the old value), and NSHostingView
  recycles NSTextFields so later AX reads return your own phantom text even in
  fresh view instances. Synthetic `keystroke` is also unreliable here. Verify
  note/tag *text* edits manually; clicks (expand, save, delete, navigate) are
  reliable.
- Screenshots: `screencapture -x` then crop with
  `sips -c <h> <w> --cropOffset <y> <x>` (pixels = points × 2 on this display).
  Get the window frame via AX `position`/`size` to aim crops.
- The server is `https://traggo.lofi` (fast check: `curl -sk -o /dev/null -w
  "%{http_code}" https://traggo.lofi/`). Mutations hit real user data — create
  your own test timespan (quick-start a tag set, stop it) and delete it when
  done.
