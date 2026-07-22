// Shared declarations for the include-only modules in this compilation unit.
// Keep implementations and state in their owning modules.

#if PM_FOREGROUND_PROBE_ENABLED
// Generic foreground-app diagnostic probe. Implemented after App persistent
// source ownership so snapshots can report the live source pointer.
typedef NS_ENUM(uint32_t, PMFGProbeRangeSource) {
    PMFGProbeRangeSourceNone = 0,
    PMFGProbeRangeSourceDisplayLink = 1,
    PMFGProbeRangeSourceCAAnimation = 2,
};
typedef NS_ENUM(uint32_t, PMFGProbeScrollSource) {
    PMFGProbeScrollSourceSetContentOffset = 1,
    PMFGProbeScrollSourceSetContentOffsetAnimated = 2,
    PMFGProbeScrollSourceLayoutMoving = 3,
};
typedef NS_ENUM(uint32_t, PMFGProbeMetalSource) {
    PMFGProbeMetalSourceDrawable = 1,
    PMFGProbeMetalSourceCommandBuffer = 2,
};
static BOOL PMFGProbeEnabled = NO;
static void PMFGProbeInit(void);
static void PMFGProbeRecordDisplayLinkCreate(void);
static void PMFGProbeRecordRange(PMFGProbeRangeSource source, CAFrameRateRange range);
static void PMFGProbeRecordScroll(PMFGProbeScrollSource source);
static void PMFGProbeRecordMetal(PMFGProbeMetalSource source);
static void PMFGProbeRecordSourceRefresh(void);
#endif

// SpringBoard global source and blocked-app keepalive.
static void PMGlobalSBApply(NSString *reason);
static void PMGlobalSBApplyForced(NSString *reason);
static void PMSBForceMainDisplayHighMode(void);
static void PMSBKeepAliveApplyLinkRange(void);

// App-process persistent source.
static void PMAppEnsurePersistentSource(void);
static void PMAppRefreshPersistentSource(void);

// Floating-window arming (used from keepalive / UIKit hooks).
static BOOL PMFloatFeatureEnabled(void);
static BOOL PMFloatAnyFloatingWindowVisible(void);
static void PMFloatArm(NSString *event);
