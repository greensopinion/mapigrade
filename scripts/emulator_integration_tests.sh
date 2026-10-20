#!/usr/bin/env bash
# Runs the test harness's integration tests on an Android emulator, for the
# x86_64 job of consumer-build.yml (design D106 of the publish-readiness
# change). Run it in packages/test_harness.
#
#   scripts/emulator_integration_tests.sh [test-file]...
#
# Without arguments it runs every integration_test/*_test.dart. With
# REPEAT=<n> in the environment it runs the files n times. DEVICE=<id> selects
# another device than emulator-5554.
#
# The script first waits until the device shows no lock screen. Each test file
# runs in its own flutter test call, which installs the test harness's APK,
# with a timeout of 15 minutes where the timeout command exists. A file in
# which no test finished runs once more; a file in which a test failed
# doesn't. For a failed file the script saves the logcat, the lock screen and
# power state, and the JSON results in build/logcat/<file>-<run>*. It runs
# every file and fails if one of them failed.
set -uo pipefail

device=${DEVICE:-emulator-5554}
# The tests lay out widgets at least 400 logical pixels wide, and the default
# emulator screen is 320 wide. A density of 160 makes one logical pixel one
# physical pixel, which keeps software rendering cheap.
adb -s "$device" shell wm size 800x1280
adb -s "$device" shell wm density 160
# The settings persist on the device, so the script restores them.
trap 'adb -s "$device" shell wm size reset; adb -s "$device" shell wm density reset' EXIT

if [[ $# -gt 0 ]]; then
  tests=("$@")
else
  tests=(integration_test/*_test.dart)
fi

# Runs a command with a timeout of 15 minutes. macOS has no timeout command;
# there the command runs without one.
with_timeout() {
  if command -v timeout > /dev/null; then
    timeout 15m "$@"
  else
    "$@"
  fi
}

# Waits until the device has booted and shows no lock screen. Behind the lock
# screen the activity gets no frames, and a test never starts.
wait_until_ready() {
  adb -s "$device" wait-for-device
  until [[ "$(adb -s "$device" shell getprop sys.boot_completed | tr -d '\r')" == 1 ]]; do
    sleep 2
  done
  adb -s "$device" shell input keyevent KEYCODE_WAKEUP
  adb -s "$device" shell svc power stayon true
  local attempt
  for attempt in $(seq 1 30); do
    adb -s "$device" shell wm dismiss-keyguard
    if adb -s "$device" shell dumpsys window | grep -q "isKeyguardShowing=false"; then
      return 0
    fi
    sleep 2
  done
  echo "The lock screen is still showing on $device" >&2
}

# Runs one test file, writes its results as JSON to $2 and the tool's verbose
# log to $3, and prints the test output without the verbose lines. Returns the
# exit status of flutter test. A run in which no test has started after 8
# minutes, the first build included, is stopped: the tool hasn't connected to
# the app, whose tests wait for it.
run_file() {
  adb -s "$device" logcat -c
  rm -f "$2"
  with_timeout flutter test -v "$1" -d "$device" --file-reporter "json:$2" \
    > "$3" 2>&1 &
  local flutter_pid=$! waited=0
  # The subshell's stderr is discarded, where it reports that tail was
  # stopped.
  (tail -n +1 -f "$3" | grep --line-buffered -vE '^\[[ +0-9]*( ms)?\]') \
    2> /dev/null &
  local tail_pid=$!
  while kill -0 "$flutter_pid" 2> /dev/null; do
    if ((waited >= 480)) && ! started_a_test "$2"; then
      echo "No test started in 8 minutes; stopping the run" >&2
      kill_tree "$flutter_pid"
      break
    fi
    sleep 5
    waited=$((waited + 5))
  done
  wait "$flutter_pid"
  local status=$?
  sleep 1
  kill_tree "$tail_pid"
  return $status
}

# Stops process $1 and its descendants.
kill_tree() {
  local child
  for child in $(pgrep -P "$1"); do kill_tree "$child"; done
  kill "$1" 2> /dev/null
}

# Whether the JSON results in $1 report a started test.
started_a_test() {
  grep '"type":"testStart"' "$1" 2> /dev/null | grep -qv '"name":"loading '
}

# Whether the JSON results in $1 report a finished test.
ran_a_test() {
  grep '"type":"testDone"' "$1" 2> /dev/null | grep -q '"hidden":false'
}

# Saves the logcat, the lock screen and power state, the JSON results ($2) and
# the tool's verbose log ($3) of a failed run in build/logcat/ with the prefix
# $1.
save_evidence() {
  adb -s "$device" logcat -d > "build/logcat/$1.txt"
  adb -s "$device" shell dumpsys window | grep -E "isKeyguardShowing|mCurrentFocus|mDreamingLockscreen" > "build/logcat/$1-window.txt"
  adb -s "$device" shell dumpsys power | grep -E "mWakefulness=" >> "build/logcat/$1-window.txt"
  cp "$2" "build/logcat/$1.json" 2> /dev/null
  cp "$3" "build/logcat/$1-flutter.txt" 2> /dev/null
}

wait_until_ready
mkdir -p build/logcat
status=0
failures=0
for run in $(seq 1 "${REPEAT:-1}"); do
  for test in "${tests[@]}"; do
    name="$(basename "$test" .dart)-$run"
    results="build/logcat/$name-results.json"
    verbose="build/logcat/$name-verbose.txt"
    echo "== $test, run $run"
    if run_file "$test" "$results" "$verbose"; then
      continue
    fi
    # A run in which no test finished never reached the tests: the tool
    # didn't connect to the app, or the app didn't start them. It runs once
    # more. A run in which a test failed doesn't.
    if ! ran_a_test "$results"; then
      echo "NO TESTS RAN: $test, run $run; running it again" >&2
      save_evidence "$name-no-tests" "$results" "$verbose"
      wait_until_ready
      if run_file "$test" "$results" "$verbose"; then
        continue
      fi
    fi
    echo "FAIL: $test, run $run" >&2
    save_evidence "$name" "$results" "$verbose"
    status=1
    failures=$((failures + 1))
  done
done
echo "$failures of $((${REPEAT:-1} * ${#tests[@]})) test file runs failed"
exit $status
