#!/bin/zsh
# History tab recording (~25s): side-by-side type×project -> in Groups ->
# type×client -> meeting×client. Beats verified 2026-08-13.
#
# Precondition: app running, History tab staged by stills.zsh (Last 30 days,
# type vs project, Count marks Separately). This script re-asserts that state,
# records, then restores it. Run: captures/drivers/history-motion.zsh [out.mov]
set -e
source "${0:a:h}/lib.zsh"
OUT=${1:-$REPO_ROOT/captures/raw/history-motion.mov}

frontmost; sleep 0.5
main_origin
read MW MH < <(ax 'get position of window "Moment Tally"' >/dev/null; ax 'get size of window "Moment Tally"' | tr -d ',')
[[ $MW == 780 ]] || echo "WARN: main window ${MW}pt wide (offsets assume 780)"
ax 'click button "History" of toolbar 1 of window "Moment Tally"' >/dev/null; sleep 1

# Re-assert start state (idempotent; combined-mode popups are NOT aliased).
restore() {
  if [[ $(ax 'get value of radio buttons of radio group 1 of group 1 of group 1 of window "Moment Tally"') == 0* ]]; then
    # combined mode: set pickers there, then flip back to Separately
    ax 'click pop up button 1 of scroll area 1 of group 1 of group 1 of window "Moment Tally"' >/dev/null
    menu_pick "type"; sleep 0.6
    ax 'click pop up button 2 of scroll area 1 of group 1 of group 1 of window "Moment Tally"' >/dev/null
    menu_pick "project"; sleep 0.6
    rmove 595 90; sleep 0.2; rclick 595 108; sleep 1     # Separately (y-centre of the 24pt group!)
  fi
}
restore

drive() {
  sleep 3
  rmove 679 90; sleep 0.2; rclick 679 108; sleep 2.5     # Count marks -> in Groups
  rmove 427 128; sleep 0.15; rapproach 427 153; menu_pick "client"; sleep 3    # right picker
  rapproach 200 153; menu_pick "meeting"; sleep 4                              # left picker
  rmove 293 288
}

take "$OUT" 34 "$WX,$WY,780,648" drive
restore
