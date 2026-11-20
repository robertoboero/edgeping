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

# Options reach the program as CLAUDE_PLUGIN_OPTION_<KEY>; an inherited one would change every launch.
for name in $(compgen -e | grep '^CLAUDE_PLUGIN_OPTION_'); do unset "$name"; done

# This input makes the hook mode stop after parsing the options, so no case here plays or draws.
QUIET_INPUT='{"background_tasks":[{"status":"running","type":"agent"}]}'

# set_option <key> <value>: gives one option to the next launches, as Claude Code does.
set_option() { export "CLAUDE_PLUGIN_OPTION_$(printf '%s' "$1" | tr 'a-z' 'A-Z')=$2"; }
clear_option() { unset "CLAUDE_PLUGIN_OPTION_$(printf '%s' "$1" | tr 'a-z' 'A-Z')"; }
logged_options() { sed -n 's/.* option=\([^ ]*\).*/\1/p' "$LOG" | sort | tr '\n' ' '; }
log_mentions() { grep -cF -- "$1" "$LOG" || true; }

# RF-08: one option-invalid line carrying option= (never the value) and event=; no output, exit 0.
invalid_option() {
  local key="$1" value="$2" msg="$3"
  set_option "$key" "$value"
  L "$QUIET_INPUT" done
  clear_option "$key"
  assert_eq "0" "$RC" "$msg: exit code 0"
  assert_eq "" "$OUT$ERR" "$msg: stdout and stderr empty"
  assert_eq "1" "$(lines)" "$msg: exactly one log line"
  assert_eq "option-invalid" "$(field outcome)" "$msg: outcome option-invalid"
  assert_eq "$key" "$(field option)" "$msg: the line names the option"
  assert_eq "0" "$(log_mentions "$value")" "$msg: the value is not in the log"
  test -n "$(field event)"
  assert_eq "0" "$?" "$msg: the line carries event="
}

invalid_option sound_enabled "maybe" "invalid sound_enabled"
invalid_option strip_enabled "maybe" "invalid strip_enabled"
invalid_option sound_done "NoSuchSound" "unknown sound_done"
invalid_option sound_question "../Glass" "path-like sound_question"
invalid_option color_done "#abc" "short color_done"
invalid_option color_question "abcdef" "color_question without #"
invalid_option duration_seconds "2.9" "duration_seconds below range"
invalid_option stay_until_visited "forse" "invalid stay_until_visited"
invalid_option label_enabled "maybe" "invalid label_enabled"
invalid_option duration_seconds "60.1" "duration_seconds above range"

# Valid values at the edges, and empty values, are not reported.
valid_option() {
  local key="$1" value="$2" msg="$3"
  set_option "$key" "$value"
  L "$QUIET_INPUT" done
  clear_option "$key"
  assert_eq "0" "$RC" "$msg: exit code 0"
  assert_eq "" "$OUT$ERR" "$msg: stdout and stderr empty"
  assert_eq "0" "$(lines)" "$msg: no log line"
}

valid_option duration_seconds "3" "duration_seconds at the lower edge"
valid_option duration_seconds "60" "duration_seconds at the upper edge"
valid_option color_done "#abcdef" "lowercase color_done"
valid_option stay_until_visited "TRUE" "uppercase boolean"
valid_option sound_done "" "empty sound_done"

# All nine invalid at once: one line per option, and nothing else.
ALL_KEYS="color_done color_question duration_seconds label_enabled sound_done sound_enabled sound_question stay_until_visited strip_enabled "
for key in $ALL_KEYS; do set_option "$key" "zz"; done
L "$QUIET_INPUT" done
for key in $ALL_KEYS; do clear_option "$key"; done
assert_eq "0" "$RC" "all options invalid: exit code 0"
assert_eq "" "$OUT$ERR" "all options invalid: stdout and stderr empty"
assert_eq "9" "$(lines)" "all options invalid: one log line per option"
assert_eq "$ALL_KEYS" "$(logged_options)" "all options invalid: each option once"

# RF-03: with both switches off no child process is launched. An input that plays when they are on.
set_option sound_enabled false
set_option strip_enabled false
L '{"cwd":"/tmp"}' done
clear_option sound_enabled
clear_option strip_enabled
assert_eq "0" "$RC" "both switches off: exit code 0"
assert_eq "" "$OUT$ERR" "both switches off: stdout and stderr empty"
assert_eq "" "$(pgrep -f "$BIN" || true)" "both switches off: no process of the binary"
assert_eq "0" "$(lines)" "both switches off: no log line"

# RNF-03: the log is private to the owner and never holds an option value, valid or not.
old_umask=$(umask)
umask 000
set_option color_done "#123456"
set_option duration_seconds "33.25"
set_option sound_done "NoSuchSound"
L "$QUIET_INPUT" done
clear_option color_done
clear_option duration_seconds
clear_option sound_done
umask "$old_umask"
assert_eq "1" "$(lines)" "log content: only the invalid option is logged"
assert_eq "600" "$(stat -f %Lp "$LOG")" "log file mode is 0600 even under umask 000"
assert_eq "0" "$(log_mentions "#123456")" "valid color value is not in the log"
assert_eq "0" "$(log_mentions "33.25")" "valid duration value is not in the log"
assert_eq "0" "$(log_mentions "NoSuchSound")" "invalid sound value is not in the log"

echo ""
echo "PASSED: $PASS FAILED: $FAIL"
[ "$FAIL" -eq 0 ]
