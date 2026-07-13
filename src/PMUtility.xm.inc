// Forward function type declarations
typedef void (*PMRangeSetterDyn)(id, SEL, CAFrameRateRange);
typedef void (*PMUIntSetterDyn)(id, SEL, unsigned int);
typedef void (*PMReasonsSetterDyn)(id, SEL, const unsigned int *, NSUInteger);

static NSString *PMBundleID(void) {
    static NSString *bundleID = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        bundleID = [[[NSBundle mainBundle] bundleIdentifier] copy] ?: @"";
    });
    return bundleID;
}


static BOOL PMIsTargetProcess(void) {
    static int cached = -1;
    if (cached < 0) cached = [PMBundleID() isEqualToString:@"com.apple.springboard"] ? 1 : 0;
    return cached == 1;
}


static BOOL PMIsAppProcessEligible(void) {
    // Returns YES for any UIKit app (Filza, WeChat, etc.)
    // This is the primary high-refresh path for app processes.
    // Note: SpringBoard process returns NO here (see PMIsTargetProcess).
    return !PMIsTargetProcess();
}


static NSString *PMClassName(id obj) {
    if (!obj) return @"";
    return NSStringFromClass([obj class]) ?: @"";
}


static BOOL PMDeviceSupports120Hz(void) {
    static BOOL checked = NO;
    static BOOL supported = NO;
    if (!checked) {
        @autoreleasepool {
            Class CADisplayClass = NSClassFromString(@"CADisplay");
            if (CADisplayClass && [CADisplayClass respondsToSelector:@selector(mainDisplay)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                CADisplay *display = [CADisplayClass performSelector:@selector(mainDisplay)];
#pragma clang diagnostic pop
                NSArray *modes = display ? [display valueForKey:@"availableModes"] : nil;
                for (id mode in modes) {
                    double rate = [[mode valueForKey:@"refreshRate"] doubleValue];
                    if (rate >= 119.0) {
                        supported = YES;
                        break;
                    }
                }
            }
        }
        checked = YES;
    }
    return supported;
}


static CAFrameRateRange PMForce120Range(void) {
    CAFrameRateRange range;
    // Strict lock: do not leave 80Hz as a legal lower bound.
    range.minimum = TARGET_FPS;
    range.preferred = TARGET_FPS;
    range.maximum = TARGET_FPS;
    return range;
}


static void PMSetHighFrameRateReasonDirect(id obj) {
    if (!obj) return;
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


static void PMSetFrameRateRangeDirect(id obj) {
    if (!obj) return;
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


static void PMApplyToCAObjectDirect(id obj) {
    PMSetHighFrameRateReasonDirect(obj);
    PMSetFrameRateRangeDirect(obj);
}


static id PMMainCADisplay(void) {
    Class CADisplayClass = NSClassFromString(@"CADisplay");
    if (!CADisplayClass || ![CADisplayClass respondsToSelector:@selector(mainDisplay)]) return nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    id display = [CADisplayClass performSelector:@selector(mainDisplay)];
#pragma clang diagnostic pop
    return display;
}


