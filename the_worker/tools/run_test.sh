#!/usr/bin/env bash
# run_test.sh — Runs one headless validation scenario (Part VII §21).
# Usage: tools/run_test.sh test_name   (without .gd)   -> exit code 0 = pass
# Re-imports the project first (needed so class_name registry is fresh).
# The import step is serialized with flock so parallel agents do not collide.
set -u
cd "$(dirname "$0")/.."
NAME="${1:?usage: run_test.sh test_name}"
NAME="${NAME%.gd}"
(
  flock -w 300 9 || { echo "could not get import lock"; exit 99; }
  timeout 240 godot --headless --path . --import >/tmp/tw_import_$$.log 2>&1
  grep -E "SCRIPT ERROR|Parse Error|ERROR: Failed" /tmp/tw_import_$$.log | head -20
  rm -f /tmp/tw_import_$$.log
) 9>/tmp/the_worker_import.lock
timeout "${TEST_TIMEOUT:-180}" godot --headless --path . --script "res://tests/${NAME}.gd" 2>&1 \
  | grep -v -E "audio_driver_alsa|All audio drivers failed|audio_server.cpp|init_output_device|^\s*at: (initialize|init_output_device)"
RC=${PIPESTATUS[0]}
if [ "$RC" = "0" ]; then echo "[run_test] ${NAME}: PASS"; else echo "[run_test] ${NAME}: FAIL (exit $RC)"; fi
exit $RC
