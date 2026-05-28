# DayNightSwitch

Dynamic UISwitch styles for jailbroken iOS, based on Finn Gaida's DayNightSwitch and adapted as a Theos tweak.

## iOS 15 compatibility notes

This fork keeps the safer upstream-style `didMoveToSuperview` mounting path and avoids the iOS 16-only/private `setOn:animated:notifyingVisualElement:` hook. It also avoids calling the private `UISwitch` `_impactFeedbackGenerator` selector directly.

## Build

GitHub Actions builds rootless and roothide packages.

Manual build with Theos:

```sh
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless SDKVERSION=16.5
```
