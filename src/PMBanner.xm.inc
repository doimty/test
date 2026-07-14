static BOOL PMBannerLifecycleActive = NO;
static BOOL PMBannerWindowConfirmed = NO;
static CFAbsoluteTime PMBannerArmUntil = 0;
static NSUInteger PMBannerSession = 0;
static __weak id PMCurrentBannerPresentable = nil;
static uintptr_t PMCurrentBannerPresentablePtr = 0;
static __weak UIWindow *PMCurrentBannerWindow = nil;
static __weak id PMCurrentBannerScene = nil;
static CFAbsoluteTime PMBannerLastSourceApplyAt = 0;

static BOOL PMBannerIsArmed(void) {
    return CFAbsoluteTimeGetCurrent() < PMBannerArmUntil;
}

static BOOL PMBannerIsEligibleNow(void) {
    return PMIsTargetProcess() && PMBannerWindowConfirmed && PMBannerIsArmed();
}

static void PMSetHighFrameRateReasonIfPossible(id obj, BOOL isDisplayLink, BOOL isDynamicSource) {
    if (!obj || !PMBannerIsEligibleNow()) return;
    @try {
        static SEL singleSel = nil;
        static SEL multiSel = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            singleSel = NSSelectorFromString(@"setHighFrameRateReason:");
            multiSel = NSSelectorFromString(@"setHighFrameRateReasons:count:");
        });
        if ([obj respondsToSelector:singleSel]) {
            PMUIntSetterDyn fn = (PMUIntSetterDyn)objc_msgSend;
            fn(obj, singleSel, 1U);
        }
        if ([obj respondsToSelector:multiSel]) {
            unsigned int reasons[1] = { 1U };
            PMReasonsSetterDyn fn = (PMReasonsSetterDyn)objc_msgSend;
            fn(obj, multiSel, reasons, (NSUInteger)1);
        }
    } @catch (__unused NSException *e) {
    }
}

static void PMSetFrameRateRangeIfPossible(id obj, BOOL isDisplayLink, BOOL isDynamicSource) {
    if (!obj || !PMBannerIsEligibleNow()) return;
    @try {
        static SEL sel = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            sel = NSSelectorFromString(@"setPreferredFrameRateRange:");
        });
        if ([obj respondsToSelector:sel]) {
            PMRangeSetterDyn fn = (PMRangeSetterDyn)objc_msgSend;
            fn(obj, sel, PMForce120Range());
        }
    } @catch (__unused NSException *e) {
    }
}

static void PMApplyToCAObject(id obj, BOOL isDisplayLink, BOOL isDynamicSource) {
    PMSetHighFrameRateReasonIfPossible(obj, isDisplayLink, isDynamicSource);
    PMSetFrameRateRangeIfPossible(obj, isDisplayLink, isDynamicSource);
}

// Banner no longer owns a separate DynamicSource. SB has one owner:
// PMGlobalSBDisplaySource. Banner lifecycle only re-applies that owner.
static void PMApplyDisplayFrameRateSource(NSString *source) {
    if (!PMBannerIsEligibleNow()) return;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (PMBannerLastSourceApplyAt > 0 && (now - PMBannerLastSourceApplyAt) < 0.10) return;
    @try {
        // Re-apply the single SB owner. Do not allocate a 2nd source.
        PMGlobalSBApply(source ?: @"banner.reapply");
        PMBannerLastSourceApplyAt = now;
    } @catch (__unused NSException *e) {
    }
}

static void PMReleaseDisplayFrameRateSource(NSString *source) {
    // Single-owner model: never tear down Global on banner exit.
    // Banner session end only clears banner state; Global stays for SB.
    (void)source;
}

static BOOL PMLayerBelongsToBannerWindow(CALayer *layer) {
    if (!layer || !PMCurrentBannerWindow) return NO;
    CALayer *root = PMCurrentBannerWindow.layer;
    for (CALayer *cursor = layer; cursor; cursor = cursor.superlayer) {
        if (cursor == root) return YES;
    }
    return NO;
}

