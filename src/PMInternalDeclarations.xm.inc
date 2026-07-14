// Shared declarations for the include-only modules in this compilation unit.
// Keep implementations and state in their owning modules.

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
