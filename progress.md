# ProMotion120 refactor progress

## Baseline

- Branch: `main`
- Commit: `5975beec2e82d174832720647aed52399600c98b`
- Validated behavior baseline: 1.0.22

## Current pass: deepen include-only modules

### Hypothesis

Moving state and declarations to their owning include-only modules can remove false dependencies without changing runtime behavior.

### Scope

1. Move cross-module forward declarations out of `PMBanner.xm.inc` into one internal declaration include.
2. Move Banner, Global SpringBoard, and Float state into their owning modules.
3. Remove Float state/configuration from `PMDiagnostic.xm.inc` so diagnostics can later be deleted independently.
4. Rename banner-only generic helpers to `PMBanner*` names.
5. Remove stale comments and diff-check whitespace findings.

### Success criteria

- Makefile, package metadata, injection filter, hook implementations, hook order, keepalive constants, and version remain unchanged.
- All existing C/Objective-C function bodies remain unchanged except identifier renames required by ownership cleanup.
- Logos directive sequence remains unchanged.
- Fresh arm64 + arm64e compile succeeds.
- `git diff --check` passes.

### Independent failure signals

- Any `%hook`, replacement hook, or `%ctor` addition/removal/reordering.
- Any keepalive timing, frame-rate range, dirty-layer, notification, or lifecycle constant changes.
- New compiler/linker errors or warnings attributable to this refactor.
- Diagnostic-disabled build no longer compiles.

### Evidence plan

- Review the exact diff from `5975bee`.
- Compare normalized source tokens after mapping renamed banner identifiers.
- Compare Logos directive sequence before/after.
- Run a clean local package build as compile smoke validation.

## Verification result

- `git diff --check`: pass.
- Package metadata and injection filter unchanged: `control`, `ProMotion120.plist`.
- `Makefile` intentionally changed from `Tweak.xm` to `Tweak.xmi` for CPP-before-Logos module expansion.
- Logos directive sequence unchanged: 100 entries, same order.
- Normalized function set unchanged: 105 functions; no function-body changes after mapping the two banner renames.
- Normalized token delta is only the removal of one redundant `PMFPSRecordRange` forward declaration.
- Clean local arm64 + arm64e package build: pass (`BUILD_STATUS=0`).
- Local arm64e link still emits the known incompatible-ABI warning; local package remains compile-smoke only and must not be delivered.
- Independent review found no P0/P1 regression; the new load-bearing declaration include must be included in any future commit/push.

## Hook-layer split

### Design decision

- Plain `#include` inside `.xm` does not preprocess included `%hook` directives; a minimal probe failed as expected.
- Theos `.xmi` runs the C preprocessor before Logos. A minimal `.xmi` probe proved that `%hook` files included with `#include` are expanded and processed correctly.
- `rootless.h` was unused and incompatible with the `.xmi` preprocessing stage because of its `libroot` module import, so the unused import was removed.

### Modules

- `PMSystemHooks.xm.inc`: SpringBoard policy/controller and `UIScreen` hooks.
- `PMRenderingHooks.xm.inc`: `CADisplayLink`, CoreAnimation, CAMetalLayer/drawable, and Metal command-buffer hooks.
- `PMUIKitHooks.xm.inc`: view/controller/window/scroll/menu/overlay hooks.
- `PMRuntimeHooks.xm.inc`: dynamic Objective-C runtime hooks, replacements, and installers.
- `PMBootstrap.xm.inc`: the single `%ctor` composition root.
- `Tweak.xmi`: imports, constants, interfaces, and ordered module includes only.

### Hook-split verification

- Throwaway split probe compiled for arm64 + arm64e before applying to the worktree.
- Formal clean local build passed (`BUILD_STATUS=0`).
- Generated Logos intermediates contain no unprocessed `%hook`, `%orig`, `%end`, or `%ctor` directives.
- Split and unsplit local dylibs have identical size (`236480` bytes), architecture slices, linked libraries, defined/undefined symbol sets, Objective-C selector/class strings, and package metadata/plist.
- arm64 and arm64e machine-code disassembly are byte-for-byte identical. Binary hash differences are limited to generated UUID/code-signature data.
- Independent hook-split review found no P0 and no hook/constructor/include-order regression. Ship gate: all new `.xmi`/`.xm.inc` files must be included in the eventual commit.
- GitHub Actions path filters now include `**/*.xmi` and `**/*.inc`, so later module-only edits trigger both roothide and rootless workflows.

