# Driving PrimeTime via System Events / AX

Shared reference for the `verify` and `capture` skills. This is where the
hard-won AX knowledge lives — keep additions here, not in the individual
skills, so the two don't drift.

## Element map

- The status item is `menu bar item 1 of menu bar 2`; its label is "Timer" when
  idle, "● M:SS" while running.
- The popover is the untitled window: `window ""`. Its rows are unnamed buttons
  of `group 1` in layout order (idle: quick-start sets first, then Log,
  Calendar, History, Settings…, Quit; running: Stop first).
- The PrimeTime window is `window "PrimeTime"`; switch tabs via
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
- **Never drive AX with two PrimeTime instances running** (learned 2026-07-29
  testing Sparkle): the user's installed copy + a test build are two processes
  with the same name, and even `first process whose unix id is <pid>` sessions
  ended up enumerating the *other* app's popover. Both instances also share
  the real database and defaults — a `HOME=` env override does NOT isolate
  anything (`NSHomeDirectory()`, UserDefaults, and Application Support all
  resolve the real home). Ask the user to quit the installed app (or note
  you're doing it) before any popover/settings driving of a test build.
- The status-item click *toggles* the popover, and it stays open across
  osascript runs — guard with `if not (exists window "" of p)` before
  clicking again, or a fresh script closes what the last one opened.

## Screenshots & recordings

- Stills: best results from `screencapture -x -l <CGWindowID>` — captures
  just that window with its native shadow on a transparent background, no crop
  math. Get the ID with a tiny compiled Swift helper calling
  `CGWindowListCopyWindowInfo` (filter on owner name; there's no pyobjc to do
  it from Python). The popover (`window ""`) and the PrimeTime window each
  have their own ID. Falling back to full-screen + crop: `sips -c <h> <w>
  --cropOffset <y> <x>` (pixels = points × 2), but beware `--cropOffset 0 0`
  is treated as unset and crops from the *center* — use `1 1` for top-left.
- Recordings: `screencapture -v -R "x,y,w,h" out.mov` (region in points; get
  the window's `position`/`size` from AX first, and add margin if you want
  the shadow). `-V <seconds>` caps the duration so the run needs no manual
  stop; drive the scene from a second shell while it records.
