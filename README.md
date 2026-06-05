# ProMotion120

Recovered source skeleton for `com.promotion120` from the uploaded `1.0.0-17+debug` rootless deb.

## Status

- Local reconstruction only.
- Do **not** publish to the jailbreak source until tested.
- Baseline package: `references/com.promotion120_1.0.0-17+debug_iphoneos-arm64.deb`.

## Recovered behavior

- Forces SpringBoard ProMotion policy maximum/effective refresh rate to 120.
- Disables frame-rate limiting and low-power-mode checks exposed through common APIs.
- Forces 120Hz-related behavior for `UIScreen`, `CADisplayLink`, `CAAnimation`, `CAMetalLayer`, `CAMetalDrawable`, and `MTLCommandBuffer` when a 120Hz display mode is detected.
- Injection filter matches the uploaded package:
  - `com.apple.UIKit`
  - `com.apple.springboard`
  - `com.apple.UserNotificationsUIServer`
  - `com.apple.springboard.SpringBoardOutofCallUI`

## Known weak spots from testing

- Notification banners still do not fully hold 120Hz.
- WeChat image viewer drops to around 40 FPS at the moment an image opens.

## Next maintenance steps

1. Build rootless locally or via CI and compare package contents.
2. Add temporary debug logging around:
   - `com.apple.UserNotificationsUIServer`
   - `com.apple.springboard`
   - `com.tencent.xin`
   - `CADisplayLink`, `CAAnimation`, `CALayer`, and Metal present paths.
3. Add targeted fixes for notification banners and WeChat image viewer.
4. Only then decide on a formal version such as `1.0.0-18`.
