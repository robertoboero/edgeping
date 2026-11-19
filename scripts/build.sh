#!/usr/bin/env bash
# Builds the universal, ad-hoc signed edgeping binary from Sources/.
set -euo pipefail
cd "$(dirname "$0")/.."
out=dist
if [ "${1:-}" = "--out" ]; then out="${2:?--out needs a directory}"; fi
for tool in swiftc lipo codesign shasum; do
  command -v "$tool" >/dev/null || { echo "build.sh: missing $tool (install the Xcode command line tools)" >&2; exit 1; }
done
sources=(Sources/Core/*.swift Sources/MacOS/*.swift)
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
swiftc --version | head -1
for arch in arm64 x86_64; do
  swiftc -O -target "$arch-apple-macos13" "${sources[@]}" -o "$work/edgeping-$arch"
done
mkdir -p "$out"
lipo -create "$work/edgeping-arm64" "$work/edgeping-x86_64" -output "$out/edgeping"
codesign --force --sign - "$out/edgeping"
printf '%s\n' "${sources[@]}" | LC_ALL=C sort | xargs shasum -a 256 > "$out/SOURCES.sha256"
lipo -archs "$out/edgeping"
