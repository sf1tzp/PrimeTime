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
- The popover window is not reliably `window ""` — on macbook-air
  (2026-08-03) it enumerated as `window "Untitled"`. Address it as
  `window 1` (the PrimeTime window is findable by its real name, so the
  popover is whatever's left) and check `name of every window` when lost.
- Collective element queries on the popover (`buttons of group 1 of
  window 1`) can fail wholesale with `-10000` even when the elements exist —
  iterate `UI elements of …` and filter on `role` instead.
- **Tab-order tracing works** (2026-08-03, found the #134 key-view-loop bug):
  focus a field, then loop `keystroke tab` + read `value of attribute
  "AXFocusedUIElement" of process` — reliable, unlike text entry. Caveats:
  `set focused of <field> to true` only takes if that window is key (with two
  windows the read silently returns the other window — `cliclick` into the
  field instead), and a field-style date picker reports its *label's* static
  text as focused while eating one Tab per date element.
- A fresh demo launch opens onboarding: click `button 1 of group 1 of
  window 1` repeatedly to advance, then close the walkthrough window it
  hands off to (`AXCloseButton`) before driving anything else.
- Views at `.opacity(0)` (e.g. hover-revealed controls) are absent from the
  AX tree entirely — not present-but-invisible. To reach them, hover with a
  real cursor move first (`cliclick m:x,y`, app frontmost), then re-query;
  their presence/absence also doubles as a check that the hover reveal
  works. Buttons identify nicely by their `help` attribute (read it per
  element inside a `try`; some elements throw).
- **Duplicate pop-up buttons alias the same control** (learned 2026-08-03 on
  the History tab): both "Group by" pickers enumerate as `AXPopUpButton`s,
  but `pop up button 2 of scroll area 1` reports picker 1's position/value
  and clicking it opens picker 1's menu — the right picker is unreachable
  through the tree. Workaround: read the right column's "Group by"
  `AXStaticText` position, `cliclick c:<x+95>,<y+6>` to open the real
  picker, then select by *menu type-select* (`keystroke "<item name>"`,
  `key code 36`). Typing the full item name wins over shorter siblings
  ("project" beats "proj") because a menu item can't prefix-match a buffer
  longer than itself.
- After `click` on a (working) pop up button, poll for `menu 1` *and* the
  target menu item — items populate late. A script that dies mid-menu
  leaves it open, and the next click toggles it shut: send Escape
  (`key code 53`) before retrying.
- SwiftUI segmented controls (`AXRadioGroup`) click fine via
  `radio button N`, but a disabled control silently no-ops — read the
  values back to confirm the switch took.
- **`button N` and `UI element N` index differently** (learned 2026-08-03
  driving the popover): `button 24` counts only buttons and fails with
  "Invalid index" past their count, while an element enumeration that showed
  a button as the 24th child needs `UI element 24`. When a click errors
  -1719 on an element you just enumerated, re-address it by element index.
  Coercing `position of e as string` concatenates x,y with no separator
  ("1137612" = 1137,612) — fetch coordinates separately if you need math.
- The popover's **Settings… row switches the main "PrimeTime" window to its
  Settings tab** — no separate settings window exists, and ⌘, does nothing.
  Onboarding's unnamed footer buttons are the last three of `group 1`
  (Back / Skip Tour / Next); pick "Skip Tour" as the ~85pt-wide one.
- **Colour pickers drive fine end-to-end** (2026-08-03, card-colour verify):
  click the `AXColorWell` swatch → panel appears as `window "Colors"` of the
  app process; a `cliclick` inside the wheel applies live to the SwiftUI
  binding (no OK step — unlike text fields, this path is trustworthy).
  Close it via `button 1 of window "Colors"` before driving on.
- **The popover's anchored colour picker (#13) is invisible to AX windows**
  (2026-08-04): the child NSPopover never enumerates in `windows` of the
  process — the count stays 1 while it's plainly on screen. Screenshot to
  confirm it opened, then drive it by `cliclick` screen coords (the wheel
  and preset clicks apply live to the binding, same as the Colors panel).
  The swatch buttons identify by `help` ("Choose colour").
- **NSColorSampler dismisses the MenuBarExtra popover** the moment its
  magnifier overlay appears (both the menu popover and the child picker
  close). The sample still lands — the callback fires and writes through
  the model, and the edit session survives — so verify by reopening the
  popover afterwards, not by watching for it to stay up.
- **cliclick drives SwiftUI drags reliably** (2026-08-04, verifying #155 row
  reorder): `cliclick -e 120 dd:x,y w:250 m:… m:… w:400 du:x2,y2` — a few
  intermediate `m:` moves plus the waits are what make the drag register;
  a bare `dd`/`du` pair does not. Works for `onDrag`/`onDrop` (and
  `.draggable`) in regular windows and for plain `DragGesture`s anywhere.
  The grip images themselves don't enumerate via AX — compute their screen
  points from a screenshot (or from a sibling `AXColorWell`'s position) and
  drag by coordinates, app frontmost. Mid-drag screenshots race the
  reshuffle animation — trust the end state, not the mid-drag frame.
- **The MenuBarExtra popover never delivers internal drag-and-drop**
  (2026-08-04): an `onDrag` from a popover row starts a session (the
  preview appears, then sticks) but no `onDrop`/`DropDelegate` in the same
  popover ever fires, and the stuck session eats the next click — send
  Escape to clear it. That's why the popover's row reorder is a plain
  `DragGesture` (`GestureReorderGrip`), not the system drag the window
  editors use.

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
