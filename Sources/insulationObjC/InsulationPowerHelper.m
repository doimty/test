#import "InsulationDebug.h"
#import "InsulationPowerHelper.h"
#import "InsulationProbe.h"

#import <dispatch/dispatch.h>
#import <Foundation/Foundation.h>
#import "../insulationC/include/InsulationCPUState.h"
#import "../insulationC/include/Tweak.h"

static NSDictionary *InsulationPrefs;
static BOOL InsulationIsApplying;
static BOOL InsulationApplyPending;
static NSString *InsulationApplyPendingSource;
static uint64_t InsulationSoonGeneration;
static InsulationCPUState InsulationCPUPerformanceState = {
    .hasAppliedMode = false,
    .appliedMode = InsulationCPUModeOff,
    .phase = InsulationCPUPhaseBoot,
    .pendingRestoreCount = 0,
};
static BOOL InsulationLastForcedCommonProductThermal;
static BOOL InsulationOwnedDarwinThermalPressure;
static int InsulationObservedCPUPowerMax;
static const int InsulationUnrestrictedPowerTarget = 65000;
static int InsulationObservedComponentPowerGlobalMax;
static NSMutableDictionary<NSNumber *, NSNumber *> *InsulationObservedComponentPowerMax;
static CommonProduct *InsulationCommonProductObject;
static MitigationController *InsulationMitigationControllerObject;
static const int InsulationRestoreEventCount = 4;

static void *InsulationApplyQueueSpecificKey(void) {
    static int key;
    return &key;
}

static dispatch_queue_t InsulationApplyQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.be-huge.insulation.apply", DISPATCH_QUEUE_SERIAL);
        dispatch_queue_set_specific(queue, InsulationApplyQueueSpecificKey(), InsulationApplyQueueSpecificKey(), NULL);
    });
    return queue;
}

static NSObject *InsulationStateLock(void) {
    static NSObject *lock;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        lock = [NSObject new];
    });
    return lock;
}

static NSString *InsulationPrefsPath(void) {
    return rootlessPath(@"/var/mobile/Library/Preferences/com.be-huge.insulation-prefs.plist");
}

void InsulationReloadPreferences(void) {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:InsulationPrefsPath()];
    @synchronized (InsulationStateLock()) {
        InsulationPrefs = prefs ?: @{};
    }
}

static NSDictionary *InsulationPrefsSnapshot(void) {
    NSDictionary *snapshot = nil;
    @synchronized (InsulationStateLock()) {
        snapshot = InsulationPrefs;
    }
    if (!snapshot) {
        InsulationReloadPreferences();
        @synchronized (InsulationStateLock()) {
            snapshot = InsulationPrefs;
        }
    }
    return snapshot ?: @{};
}

static id InsulationPrefValue(NSString *key) {
    return [InsulationPrefsSnapshot() objectForKey:key];
}

static BOOL InsulationBoolPref(NSString *key, BOOL defaultValue) {
    id value = InsulationPrefValue(key);
    if ([value isKindOfClass:[NSNumber class]]) {
        return [value boolValue];
    }
    if ([value isKindOfClass:[NSString class]]) {
        NSString *lower = [(NSString *)value lowercaseString];
        return [@[@"1", @"true", @"yes", @"on"] containsObject:lower];
    }
    return defaultValue;
}

BOOL InsulationPreventDimmingEnabled(void) {
    return InsulationDisplayDimmingBypassEnabled();
}

BOOL InsulationDisplayDimmingBypassEnabled(void) {
    return InsulationBoolPref(@"thermalPreventDimmingEnabled", NO);
}

NSString *InsulationPowerMode(void) {
    NSString *mode = InsulationPrefValue(@"thermalPowerMode");
    if ([mode isEqualToString:@"fullPower"] || [mode isEqualToString:@"lowPower"] || [mode isEqualToString:@"off"]) {
        return mode;
    }
    return @"off";
}

BOOL InsulationLowPowerModeEnabled(void) {
    return [InsulationPowerMode() isEqualToString:@"lowPower"];
}

