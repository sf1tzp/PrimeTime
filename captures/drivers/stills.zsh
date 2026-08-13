#!/bin/zsh
# All still shots (dark + light variants) per captures/shots.yaml, except the
# popover still (see popover-motion.zsh — it needs the timers stopped).
#
# Precondition: MomentTally --demo running, onboarding dismissed, main window
# open. Run: captures/drivers/stills.zsh [raw-dir]
# Staging side effects: week navigator on previous week, History on
# Last 30 days type×project Separately, Marks proj row expanded — all
# harmless for the recordings that follow.
set -e
source "${0:a:h}/lib.zsh"
RAW=${1:-$REPO_ROOT/captures/raw}
mkdir -p "$RAW"

tab() { ax "click button \"$1\" of toolbar 1 of window \"Moment Tally\"" >/dev/null; sleep 1.5; }

stage_and_shoot() { # <suffix: "" | "-light">
  local sfx=$1
  tab Launcher;             still "$RAW/launcher$sfx.png"     "Moment Tally"
  tab Tallies;              still "$RAW/label-sets$sfx.png"   "Moment Tally"
  tab Log;                  still "$RAW/log$sfx.png"          "Moment Tally"
  tab Calendar; sleep 0.5;  still "$RAW/calendar$sfx.png"     "Moment Tally"
  tab History;  sleep 0.5;  still "$RAW/history$sfx.png"      "Moment Tally"
  tab Marks;                still "$RAW/label-review$sfx.png" "Moment Tally"
  tab Settings;             still "$RAW/settings$sfx.png"     "Moment Tally"
}

frontmost; sleep 0.5
main_origin
assert_2x

# --- one-time staging (dark pass) ------------------------------------------
# Log/Calendar: most recent full week -> one step back from Today.
tab Log
ax 'click button 1 of group 1 of group 1 of window "Moment Tally"' >/dev/null; sleep 1

# History: Range = Last 30 days; right donut = project (left defaults to type).
tab History
ax 'click pop up button 1 of group 1 of group 1 of window "Moment Tally"' >/dev/null
menu_pick "Last 30 days"; sleep 1
# Right Group-by AX-aliases to the left in side-by-side mode — coordinate
# click (rehearsed offset), then menu type-select.
rmove 505 130; sleep 0.2; rapproach 505 159
menu_pick "project"; sleep 1

# Marks: expand the drifted `proj` key (bottom row of the outline).
tab Marks
last_row_y=$(ax 'get position of rows of outline 1 of scroll area 1 of group 1 of group 1 of window "Moment Tally"' | tr ',' '\n' | tail -1 | tr -d ' ')
cliclick "m:$((WX+16)),$((last_row_y-20))" w:150 "m:$((WX+16)),$((last_row_y+13))" w:200 "c:$((WX+16)),$((last_row_y+13))"
sleep 1

# --- dark pass --------------------------------------------------------------
stage_and_shoot ""

# --- light pass (staging persists across the appearance flip) ---------------
osascript -e 'tell app "System Events" to tell appearance preferences to set dark mode to false'
sleep 3; frontmost; sleep 0.5
tab Settings;             still "$RAW/settings-light.png"   "Moment Tally"
tab Tallies;              still "$RAW/label-sets-light.png" "Moment Tally"
tab Log;                  still "$RAW/log-light.png"        "Moment Tally"
tab Calendar; sleep 0.5;  still "$RAW/calendar-light.png"   "Moment Tally"
tab History;  sleep 0.5;  still "$RAW/history-light.png"    "Moment Tally"
osascript -e 'tell app "System Events" to tell appearance preferences to set dark mode to true'
sleep 2

echo "stills done -> $RAW"
ls -la "$RAW"/*.png | awk '{print $NF}' | while read f; do
  sips -g pixelWidth "$f" | awk -v f="$f" '/pixelWidth/{print f": "$2"px"}'
done
