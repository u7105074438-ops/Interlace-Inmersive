#!/usr/bin/env bash
# screenshot.sh — Runs the game under a virtual display and saves PNG screenshots.
# Usage: tools/screenshot.sh <out_dir> [scenario] [extra user args...]
#   scenario = name understood by src/util/autopilot.gd (e.g. "boot", "wing_3b", "stellar_os").
# The game reads --autopilot=<scenario> and --shots=<dir> from OS.get_cmdline_user_args().
cd "$(dirname "$0")/.."
OUT="${1:?out dir}"; SCEN="${2:-boot}"; shift 2 || true
mkdir -p "$OUT"
( flock -w 300 9; timeout 240 godot --headless --path . --import >/dev/null 2>&1 ) 9>/tmp/the_worker_import.lock
timeout "${SHOT_TIMEOUT:-120}" xvfb-run -a -s "-screen 0 1920x1080x24" \
  godot --path . --rendering-driver opengl3 --resolution 1600x900 -- --autopilot="$SCEN" --shots="$OUT" "$@" 2>&1 \
  | grep -v -E "audio|ALSA|init_output_device" | tail -40
ls -la "$OUT"
