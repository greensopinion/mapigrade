#!/usr/bin/env bash
# Runs the test harness's integration tests on the Android emulator
# emulator-5554, for the x86_64 job of consumer-build.yml (design D106 of the
# publish-readiness change). Run it in packages/test_harness.
#
#   scripts/emulator_integration_tests.sh [test-file]...
#
# Without arguments it runs every integration_test/*_test.dart. With
# REPEAT=<n> in the environment it runs the files n times.
#
# Each test file runs in its own flutter test call, which installs the test
# harness's APK, with a timeout of 15 minutes. For a file that fails, the script
# saves the emulator's logcat in build/logcat/<file>-<run>.txt. It runs every
# file and fails if one of them failed.
set -uo pipefail

device=emulator-5554
# The tests lay out widgets at least 400 logical pixels wide, and the default
# emulator screen is 320 wide. A density of 160 makes one logical pixel one
# physical pixel, which keeps software rendering cheap.
adb -s "$device" shell wm size 800x1280
adb -s "$device" shell wm density 160

if [[ $# -gt 0 ]]; then
  tests=("$@")
else
  tests=(integration_test/*_test.dart)
fi

mkdir -p build/logcat
status=0
failures=0
for run in $(seq 1 "${REPEAT:-1}"); do
  for test in "${tests[@]}"; do
    echo "== $test, run $run"
    adb -s "$device" logcat -c
    if ! timeout 15m flutter test "$test" -d "$device"; then
      echo "FAIL: $test, run $run" >&2
      adb -s "$device" logcat -d > "build/logcat/$(basename "$test" .dart)-$run.txt"
      status=1
      failures=$((failures + 1))
    fi
  done
done
echo "$failures of $((${REPEAT:-1} * ${#tests[@]})) test file runs failed"
exit $status
