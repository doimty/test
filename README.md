# ProMotion120

Full-function ProMotion tweak for `com.promotion120`, with the validated notification-banner 120Hz fix merged into the main source.

## Status

- Current source is the full-function implementation plus the cleaned notification-banner path derived from the validated `bannerdisplay5` test line.
- Diagnostic plist logging and test counters have been removed.
- Package version: `1.0.0-36+fullnotify1`.

## Full-function behavior

Restored/kept global behavior:

- SpringBoard ProMotion policy maximum/effective refresh rate hooks.
- Low-power-mode bypass hooks:
  - `SBLowPowerModeController`
  - `_CDBatterySaver`
  - `NSProcessInfo`
- `SBDisplayRefreshRateController` maximum refresh hook.
- `UIScreen.maximumFramesPerSecond` 120Hz spoof on ProMotion devices.
- Global `CADisplayLink` 120Hz range / frame interval behavior.
- Global `CAAnimation` 120Hz frame-rate range behavior.
- Metal present-related hooks:
  - `CAMetalLayer.maximumDrawableCount`
  - `CAMetalDrawable presentAfterMinimumDuration:`
  - `MTLCommandBuffer presentDrawable:afterMinimumDuration:`

## Notification-banner fix

Validated notification route:

- Targets real notification banner presentation in SpringBoard.
- Confirms `SBBannerWindow` before applying banner-specific display-level 120Hz behavior.
- During banner lifetime, creates and holds a `CADynamicFrameRateSource` on the main `CADisplay`.
- Applies:
  - `setHighFrameRateReasons:count:`
  - `setPreferredFrameRateRange:{80,120,120}`
- Uses raw presentable identity to ignore stale disappear events from previous notifications in stacked/continuous notification flows.
- Keeps the display-level request alive through the exit animation with bounded exit polling.
- Releases the request after window disappearance confirmation or a 4 second safety timeout.
- Keeps lightweight `CALayer addAnimation:` support scoped to the confirmed banner window.

## Validation baseline

Validated behavior from the test line:

- Single notification banner enters and exits at 120Hz by visual testing.
- Continuous notification stacks no longer drop the final banner exit to 60Hz by visual testing.
- Test logs showed clean lifecycle accounting before logging was removed:
  - `displaySourceCreate == displaySourceRelease`
  - `displaySourceActive = false`
  - stale/late disappear events occur during stacked notifications and are intentionally ignored.

## Notes

The notification fix is intentionally narrow inside SpringBoard even though the package remains full-function. It does not reintroduce diagnostic plist writes or broad runtime/policy probing from the experimental branches.
