#!/usr/bin/env bash
# Builds and runs every suite in Tests/, then the component test of the modes.
set -uo pipefail
cd "$(dirname "$0")/.."

if grep -nE '^\s*import\s+(AppKit|CoreGraphics|QuartzCore|Cocoa)' Sources/Core/*.swift; then
  echo "test.sh: Sources/Core must not import Apple UI frameworks" >&2; exit 1
fi

work="$(mktemp -d "${TMPDIR:-/tmp}/edgeping-test.XXXXXX")"; trap 'rm -rf "$work"' EXIT
sources=()
for f in Sources/Core/*.swift Sources/MacOS/*.swift; do
  [ "$f" != Sources/MacOS/main.swift ] && sources+=("$f")
done

status=0
for dir in Tests/*/; do
  suite="$(basename "$dir")"
  if swiftc "${sources[@]}" Tests/$suite/*.swift -o "$work/$suite" && "$work/$suite" | tail -1; then
    :
  else
    echo "test.sh: suite $suite failed" >&2; status=1
  fi
done
bash Tests/modes.sh | tail -1 || { echo "test.sh: suite modes failed" >&2; status=1; }
exit "$status"
