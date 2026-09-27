#!/usr/bin/env bash
# run_all_tests.sh — Runs every tests/test_*.gd scenario and prints a summary.
cd "$(dirname "$0")/.."
PASS=0; FAIL=0; FAILED=()
for f in tests/test_*.gd; do
  n=$(basename "$f" .gd)
  { [ "$n" = "test_base" ] || [ "$n" = "test_case" ]; } && continue
  if tools/run_test.sh "$n" > "/tmp/tw_$n.log" 2>&1; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); FAILED+=("$n"); fi
done
echo "PASSED: $PASS  FAILED: $FAIL"
for n in "${FAILED[@]:-}"; do [ -n "$n" ] && { echo "--- $n"; tail -15 "/tmp/tw_$n.log"; }; done
[ "$FAIL" = "0" ]