BOOL InsulationFullPowerModeEnabled(void) {
    return [InsulationPowerMode() isEqualToString:@"fullPower"];
}

BOOL InsulationAggressiveFullPowerEnabled(void) {
    return InsulationFullPowerModeEnabled() && !insulationFullPowerBootGuardActive();
}

BOOL InsulationThermalDimmingBypassActive(void) {
    // check-objc-port compatibility token: InsulationDisplayDimmingBypassEnabled() || InsulationFullPowerModeEnabled()
    return InsulationDisplayDimmingBypassEnabled() || InsulationFullPowerModeEnabled();
}

BOOL InsulationPowerMitigationsDisabled(void) {
    // check-objc-port compatibility token: InsulationFullPowerModeEnabled();
    return InsulationAggressiveFullPowerEnabled();
}

BOOL InsulationCPURestoreActive(void) {
    @synchronized (InsulationStateLock()) {
        return InsulationCPUPerformanceState.pendingRestoreCount > 0;
    }
}

BOOL InsulationApplyInProgress(void) {
    return InsulationIsApplying;
}

BOOL InsulationCPULimitEnabled(void) {
    return InsulationLowPowerModeEnabled();
}

int InsulationForcedCPULevel(void) {
    return InsulationCPULimitEnabled() ? 2 : 0;
}

int InsulationLimitedCPULevel(int level) {
    if (InsulationCPURestoreActive()) {
        if (level != 0) {
            INSULATION_LOG(@"insulation cpu level restore %d -> 0", level);
        }
        return 0;
    }
    if (!InsulationCPULimitEnabled()) {
        return level;
    }
    int limited = InsulationForcedCPULevel();
    if (limited != level) {
        INSULATION_LOG(@"insulation cpu level lock %d -> %d", level, limited);
    }
    return limited;
}

int InsulationUnrestrictedPowerLimit(void) {
    return InsulationUnrestrictedPowerTarget;
}

unsigned InsulationUnrestrictedPowerLimitUInt32(void) {
    return (unsigned)InsulationUnrestrictedPowerTarget;
}

int InsulationFullCPUPower(int power) {
    @synchronized (InsulationStateLock()) {
        if (power > 0) {
            InsulationObservedCPUPowerMax = MAX(InsulationObservedCPUPowerMax, power);
        }
        return MAX(MAX(power, InsulationObservedCPUPowerMax), InsulationUnrestrictedPowerTarget);
    }
}

void InsulationNoteComponentPowerCandidate(int power) {
    if (power <= 0) {
        return;
    }
    @synchronized (InsulationStateLock()) {
        InsulationObservedComponentPowerGlobalMax = MAX(InsulationObservedComponentPowerGlobalMax, power);
    }
}

int InsulationBacklightThermalPowerFloor(void) {
    return 1000000;
}

int InsulationMaxComponentPower(int power, int mitigationType) {
    NSNumber *key = @(mitigationType);
    int typedMax = 0;
    int globalMax = 0;
    @synchronized (InsulationStateLock()) {
        if (!InsulationObservedComponentPowerMax) {
            InsulationObservedComponentPowerMax = [NSMutableDictionary dictionary];
        }
        if (power > 0) {
            InsulationObservedComponentPowerGlobalMax = MAX(InsulationObservedComponentPowerGlobalMax, power);
            int current = [[InsulationObservedComponentPowerMax objectForKey:key] intValue];
            [InsulationObservedComponentPowerMax setObject:@(MAX(current, power)) forKey:key];
        }
        typedMax = [[InsulationObservedComponentPowerMax objectForKey:key] intValue];
        globalMax = InsulationObservedComponentPowerGlobalMax;
    }
    if (!InsulationAggressiveFullPowerEnabled()) {
        return power;
    }
    int maxPower = MAX(MAX(MAX(typedMax, globalMax), power), InsulationUnrestrictedPowerTarget);
    int patched = MAX(power, maxPower);
    if (patched != power) {
        INSULATION_LOG(@"insulation component %d power limit %d -> %d", mitigationType, power, patched);
    }
    return patched;
}

