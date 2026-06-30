# ObjC Port Build Notes

This branch is migrating Insulation away from Swift/Orion toward Objective-C/C runtime hooks.

## Safety Model

- Default build path remains Swift/Orion.
- ObjC path is opt-in via `USE_OBJC_PORT=1`.
- ObjC packaging uses shadow files and temporary swaps:
  - `control.objc` removes `dev.theos.orion` for ObjC packages.
  - `scripts/objc-packaging/Info.plist` changes `NSPrincipalClass` to `RootListController`.
  - `scripts/objc-packaging/InsulationPrefs.plist` changes PreferenceLoader `detail` to `RootListController`.
- `scripts/build-objc-package.sh` restores original files on exit.

## Static Gate

Run before each ObjC migration step:

```sh
scripts/check-objc-port.sh
```

The gate checks:

- ObjC source expansion does not include Swift files.
- ObjC main tweak source expansion excludes `Sources/insulationC/Tweak.m` / `orion_init()`.
- Key runtime hook selectors are present.
- Local `Preferences` headers exist for Linux/Theos builds.
- Prefs key/notification semantic tokens are preserved.
- ObjC shadow plists do not live under packaged PreferenceLoader paths.

## Linux/Theos Setup

Host tools needed:

- `git`
- `make`
- `clang` / LLVM
- `dpkg-deb`
- `fakeroot`
- `ldid`
- `rsync`
- `plistutil` with `libplist-2.0.so.4` available at runtime
- `curl` / `tar` / `xz`
- Theos
- iPhoneOS SDK in `$THEOS/sdks`

Bootstrap helper:

```sh
scripts/setup-linux-theos-env.sh
```

The setup helper stops early if required host tools are missing. Install those first, then re-run it. If GitHub is unreachable after host tools are present, the script may fail while cloning Theos. That is an environment/network blocker, not an Insulation source failure.

## ObjC Build Probe

```sh
export THEOS=/root/.openclaw/workspace/toolchains/theos
export PATH=/root/.openclaw/workspace/toolchains/bin:$THEOS/bin:$PATH
scripts/check-objc-port.sh
make USE_OBJC_PORT=1 -n
scripts/build-objc-package.sh rootless
```

## Current Local Build Result

The current OpenClaw host has a working local Linux/Theos environment under `/root/.openclaw/workspace/toolchains/theos`, with `iPhoneOS16.5.sdk` installed. The ObjC rootless package build has completed successfully:

```sh
export THEOS=/root/.openclaw/workspace/toolchains/theos
export PATH=/root/.openclaw/workspace/toolchains/bin:$THEOS/bin:$THEOS/toolchain/linux/iphone/bin:$PATH
scripts/check-objc-port.sh
scripts/build-objc-package.sh rootless
```

Result:

```text
packages/com.be-huge.insulation_0.1.22-objc-port_iphoneos-arm64.deb
```

The package includes the rootless paths for the main tweak dylib, PreferenceBundle, PreferenceLoader plist, and Control Center bundle under `/var/jb`.

## Current ObjC Port Status

Branch: `objc-port-full`

The ObjC port is still an opt-in shadow implementation. Default builds remain Swift/Orion unless `USE_OBJC_PORT=1` or `scripts/build-objc-package.sh` is used.

### Implemented ObjC Shadow Areas

- Main tweak runtime init:
  - `Sources/insulationObjC/TweakInit.m`
  - Installs runtime hooks with a constructor.
  - Registers Darwin notifications for apply/runtime state/restart.
  - Replaces Swift/Orion `orion_init()` only in ObjC mode.
- Main tweak runtime hooks:
  - `Sources/insulationObjC/InsulationRuntimeHooks.m`
  - Uses Objective-C runtime hook replacement and stores original IMPs.
  - Covers `NSDictionary`, `ComponentControl`, `CPMSHelper`, `CommonProduct`, and `MitigationController` hook families.
- Power helper parity:
  - `Sources/insulationObjC/InsulationPowerHelper.m`
  - Preserves key Swift behavior for `thermalPowerMode`, `lowPower`, `fullPower`, prevent-dimming, notification suppression, pocket sunlight, sunlight override, and fullPower restore paths.
- Thermal dictionary patching:
  - `Sources/insulationObjC/InsulationDictHelper.m`
  - Recursively patches thermal dictionaries and keeps strict Swift-like integer parsing for strings.
- PreferenceBundle ObjC shadow:
  - `InsulationPrefs/Sources/InsulationPrefsObjC/*`
  - Keeps the CPU mode menu, preference keys, runtime state notification, execute notification, and restart notification behavior.
- Packaging shadows:
  - `control.objc`
  - `scripts/objc-packaging/Info.plist`
  - `scripts/objc-packaging/InsulationPrefs.plist`

### Protected Behavior

`fullPower` remains the only mode that forces the CPU/package power restore hooks. Prevent-dimming and `lowPower` do not inherit the fullPower setter interception behavior.

`lowPower` remains CPU level `2`, matching the existing Swift design.

Default Swift/Orion packaging remains protected:

- default `control` keeps `dev.theos.orion`
- default PreferenceBundle plists keep `InsulationPrefs.RootListController`
- default source expansion keeps Swift files and `Sources/insulationC/Tweak.m`
- ObjC packaging shadows stay outside packaged PreferenceLoader paths until `scripts/build-objc-package.sh` temporarily swaps them

### Validation Performed

These checks pass on the current host:

```sh
scripts/check-objc-port.sh
bash -n scripts/check-objc-port.sh scripts/build-objc-package.sh scripts/setup-linux-theos-env.sh
scripts/build-objc-package.sh rootless
```

`scripts/build-objc-package.sh` checks required host tools (`make`, `clang`, `dpkg-deb`, `fakeroot`, `ldid`, `rsync`, `plistutil`) before mutating packaging files.

A failure-injection test was also performed with a fake `THEOS`, fake required host tools, and fake `make` returning exit code `42`. `scripts/build-objc-package.sh` restored all temporarily swapped files after failure:

- `control`
- `InsulationPrefs/Resources/Info.plist`
- `InsulationPrefs/layout/Library/PreferenceLoader/Preferences/InsulationPrefs.plist`

### Static Gate Coverage

`scripts/check-objc-port.sh` now guards:

- default Swift/Orion path is not polluted by ObjC shadows
- ObjC source expansion has no Swift files
- ObjC mode excludes `Sources/insulationC/Tweak.m` / `orion_init()`
- local Linux/Theos Preferences private headers exist
- all required hook selectors are present
- ObjC runtime risk patterns stay out of the port (`__weak`, `objc_msgSend`, `performSelector`, `NSClassFromString`, `dlsym`, `unsafe_unretained`)
- only the known `_specifiers` KVC access remains in the ObjC PreferenceBundle, matching the Swift implementation
- exported ObjC helper declarations have implementations
- private ObjC helper functions remain `static`
- DictHelper, PowerHelper, fullPower hotfix, tweak init, prefs UI/notification, Makefile source discovery, parsed Makefile source expansion, control shadow, and prefs packaging shadow semantics

### Remaining Notes

- Rootless ObjC packaging is locally validated.
- `arm64e` link steps emit toolchain compatibility warnings from the Linux iOS clang, but the merged/sign/stage/package flow completes and produces the `.deb`.
- `THEOS_PACKAGE_SCHEME=roothide` has not been validated in this pass.
- Do not treat GitHub Actions failures as Swift/ObjC source failures unless runner quota/toolchain problems have been ruled out.