## Foreground app probe 1

### Baseline

- Production behavior baseline: `8d7ce89` (`1.0.9+clean2`).
- Diagnostic starting point: `6312bd4` (`diag/telegram-chat-probe`).
- Working branch: `diagnostic/foreground-app-probe1`.

### Hypothesis

Hard-coded Telegram bundle IDs are unnecessary. Because ProMotion120 already injects into UIKit app processes, a compile-time-isolated probe can observe only the currently active app, keep hot-path evidence in bounded atomic counters, and write a bundle-identified snapshot when that app resigns active or receives an explicit marker. This should cover arbitrary Telegram forks without adding per-frame queueing or disk I/O.

### Success criteria

- Remove Telegram/Nicegram bundle matching and all rejected-app plist writes.
- Do not dispatch, allocate collections/strings, or write files from DisplayLink/range/scroll/Metal hot hooks.
- Record only while the app process is active; reset counters at each foreground session.
- Write a unique bundle-identified plist only on app resign or `com.doimty.promotion120.probe.mark.drop`.
- Snapshot includes bundle/version/pid, capture span, source liveness, requested range counters, scroll counters, Metal-present cadence buckets, last-event monotonic times, and the trigger.
- `PM_FOREGROUND_PROBE_ENABLED=0` excludes the implementation and all probe strings from a clean binary.
- Existing ProMotion hook order, active 120Hz behavior, keepalive/Float/Banner state machines, ranges, and timing constants remain unchanged.
- Probe-enabled and probe-disabled local builds compile; cloud roothide artifact has correct arm64e ABI and no incompatible-ABI warning.

### Independent failure signals

- Any production hook, forced range, high-frame-rate reason, keepalive tick/evaluate behavior, lifecycle hold, or process filter changes.
- Any unbounded queue or collection fed by a per-frame hook.
- Any file write before an explicit marker or foreground-session end.
- Probe filenames collide across bundle IDs or system/non-target processes overwrite the target app snapshot.
- A clean build contains `foreground-probe`, marker notification, or probe-version strings.

### Ablation expectations

- Probe enabled versus disabled must differ only by observation calls and probe lifecycle registration; forced output ranges and runtime hook composition stay identical.
- Removing bundle-name matching must not affect ProMotion eligibility because the matcher was diagnostic-only.
- With no marker and no resign event, no probe plist is created.
- On resign, exactly the resigning app writes its own bundle-specific snapshot; on marker, only active app processes write snapshots.

### Evidence plan

- Static hot-path scan and source contract checker.
- Diff production function bodies and Logos directive order against `8d7ce89` after accounting for probe calls.
- Compile with `PM_FOREGROUND_PROBE_ENABLED=1` and `0`.
- Extract both packages and scan clean/probe strings and substrate filter.
- Use macOS cloud roothide build for any device-delivered arm64e package.

### Verification

- Source contract (scripts/check-foreground-probe.sh): 22 checks pass.
- Package verification (scripts/verify-foreground-probe-package.sh): probe-on produces roothide arm64e with expected strings; probe-off has no probe strings and passes jbroot check.
- Binary equivalence: probe-off vs baseline `8d7ce89` — arm64e symbols, disassembly, __cstring, __objc_methname, __objc_classname, __objc_methtype all identical.
- Correctness review (sub-agent): P1 writer boundary, coherent range snapshot, marker generation binding, CAS timestamp race — all fixed.
- Build/isolation review (sub-agent): P1 probe-off CI, ABI gate, roothide assertion — all fixed.
- Concurrent pended-marker handling: marker accepted in backgrounded callback merged into foregroundEnd snapshot with `marker.drop+foregroundEnd` reason.
- Run `29925794568` did not reach checkout or compilation. Its sole annotation reports failed account payment or an insufficient Actions spending limit.
- Workflow regression gate now proves build pipeline failures propagate through `tee`, preserves the probe-on deb before the probe-off isolation build, and uploads only the preserved diagnostic package.
- Fallback macOS run `29927454537` built commit `50dbe0a371ad0b35cac619394017d4530531ad8c`: probe-on and probe-off package gates passed, compiler-error and incompatible-arm64e scans were clean, and the uploaded artifact contains only the preserved probe-on deb.
- Verified cloud deb SHA256: `49edcc87463f784717ed8414fbec818c8da05511f13d956f6e77be2c064bfa40`.
