# ProMotion120

Notification-banner focused ProMotion tweak for `com.promotion120`.

## Status

- Current source is the cleaned notification-banner implementation derived from the validated `bannerdisplay5` test line.
- Diagnostic plist logging and test counters have been removed.
- Injection is limited to SpringBoard.

## Current behavior

- Targets real notification banner presentation in SpringBoard.
- Confirms `SBBannerWindow` before applying banner-specific 120Hz behavior.
- During banner lifetime, creates and holds a `CADynamicFrameRateSource` on the main `CADisplay`.
- Applies:
  - `setHighFrameRateReasons:count:`
  - `setPreferredFrameRateRange:{80,120,120}`
- Uses raw presentable identity to ignore stale disappear events from previous notifications in stacked/continuous notification flows.
- Keeps the display-level request alive through the exit animation with bounded exit polling.
- Releases the request after window disappearance confirmation or a 4 second safety timeout.
- Keeps lightweight `CAAnimation` / `CADisplayLink` / `CALayer addAnimation:` support scoped to the confirmed banner window.

## Validation baseline

Validated behavior from the test line:

- Single notification banner enters and exits at 120Hz by visual testing.
- Continuous notification stacks no longer drop the final banner exit to 60Hz by visual testing.
- Test logs showed clean lifecycle accounting before logging was removed:
  - `displaySourceCreate == displaySourceRelease`
  - `displaySourceActive = false`
  - stale/late disappear events occur during stacked notifications and are intentionally ignored.

## Notes

This cleaned source intentionally does **not** include the older broad/global hooks such as SpringBoard ProMotion policy overrides, `UIScreen.maximumFramesPerSecond` spoofing, Metal hooks, or low-power-mode overrides. The notification-banner path is kept narrow because the validated fix is `SBBannerWindow + CADynamicFrameRateSource` rather than broad policy probing.
