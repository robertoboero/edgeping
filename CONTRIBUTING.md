# Contributing

Thanks for your interest in edgeping. This document explains how to build, test and propose changes.

## Requirements

- macOS with the Xcode command line tools (`swiftc`, `lipo`, `codesign`, `shasum`).

## Build

```sh
bash scripts/build.sh
```

This compiles the universal, ad-hoc signed binary from `Sources/` into `dist/`. To build somewhere else, pass a directory:

```sh
bash scripts/build.sh --out "$TMPDIR/edgeping-out"
```

## Test

```sh
bash scripts/test.sh
```

This builds and runs every suite in `Tests/`, then the component test of the modes. It exits non-zero if any suite fails.

## Rules for changes

- Open an issue to discuss a new option or a new behaviour before writing code. Options are added only after that discussion.
- `Sources/Core` must not import AppKit, CoreGraphics, QuartzCore or Cocoa. `scripts/test.sh` enforces this.
- Every bug fix comes with a test that reproduces the bug and fails before the fix.
- Keep comments in English and short: say why, not what.
- Do not commit personal data: no user names, home paths, client or project names in code, tests or fixtures. Tests use neutral names such as `project-a`, and a placeholder home directory.

## Pull requests

Describe the change and how you checked it, and run `bash scripts/build.sh` and `bash scripts/test.sh` before you open the pull request.
