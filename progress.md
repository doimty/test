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
