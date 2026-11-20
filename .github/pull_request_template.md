## What changes

<!-- One or two sentences: what behaves differently after this change. -->

## Why

<!-- Link the issue where this was discussed. New options need a discussed issue first. -->

## Checks

- [ ] `bash scripts/build.sh --out "$TMPDIR/edgeping"` succeeds
- [ ] `bash scripts/test.sh` passes
- [ ] A bug fix comes with a test that fails without it
- [ ] `Sources/Core` does not import AppKit, CoreGraphics, QuartzCore or Cocoa
- [ ] If `Sources/` changed, `dist/` was rebuilt with `bash scripts/build.sh` and `bash scripts/check-dist.sh` passes
