#!/usr/bin/env bash
# Component test of the modes of `edgeping`, on the cases that neither play a sound nor draw.

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE="$SCRIPT_DIR/../Sources/Core"
MACOS="$SCRIPT_DIR/../Sources/MacOS"

# Own directory: any installed binary is never touched.
WORK="$(mktemp -d "${TMPDIR:-/tmp}/test-edgeping-modes.XXXXXX")" || exit 1
trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/edgeping"
TEST_TMP="$WORK/tmp"
LOG="$WORK/home/Library/Logs/edgeping/outcomes.log"
mkdir -p "$TEST_TMP"

PASS=0
FAIL=0
test_id=0

assert_eq() {
  local expected="$1" actual="$2" msg="$3"
  test_id=$((test_id + 1))
  if [ "$actual" = "$expected" ]; then
    echo "✓ TEST $test_id: $msg"
    PASS=$((PASS + 1))
  else
    echo "✗ TEST $test_id: $msg (expected: '$expected', got: '$actual')"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Test suite: edgeping modes (no sound, no panel) ==="

SWIFT_SOURCES=("$CORE"/*.swift "$MACOS"/*.swift)
if ! swiftc -O "${SWIFT_SOURCES[@]}" -o "$BIN" 2>"$WORK/swiftc.err"; then
  cat "$WORK/swiftc.err"
  echo "build failed"
  echo "PASSED: 0 FAILED: 1"
  exit 1
fi

# L <stdin> <arguments...>: RC, OUT and ERR of the launch; log and state are reset at every launch.
L() {
  local input="$1"; shift
  rm -rf "$TEST_TMP/edgeping" "$WORK/home"
  RC=0
  printf '%s' "$input" | TMPDIR="$TEST_TMP" HOME="$WORK/home" "$BIN" "$@" \
    >"$WORK/out" 2>"$WORK/err" || RC=$?
  OUT=$(cat "$WORK/out")
  ERR=$(cat "$WORK/err")
}

lines() { if [ -f "$LOG" ]; then wc -l <"$LOG" | tr -d ' '; else echo 0; fi; }
field() { sed -n "s/.* $1=\([^ ]*\).*/\1/p" "$LOG" | head -n 1; }

# Input that the hook mode rejects: no effect, one invalid-input line carrying event=.
rejected_input() {
  local input="$1" msg="$2"
  L "$input" done
  assert_eq "0" "$RC" "$msg: exit code 0"
  assert_eq "" "$OUT$ERR" "$msg: stdout and stderr empty"
  assert_eq "1" "$(lines)" "$msg: exactly one log line"
  assert_eq "invalid-input" "$(field outcome)" "$msg: outcome invalid-input"
  test -n "$(field event)"
  assert_eq "0" "$?" "$msg: the line carries event="
}

rejected_input "" "empty input"
rejected_input "not json" "text that is not JSON"
rejected_input "[]" "empty array"
rejected_input '"x"' "string"
rejected_input "null" "null"

# Arguments that no mode recognises: no event= field, only invalid-arguments.
rejected_arguments() {
  local msg="$1"; shift
  L "" "$@"
  assert_eq "0" "$RC" "$msg: exit code 0"
  assert_eq "" "$OUT$ERR" "$msg: stdout and stderr empty"
  assert_eq "1" "$(lines)" "$msg: exactly one log line"
  assert_eq "invalid-arguments" "$(field outcome)" "$msg: outcome invalid-arguments"
}

rejected_arguments "unknown mode" other
rejected_arguments "sound with malformed event" sound done 1-x
rejected_arguments "alert with malformed event" done /tmp 1-x

# A running non-shell subagent: the hook mode launches neither sound nor alert.
L '{"background_tasks":[{"status":"running","type":"agent"}]}' done
assert_eq "0" "$RC" "running subagent: exit code 0"
assert_eq "" "$OUT$ERR" "running subagent: stdout and stderr empty"
assert_eq "0" "$(lines)" "running subagent: no log line"
assert_eq "" "$(pgrep -f "$BIN sound" || true)" "running subagent: no sound process"
assert_eq "" "$(pgrep -f "$BIN done" || true)" "running subagent: no alert process"

echo ""
echo "PASSED: $PASS FAILED: $FAIL"
[ "$FAIL" -eq 0 ]
