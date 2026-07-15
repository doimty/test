# Insulation 0.1.37 simple uninstall plan

Baseline: `86bbc6e9ae17a0e470ef37db63642255cb8b43f9`

Rejected branch: `692c1317cce9032153e172df432735c7f00236a8`

This document supersedes the Clean4 removal-lifecycle design for the new
`fix/insulation-0.1.37-simple-uninstall` line.

Status: implemented and locally verified. Roothide delivery still requires a
macOS cloud build with a clean arm64e ABI-warning scan.

## Product contract

Insulation owns no uninstall transaction. The package manager removes the
payload normally. After payload deletion, `postrm` best-effort terminates
`thermalmonitord`; launchd then starts a native process without the injected
dylib.

Uninstall must not:

- delete or verify `OSThermalStatus.plist` keys;
- create a persistent marker or nonce acknowledgment;
- prepare, quiesce, or disable the injected daemon before payload deletion;
- expose uninstall-only lifecycle actions through `insulationctl`; or
- fail because process replacement could not be requested.

Installed-product mode handling remains separate. Existing off/low cleanup,
mode notification, apply serialization, and CPU state behavior are not part of
this rollback.

## Hypothesis

Removing the pre-removal native reset and moving process replacement to a
non-blocking `postrm` restores the proven uninstall behavior without regressing
installed-product state convergence.

## Confirmed test seams

1. Debian maintainer scripts invoked with package-manager lifecycle arguments.
2. Extracted package contents and maintainer scripts.
3. Apply scheduling through its host-testable generation model.
4. Source-contract absence search without an `rg` dependency.

## Success criteria

- No `prerm` removal transaction is packaged.
- `postrm remove|purge|disappear` requests `killall thermalmonitord` once and
  exits zero even when `killall` fails.
- `postrm` does nothing for upgrade/abort paths.
- The hidden reset-all, prepare-removal, and marker-clear CLI actions are absent.
- No marker/nonce/removal-disabled subsystem is present on this line.
- Direct apply does not invalidate an active Soon generation; starting another
  Soon batch does.
- Missing `rg` cannot turn a forbidden-string test into a false pass.
- The `PackagePowerCC.initWithParams:` hook checks its original IMP before
  patching arguments.

## Independent failure signals

- Package removal invokes `--reset-native-state` or any native cleanup helper.
- Any maintainer script can block removal on native state or process replacement.
- The package contains a `prerm` or uninstall-only CLI action.
- Direct apply advances the Soon generation.
- A forbidden-string scan reports success after its search command fails.

## Ablation expectations

- Fake `killall` success and failure both leave `postrm remove` at exit 0.
- `postrm upgrade` produces no process-control event.
- Removing the direct-apply scheduling fix makes the caller-composition test red.
- Injecting a retired notification string makes the absence contract red even
  when `rg` is unavailable.

## Evidence plan

1. Write and run red maintainer-script/package-source contracts.
2. Implement the smallest uninstall change and make those contracts green.
3. Add the minimal direct/Soon generation fix and its host test.
4. Carry the search-contract and null-IMP fixes independently.
5. Run shell syntax, source checks, all host tests, `git diff --check`, and a
   clean rootless package smoke/inspection.
6. Treat any local arm64e output as compile evidence only; use macOS cloud logs
   before a future Roothide delivery.