int InsulationMitigationPowerFloor(int power) {
    if (InsulationPowerMitigationsDisabled()) {
        return 0;
    }
    return power;
}

int InsulationLimitedCPUPower(int power) {
    if (power > 0) {
        @synchronized (InsulationStateLock()) {
            InsulationObservedCPUPowerMax = MAX(InsulationObservedCPUPowerMax, power);
        }
    }
    if (InsulationPowerMitigationsDisabled()) {
        return InsulationFullCPUPower(power);
    }
    return power;
}

void InsulationSetCommonProductObject(CommonProduct *product) {
    @synchronized (InsulationStateLock()) {
        InsulationCommonProductObject = product;
    }
}

void InsulationSetMitigationControllerObject(MitigationController *controller) {
    @synchronized (InsulationStateLock()) {
        InsulationMitigationControllerObject = controller;
    }
}

static CommonProduct *InsulationCommonProductSnapshot(void) {
    @synchronized (InsulationStateLock()) {
        return InsulationCommonProductObject;
    }
}

static MitigationController *InsulationMitigationControllerSnapshot(void) {
    @synchronized (InsulationStateLock()) {
        return InsulationMitigationControllerObject;
    }
}

static void InsulationResetObservedPowerState(void) {
    @synchronized (InsulationStateLock()) {
        InsulationObservedCPUPowerMax = 0;
        InsulationObservedComponentPowerGlobalMax = 0;
        [InsulationObservedComponentPowerMax removeAllObjects];
    }
}

static void InsulationClearCPUThrottle(MitigationController *controller) {
    if (!controller) {
        return;
    }
    [controller setPowerSaveActive:NO];
    [controller setCPULevel:0];
}

static void InsulationRestoreFullCPU(MitigationController *controller) {
    if (!controller) {
        return;
    }
    [controller setCPMSMitigationsEnabled:NO];
    InsulationClearCPUThrottle(controller);
    int observedPower = 0;
    @synchronized (InsulationStateLock()) {
        observedPower = InsulationObservedCPUPowerMax;
    }
    int power = MAX(observedPower, InsulationUnrestrictedPowerTarget);
    [controller setCPULowPowerTarget:power];
    [controller setCPUPowerCeiling:power fromDecisionSource:0];
    [controller setCPUPowerFloor:power fromDecisionSource:0];
    [controller setCPUPowerZoneTarget:power];
    [controller setGPUPowerCeiling:power fromDecisionSource:0];
    [controller setGPUPowerFloor:power fromDecisionSource:0];
    [controller setGPUPowerZoneTarget:power];
    [controller setMaxGraphicsDrivePowerTarget:power];
    [controller setMaxPackagePower:power];
    [controller setPackagePowerCeiling:power fromDecisionSource:0];
    [controller setPackagePowerFloor:power fromDecisionSource:0];
    [controller setCPMSMitigationsEnabled:NO];
}


static InsulationCPUMode InsulationRequestedCPUMode(void) {
    NSString *mode = InsulationPowerMode();
    if ([mode isEqualToString:@"fullPower"]) {
        return InsulationCPUModeFullPower;
    }
    if ([mode isEqualToString:@"lowPower"]) {
        return InsulationCPUModeLowPower;
    }
    return InsulationCPUModeOff;
}

