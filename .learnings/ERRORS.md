
## 2026-05-28 apply_patch unavailable
- Context: attempted to use apply_patch in /root/.openclaw/workspace/repos/insulation per editing preference.
- Error: /usr/bin/bash: apply_patch: command not found.
- Lesson: this OpenClaw host may not provide apply_patch; use first-class edit/write tools for precise file changes when apply_patch is unavailable.

## 2026-05-28 local Theos package unavailable
- Context: attempted local `make package THEOS_PACKAGE_SCHEME=rootless FINALPACKAGE=1` in /root/.openclaw/workspace/repos/insulation before CI.
- Error: `Makefile:31: /aggregate.mk: No such file or directory`.
- Lesson: this host does not have a usable THEOS path for local packaging; use GitHub Actions as the build authority for insulation packages.

## 2026-05-29 zip command unavailable
- Context: attempted to package latest-switches-ios15-fix with `zip -qr`.
- Error: `/usr/bin/bash: line 1: zip: command not found`.
- Lesson: use Python's `zipfile` module for creating archives on this host when `/usr/bin/zip` is unavailable.

## 2026-05-30 git commit identity missing
- Context: attempting to commit insulation changes for GitHub Actions build.
- Error: Author identity unknown; git could not auto-detect email address.
- Lesson: set repository-local git user.name/user.email before committing on this host; avoid global config changes unless requested.

## 2026-05-30 gh CLI unavailable
- Context: checking GitHub Actions run after pushing insulation branch.
- Error: /usr/bin/bash: gh: command not found.
- Lesson: when gh is unavailable on this host, use GitHub REST API via curl/Python as a fallback for public repositories.

## 2026-05-31 rg unavailable in insulation repo
- Context: searching Swift hooks while tuning low-power simulation.
- Error: /usr/bin/bash: rg: command not found.
- Lesson: this host may lack ripgrep despite normal preference; fall back to grep/find for local code search.
