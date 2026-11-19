#!/usr/bin/env bash
# Checks that the committed dist/ matches Sources/ and is a signed universal binary.
set -uo pipefail
cd "$(dirname "$0")/.."

fail() { echo "check-dist.sh: $1" >&2; exit 1; }

for tool in lipo codesign shasum git; do
  command -v "$tool" >/dev/null || fail "missing $tool"
done
[ -f dist/edgeping ] || fail "dist/edgeping not found (run scripts/build.sh)"
[ -f dist/SOURCES.sha256 ] || fail "dist/SOURCES.sha256 not found (run scripts/build.sh)"

sources=(Sources/Core/*.swift Sources/MacOS/*.swift)
actual="$(printf '%s\n' "${sources[@]}" | LC_ALL=C sort | xargs shasum -a 256)" || fail "cannot hash the sources"
[ "$actual" = "$(cat dist/SOURCES.sha256)" ] || fail "dist/SOURCES.sha256 does not match Sources/ (rebuild with scripts/build.sh)"

archs="$(lipo -archs dist/edgeping)" || fail "lipo cannot read dist/edgeping"
for arch in x86_64 arm64; do
  case " $archs " in *" $arch "*) ;; *) fail "dist/edgeping lacks $arch (found: $archs)" ;; esac
done

codesign --verify dist/edgeping || fail "dist/edgeping has no valid signature"

mode="$(git ls-files -s dist/edgeping | cut -d' ' -f1)"
[ "$mode" = "100755" ] || fail "dist/edgeping must be tracked with mode 100755 (found: ${mode:-untracked})"

echo "check-dist.sh: dist/ is up to date"