static void InsulationApplyCPUPerformancePreference(void) {
    MitigationController *controller = InsulationMitigationControllerSnapshot();
    InsulationCPUMode requestedMode = InsulationRequestedCPUMode();
    BOOL fullPowerGuardActive = requestedMode == InsulationCPUModeFullPower && insulationFullPowerBootGuardActive();
    InsulationCPUStep step;
    @synchronized (InsulationStateLock()) {
        step = InsulationCPUStateStep(&InsulationCPUPerformanceState,
                                      requestedMode,
                                      fullPowerGuardActive,
                                      controller != nil,
                                      InsulationRestoreEventCount);
    }

    if (step.resetObservedPower) {
        InsulationResetObservedPowerState();
    }

    switch (step.action) {
        case InsulationCPUActionApplyFullPower:
            [controller updateCPU];
            InsulationRestoreFullCPU(controller);
            INSULATION_LOG(@"insulation: full power mode");
            return;

        case InsulationCPUActionApplyLowPower: {
            int level = InsulationForcedCPULevel();
            [controller setPowerSaveActive:YES];
            [controller setCPULevel:level];
            [controller updateCPU];
            [controller setPowerSaveActive:YES];
            [controller setCPULevel:level];
            INSULATION_LOG(@"insulation: low power mode at CPU level %d with soft ceiling", level);
            return;
        }

        case InsulationCPUActionRestoreOff:
            [controller updateCPU];
            InsulationClearCPUThrottle(controller);
            INSULATION_LOG(@"CPU performance mode off -> restore native CPU (%d left, phase %d)",
                           step.remainingRestoreCount,
                           step.phase);
            return;

        case InsulationCPUActionWait:
            if (fullPowerGuardActive) {
                INSULATION_LOG(@"insulation: full power warmup guard active, requested mode remains pending");
            } else if (step.remainingRestoreCount > 0) {
                INSULATION_LOG(@"insulation: native CPU restore waiting for MitigationController");
            } else {
                INSULATION_LOG(@"insulation: native thermal CPU mode steady");
            }
            return;
    }
}

static void InsulationApplyThermalTuningPreferences(void) {
    BOOL forceThermalMitigationsOff = InsulationAggressiveFullPowerEnabled();
    int mitigationStatus = forceThermalMitigationsOff
        ? insulationSetThermalMitigationsEnabled(false, true)
        : insulationResetThermalMitigations();
    INSULATION_LOG(@"thermalPowerMode %@ -> mitigation override status %d",
                   forceThermalMitigationsOff ? @"fullPower" : @"native/lowPower",
                   mitigationStatus);
    (void)mitigationStatus;

    InsulationApplyCPUPerformancePreference();

    BOOL suppressNotifications = InsulationBoolPref(@"thermalSuppressNotificationsEnabled", NO);
    int notificationStatus = suppressNotifications
        ? insulationSetOSNotifEnabled(false, true)
        : insulationResetOSNotifEnabled();
    INSULATION_LOG(@"thermalSuppressNotificationsEnabled=%d -> %d", suppressNotifications, notificationStatus);
    (void)notificationStatus;

    BOOL disablePocketSunlight = InsulationBoolPref(@"thermalDisablePocketSunlightEnabled", NO);
    int hipStatus = disablePocketSunlight
        ? insulationSetHIPEnabled(false, true)
        : insulationResetHIP();
    int simulateHIPStatus = disablePocketSunlight
        ? insulationSetSimulateHIPEnabled(false)
        : insulationResetSimulateHIP();
    INSULATION_LOG(@"thermalDisablePocketSunlightEnabled=%d -> %d/%d",
                   disablePocketSunlight,
                   hipStatus,
                   simulateHIPStatus);
    (void)hipStatus;
    (void)simulateHIPStatus;

    BOOL lockSunlight = InsulationBoolPref(@"thermalSunlightLockedEnabled", NO);
    int sunlightStatus = lockSunlight
        ? insulationSetSunlightOverride(true, true)
        : insulationResetSunlightOverride();
    INSULATION_LOG(@"thermalSunlightLockedEnabled=%d -> %d", lockSunlight, sunlightStatus);
    (void)sunlightStatus;
}

