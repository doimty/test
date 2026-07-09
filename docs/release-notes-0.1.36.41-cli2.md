# Insulation 0.1.36.41-cli2

## Fixed

- Fixed roothide `ins` / `insulationctl` aborting at launch with:

  ```text
  dyld: Library not loaded: @loader_path/.jbroot/usr/lib/libroothide.dylib
  ```

- The CLI no longer imports or links `libroothide.dylib`. It derives the roothide `.jbroot-*` prefix from its own executable path and uses that only for prefs path resolution.
- Rootless keeps the existing `/var/mobile/Library/Preferences/com.be-huge.insulation-prefs.plist` prefs path and is not redirected to `/var/jb/var/mobile/...`.

## Regression check

- Package verification now fails if `otool -L` shows `libroothide.dylib` in `insulationctl` dependencies.

## Scope

This is a CLI/dynamic-link hotfix only. It does not change thermal strategy, hooks, boot guard, probe timing, or low/max CPU behavior.
