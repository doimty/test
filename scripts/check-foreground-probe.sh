#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROBE="$ROOT/src/PMForegroundProbe.xm.inc"

python3 - "$ROOT" "$PROBE" <<'PY'
from pathlib import Path
import os
import re
import sys

root = Path(sys.argv[1])
probe_path = Path(sys.argv[2])
workflow_path = Path(os.environ.get("PM_WORKFLOW_UNDER_TEST", root / ".github/workflows/roothide-build.yml"))
probe = probe_path.read_text()
workflow = workflow_path.read_text()
all_source = "\n".join(
    path.read_text(errors="replace")
    for path in [root / "Tweak.xmi", *sorted((root / "src").glob("*.inc"))]
)
background = probe[probe.find("UIApplicationDidEnterBackgroundNotification"):]
marker_callback = probe[probe.find("static void PMFGProbeMarkerCallback"):probe.find("static void PMFGProbeRecordDisplayLinkCreate")]

required = {
    "compile-time probe guard": "#if PM_FOREGROUND_PROBE_ENABLED" in (root / "Tweak.xmi").read_text(),
    "generic probe include": 'src/PMForegroundProbe.xm.inc' in (root / "Tweak.xmi").read_text(),
    "explicit marker": "com.doimty.promotion120.probe.mark.drop" in probe,
    "foreground lifecycle start": "UIApplicationDidBecomeActiveNotification" in probe,
    "foreground start receipt": 'PMFGProbeWriteSnapshot(@"foregroundStart"' in probe,
    "foreground end": "UIApplicationDidEnterBackgroundNotification" in probe,
    "active marker gate": "PMFGProbeShouldRecord()" in probe,
    "unique bundle output": "foreground-probe.%@.%@.p%d.t%llu.s%llu.plist" in probe,
    "per-bundle visible latest output": "/var/mobile/Library/Preferences/com.promotion120.foreground-probe.%@.latest.plist" in probe,
    "collision-resistant latest bundle name": "PMFGProbeStableStringHash" in probe and "PMFGProbeLatestBundlePathPart" in probe,
    "write result telemetry": '@"writeResults"' in probe and 'errorDomain' in probe and 'errorCode' in probe,
    "real app short version": 'CFBundleShortVersionString' in probe,
    "real app build version": 'CFBundleVersion' in probe,
    "fixed atomic counters": "__atomic_add_fetch" in probe and "__atomic_load_n" in probe,
    "coalesced marker dispatch": "PMFGProbeMarkerMutex" in probe and "PMFGProbeMarkerState" in probe,
    "bounded marker disk queue": "PMFGProbeMarkerQueued" in probe and "PMFGProbeFinishMarker" in probe,
    "marker state and token share mutex": "PMFGProbeMarkerAcceptedToken == acceptedToken" in probe,
    "marker callback participates in session drain": "PMFGProbeTryBeginRecord()" in marker_callback and "PMFGProbeEndRecord();" in marker_callback,
    "background closes marker admission first": background.find("PMFGProbeCloseAndDrainSession();") < background.find("pthread_mutex_lock(&PMFGProbeMarkerMutex)"),
    "lifecycle snapshots are never dropped": "PMFGProbeSnapshotPending" not in probe,
    "background write extension": "beginBackgroundTaskWithName" in probe and "endBackgroundTask" in probe,
    "snapshot queue never blocks lifecycle callback": "dispatch_sync(PMFGProbeSnapshotQueue" not in probe,
    "drained session boundary": "PMFGProbeCloseAndDrainSession" in probe and "PMFGProbeWriters" in probe,
    "coherent range snapshot": "PMFGProbeLastRangeSequence" in probe and '@"coherent"' in probe,
    "single atomic plist write": probe.count("writeToFile:") == 1,
    "clean build macro": "PM_FOREGROUND_PROBE_ENABLED ?= 1" in (root / "Makefile").read_text(),
    "workflow propagates build failures": "set -o pipefail" in workflow,
    "probe-on artifact preserved before probe-off": workflow.find('cp "$deb" artifacts/') > 0 and workflow.find('cp "$deb" artifacts/') < workflow.find("# Probe-off build"),
    "probe-off package cannot replace deliverable": "path: artifacts/*.deb" in workflow and "path: packages/*" not in workflow,
    "probe-off binary baseline gate": "8d7ce89" in workflow and "pm120-probe-off-current-disasm" in workflow,
    "Mach-O arm64e assertion": "ARM64[[:space:]]+E" in (root / "scripts/verify-foreground-probe-package.sh").read_text(),
}

for label, ok in required.items():
    if not ok:
        raise SystemExit(f"FAIL: {label}")
    print(f"OK: {label}")

for forbidden in ("PMTelegramProbe", "PMTGProbe", "tgprobe", "rejectedBundleID", "tgprobe.rejected"):
    if forbidden.lower() in all_source.lower():
        raise SystemExit(f"FAIL: retired Telegram matcher residue: {forbidden}")
print("OK: retired Telegram matcher and rejected-app writes absent")

hot_names = [
    "PMFGProbeAdvanceTimestamp",
    "PMFGProbeRecordDisplayLinkCreate",
    "PMFGProbeRecordRange",
    "PMFGProbeRecordScroll",
    "PMFGProbeRecordCadence",
    "PMFGProbeRecordMetal",
    "PMFGProbeRecordSourceRefresh",
]
for index, name in enumerate(hot_names):
    name_position = probe.find(f"{name}(")
    if name_position < 0:
        raise SystemExit(f"FAIL: missing hot recorder {name}")
    start = probe.rfind("\nstatic ", 0, name_position) + 1
    following = [probe.find("\nstatic ", name_position + 1)]
    end = min(position for position in following if position >= 0) if any(position >= 0 for position in following) else len(probe)
    body = probe[start:end]
    for forbidden in ("dispatch_async", "dispatch_sync", "writeToFile", "NSMutable", "stringWithFormat", "PMClassName", "writeToURL"):
        if forbidden in body:
            raise SystemExit(f"FAIL: {name} hot path contains {forbidden}")
    print(f"OK: {name} hot path is allocation/queue/disk free")

hook_files = [
    root / "src/PMRenderingHooks.xm.inc",
    root / "src/PMUIKitHooks.xm.inc",
    root / "src/PMAppPersistent.xm.inc",
    root / "src/PMBootstrap.xm.inc",
]
for path in hook_files:
    text = path.read_text()
    if "PMFGProbe" in text and "#if PM_FOREGROUND_PROBE_ENABLED" not in text:
        raise SystemExit(f"FAIL: unguarded foreground probe calls in {path.name}")
    print(f"OK: {path.name} probe calls are compile-time guarded")

print("Foreground probe source contract passed")
PY