static void InsulationExecutePuppetEventLocked(NSString *source) {
    if (InsulationIsApplying) {
        // Coalesce: remember latest request and run once more after current apply finishes.
        InsulationApplyPending = YES;
        InsulationApplyPendingSource = [source copy] ?: @"pending";
        InsulationProbeEvent(@"apply.reentryPending");
        return;
    }

    NSString *activeSource = source ?: @"unknown";
    do {
        InsulationApplyPending = NO;
        InsulationIsApplying = YES;
        @try {
            InsulationReloadPreferences();
            // activeSource is always retained for coalesce trailing apply; probe may be compiled out.
            InsulationProbeRecordApply(InsulationPowerMode(), insulationFullPowerBootGuardActive(), activeSource);
            (void)activeSource;

            CommonProduct *product = InsulationCommonProductSnapshot();
            if (InsulationThermalDimmingBypassActive()) {
                // EXP-D: Aggressive pressure handling (match 0.0.13)
                // Always set nominal and zero pressure, no "light" cap
                [product putDeviceInThermalSimulationMode:@"nominal"];
                [product putDeviceInLowTempSimulationMode:@"nominal"];
                InsulationLastForcedCommonProductThermal = YES;
                int ret = insulationSetDarwinThermalPressure(0);
                InsulationOwnedDarwinThermalPressure = YES;
                INSULATION_LOG(@"insulation dimming bypass thermal state nominal -> Darwin pressure 0 (%d)", ret);
                (void)ret;
            } else if (InsulationLastForcedCommonProductThermal || InsulationOwnedDarwinThermalPressure) {
                [product putDeviceInThermalSimulationMode:@"off"];
                [product putDeviceInLowTempSimulationMode:@"off"];
                InsulationLastForcedCommonProductThermal = NO;
                // Stop owning Darwin pressure. True sensor value cannot be reconstructed; we only
                // drop ownership so thermalmonitord can publish again on the next real update.
                InsulationOwnedDarwinThermalPressure = NO;
                INSULATION_LOG(@"insulation native/lowPower thermal state: released CommonProduct simulation + Darwin ownership");
            } else {
                INSULATION_LOG(@"insulation native/lowPower thermal state: leaving system pressure untouched");
            }
            InsulationApplyThermalTuningPreferences();
        } @finally {
            InsulationIsApplying = NO;
            InsulationProbeEvent(@"apply.finished");
        }

        if (!InsulationApplyPending) {
            break;
        }
        activeSource = InsulationApplyPendingSource ?: @"pending";
        InsulationApplyPendingSource = nil;
    } while (YES);
}

void InsulationExecutePuppetEventWithSource(NSString *source) {
    dispatch_queue_t queue = InsulationApplyQueue();
    if (dispatch_get_specific(InsulationApplyQueueSpecificKey())) {
        ++InsulationSoonGeneration;
        InsulationExecutePuppetEventLocked(source);
        return;
    }
    dispatch_sync(queue, ^{
        ++InsulationSoonGeneration;
        InsulationExecutePuppetEventLocked(source);
    });
}

void InsulationExecutePuppetEvent(void) {
    InsulationExecutePuppetEventWithSource(@"direct");
}

void InsulationExecutePuppetEventSoonWithSource(NSString *source) {
    // Keep InsulationRestoreEventCount in sync with this schedule (4 delayed applies).
    // Generation reads and writes stay on the apply queue to avoid cross-thread races.
    dispatch_queue_t queue = InsulationApplyQueue();
    __block uint64_t generation = 0;
    if (dispatch_get_specific(InsulationApplyQueueSpecificKey())) {
        generation = ++InsulationSoonGeneration;
    } else {
        dispatch_sync(queue, ^{
            generation = ++InsulationSoonGeneration;
        });
    }

    NSString *resolvedSource = [source copy] ?: @"soon";
    NSArray<NSNumber *> *delays = @[@0.25, @1.0, @2.0, @4.0];
    for (NSNumber *delay in delays) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)([delay doubleValue] * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
            dispatch_async(queue, ^{
                if (generation != InsulationSoonGeneration) {
                    return;
                }
                InsulationExecutePuppetEventLocked(resolvedSource);
            });
        });
    }
}

void InsulationExecutePuppetEventSoon(void) {
    InsulationExecutePuppetEventSoonWithSource(@"soon");
}