static BOOL PMConfirmWindowIfBanner(UIWindow *window, NSString *source) {
    NSString *cls = PMClassName(window);
    if (!window) return NO;
    if ([cls isEqualToString:@"SBBannerWindow"]) {
        PMCurrentBannerWindow = window;
        PMBannerWindowConfirmed = YES;
        PMBannerArmUntil = CFAbsoluteTimeGetCurrent() + 3.0;
        if ([window respondsToSelector:@selector(windowScene)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            PMCurrentBannerScene = [window performSelector:@selector(windowScene)];
#pragma clang diagnostic pop
        }
        PMApplyDisplayFrameRateSource(source ?: @"confirmWindow.displaySource");
        return YES;
    }
    return NO;
}

static BOOL PMCaptureWindowFromView(id view, NSString *source) {
    if (!PMIsTargetProcess() || !view || ![view respondsToSelector:@selector(window)]) return NO;
    @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        UIWindow *window = [view performSelector:@selector(window)];
#pragma clang diagnostic pop
        return PMConfirmWindowIfBanner(window, source);
    } @catch (__unused NSException *e) {
        return NO;
    }
}

static BOOL PMCaptureFromPresentable(id presentable, NSString *source) {
    if (!PMIsTargetProcess() || !presentable || ![presentable respondsToSelector:@selector(view)]) return NO;
    @try {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        id view = [presentable performSelector:@selector(view)];
#pragma clang diagnostic pop
        return PMCaptureWindowFromView(view, source);
    } @catch (__unused NSException *e) {
        return NO;
    }
}

static BOOL PMScanApplicationWindows(NSString *source) {
    if (!PMIsTargetProcess()) return NO;
    @try {
        Class UIApplicationClass = NSClassFromString(@"UIApplication");
        if (!UIApplicationClass || ![UIApplicationClass respondsToSelector:@selector(sharedApplication)]) return NO;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        UIApplication *app = [UIApplicationClass performSelector:@selector(sharedApplication)];
#pragma clang diagnostic pop
        if (!app || ![app respondsToSelector:@selector(windows)]) return NO;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        NSArray *windows = [app performSelector:@selector(windows)];
#pragma clang diagnostic pop
        for (UIWindow *window in windows) {
            if ([PMClassName(window) isEqualToString:@"SBBannerWindow"]) {
                return PMConfirmWindowIfBanner(window, source ?: @"scanApplicationWindows");
            }
        }
    } @catch (__unused NSException *e) {
    }
    return NO;
}

static void PMScheduleCapture(id presentable, NSString *source) {
    if (!PMIsTargetProcess()) return;
    id capturedPresentable = presentable;
    NSString *capturedSource = [source copy] ?: @"capture";
    if (!PMCaptureFromPresentable(capturedPresentable, [capturedSource stringByAppendingString:@".presentable"])) {
        PMScanApplicationWindows([capturedSource stringByAppendingString:@".windows"]);
    }
    NSArray *delays = @[@0.03, @0.08, @0.16];
    for (NSNumber *delayNumber in delays) {
        double delay = delayNumber.doubleValue;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (!PMBannerLifecycleActive && !PMBannerIsArmed()) return;
            NSString *suffix = [NSString stringWithFormat:@".delayed%.2f", delay];
            if (!PMCaptureFromPresentable(capturedPresentable, [capturedSource stringByAppendingString:[suffix stringByAppendingString:@".presentable"]])) {
                PMScanApplicationWindows([capturedSource stringByAppendingString:[suffix stringByAppendingString:@".windows"]]);
            }
        });
    }
}

static void PMScheduleDisplaySourceReapply(NSString *source, NSArray<NSNumber *> *delays) {
    NSUInteger scheduledSession = PMBannerSession;
    for (NSNumber *delayNumber in delays) {
        double delay = delayNumber.doubleValue;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (scheduledSession != PMBannerSession) return;
            if (!PMBannerIsArmed() || !PMBannerWindowConfirmed) return;
            PMApplyDisplayFrameRateSource(source ?: @"displaySource.reapply");
        });
    }
}

static void PMExtendExitTailAndApply(NSString *source) {
    if (!PMBannerWindowConfirmed) return;
    PMBannerArmUntil = MAX(PMBannerArmUntil, CFAbsoluteTimeGetCurrent() + 1.65);
    PMApplyDisplayFrameRateSource(source ?: @"exitTail.apply");
    PMScheduleDisplaySourceReapply(source ?: @"exitTail.reapply", @[@0.05, @0.18, @0.36, @0.72, @1.10]);
}

static uintptr_t PMPresentablePointer(id presentable) {
    return (uintptr_t)(__bridge void *)presentable;
}

