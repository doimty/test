// App-process persistent 120Hz source: created once per app launch.
// Unlike the old scroll-only source that was created/destroyed on each scroll,
// this keeps a persistent CADynamicFrameRateSource alive for the entire process
// lifetime. This prevents 120Hz drops during VC transitions, tab switches,
// animations, and other non-scroll scenarios.
static id PMAppPersistentFrameRateSource = nil;
// Managed sources are never cleared via the system empty-reasons path.
// Self-teardown of Global/App persistent sources is not used in release.
// SB keeps one display-level source owner: Global. Banner/Float only re-apply
// that owner; they no longer allocate their own DynamicSource slots.
// App process keeps its own persistent source (different process).
static inline BOOL PMIsManagedSource(id source) {
    return source == PMGlobalSBDisplaySource
        || source == PMAppPersistentFrameRateSource;
}

static void PMAppEnsurePersistentSource(void) {
    // Gate on live source pointer, not a sticky applied flag that can brick rebuild.
    if (PMIsTargetProcess() || PMAppPersistentFrameRateSource) return;
    @try {
        Class SourceClass = NSClassFromString(@"CADynamicFrameRateSource");
        id display = PMMainCADisplay();
        if (SourceClass && display) {
            id allocated = [SourceClass alloc];
            SEL initSel = NSSelectorFromString(@"initWithDisplay:");
            if ([allocated respondsToSelector:initSel]) {
                typedef id (*PMInitWithDisplayFn)(id, SEL, id);
                PMInitWithDisplayFn fn = (PMInitWithDisplayFn)objc_msgSend;
                PMAppPersistentFrameRateSource = fn(allocated, initSel, display);
                if (PMAppPersistentFrameRateSource) {
                    PMSetHighFrameRateReasonDirect(PMAppPersistentFrameRateSource);
                    PMSetFrameRateRangeDirect(PMAppPersistentFrameRateSource);
                }
            }
        }
    } @catch (__unused NSException *e) {
    }
}

// Re-apply 120Hz to the persistent source (e.g. after system may have reset it)
// Throttled to avoid per-frame overhead during scrolling.
static CFAbsoluteTime PMAppLastRefreshAt = 0;
static const CFTimeInterval PMAppRefreshMinInterval = 0.20;

static void PMAppRefreshPersistentSource(void) {
    if (PMIsTargetProcess() || !PMAppPersistentFrameRateSource) return;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (PMAppLastRefreshAt > 0 && (now - PMAppLastRefreshAt) < PMAppRefreshMinInterval) return;
    PMAppLastRefreshAt = now;
    if (PMTGProbeEnabled) PMTGProbeSourceRefresh(@"refresh");
    @try {
        PMSetHighFrameRateReasonDirect(PMAppPersistentFrameRateSource);
        PMSetFrameRateRangeDirect(PMAppPersistentFrameRateSource);
    } @catch (__unused NSException *e) {
    }
}

// Scroll arm: still used to re-affirm 120Hz during active scrolling,
// but no longer creates/destroys its own source.
static BOOL PMAppScrollViewIsMoving(UIScrollView *scrollView) {
    if (!scrollView) return NO;
    @try {
        return scrollView.dragging || scrollView.tracking || scrollView.decelerating;
    } @catch (__unused NSException *e) {
        return NO;
    }
}

static void PMAppScrollArm(__unused NSString *event) {
    if (PMIsTargetProcess()) return;
    PMAppRefreshPersistentSource();
}