static BOOL PMFindBannerWindowForExitPoll(NSString *source) {
    if (!PMIsTargetProcess()) return NO;
    @try {
        Class UIApplicationClass = NSClassFromString(@"UIApplication");
        if (!UIApplicationClass || ![UIApplicationClass respondsToSelector:@selector(sharedApplication)]) return NO;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        UIApplication *app = [UIApplicationClass performSelector:@selector(sharedApplication)];
#pragma clang diagnostic pop
        if (!app || ![app respondsToSelector:@selector(windows)]) return NO;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        NSArray *windows = [app performSelector:@selector(windows)];
#pragma clang diagnostic pop
        for (UIWindow *window in windows) {
            if ([PMClassName(window) isEqualToString:@"SBBannerWindow"]) {
                PMCurrentBannerWindow = window;
                PMBannerWindowConfirmed = YES;
                if ([window respondsToSelector:@selector(windowScene)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                    PMCurrentBannerScene = [window performSelector:@selector(windowScene)];
#pragma clang diagnostic pop
                }
                return YES;
            }
        }
    } @catch (__unused NSException *e) {
    }
    return NO;
}

static void PMFinishExitPollRelease(NSString *source, BOOL timeout) {
    PMBannerWindowConfirmed = NO;
    PMBannerArmUntil = 0;
    PMCurrentBannerPresentablePtr = 0;
    PMCurrentBannerPresentable = nil;
    PMReleaseDisplayFrameRateSource(source ?: @"exitPoll.release");
}

static void PMScheduleExitPollRelease(NSUInteger endingSession, CFAbsoluteTime startedAt, NSUInteger missingCount) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (endingSession != PMBannerSession || PMBannerLifecycleActive) return;

        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        BOOL timedOut = (now - startedAt) >= 4.0;
        BOOL found = PMFindBannerWindowForExitPoll(@"exitPoll.scan");

        // Only keep confirmed while the banner window is still present.
        // Previously this forced Confirmed=YES even after window gone, which
        // polluted PMBannerIsEligibleNow and stretched banner eligibility falsely.
        if (found) {
            PMBannerArmUntil = MAX(PMBannerArmUntil, now + 0.35);
            PMBannerWindowConfirmed = YES;
            PMApplyDisplayFrameRateSource(@"exitPoll.reapplyDisplaySource");
        } else {
            // Keep a short arm tail for exit animation only; do not fake confirmation.
            PMBannerArmUntil = MAX(PMBannerArmUntil, now + 0.20);
        }

        if (timedOut) {
            PMFinishExitPollRelease(@"exitPoll.timeoutReleaseDisplaySource", YES);
            return;
        }

        NSUInteger nextMissingCount = found ? 0 : (missingCount + 1);
        if ((now - startedAt) >= 0.70 && nextMissingCount >= 2) {
            PMFinishExitPollRelease(@"exitPoll.windowGoneReleaseDisplaySource", NO);
            return;
        }

        PMScheduleExitPollRelease(endingSession, startedAt, nextMissingCount);
    });
}

static BOOL PMPresentableMatchesCurrent(id presentable) {
    uintptr_t endingPtr = PMPresentablePointer(presentable);
    uintptr_t currentPtr = PMCurrentBannerPresentablePtr;
    // Unknown identity: ignore end (do not blindly match)
    if (!endingPtr || !currentPtr) return NO;
    return endingPtr == currentPtr;
}

static void PMBeginBannerSession(NSString *event, id presentable) {
    PMBannerLifecycleActive = YES;
    PMBannerSession += 1;
    PMCurrentBannerPresentable = presentable;
    PMCurrentBannerPresentablePtr = PMPresentablePointer(presentable);
    PMBannerArmUntil = CFAbsoluteTimeGetCurrent() + 1.2;
    PMScheduleCapture(presentable, event);
}

static void PMEndBannerSession(NSString *event, NSString *note, id presentable) {
    if (!PMPresentableMatchesCurrent(presentable)) {
        PMExtendExitTailAndApply(@"endBanner.staleEndKeepCurrentAlive");
        return;
    }

    PMBannerLifecycleActive = NO;
    if (PMBannerWindowConfirmed) {
        NSUInteger endingSession = PMBannerSession;
        CFAbsoluteTime startedAt = CFAbsoluteTimeGetCurrent();
        PMExtendExitTailAndApply(@"endBanner.exitTailApply");
        PMScheduleExitPollRelease(endingSession, startedAt, 0);
    }
}
