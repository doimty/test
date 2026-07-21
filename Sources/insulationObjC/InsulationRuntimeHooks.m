#import "InsulationDebug.h"
#import "InsulationRuntimeHooks.h"

#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <objc/runtime.h>
#import <string.h>

#import "InsulationDictHelper.h"
#import "InsulationPowerHelper.h"
#import "InsulationProbe.h"
#if INSULATION_CPMS_PROBE_ENABLED
#import "InsulationCPMSProbe.h"
#endif
#import "../insulationC/include/Tweak.h"

#if INSULATION_PROBE_ENABLED
static void InsulationRecordMitigationMethodInventory(Class cls) {
    NSMutableArray<NSDictionary *> *inventory = [NSMutableArray array];
    Class currentClass = cls;
    NSUInteger depth = 0;
    while (currentClass && currentClass != [NSObject class]) {
        unsigned int methodCount = 0;
        Method *methods = class_copyMethodList(currentClass, &methodCount);
        for (unsigned int index = 0; index < methodCount; index++) {
            SEL selector = method_getName(methods[index]);
            const char *typeEncoding = method_getTypeEncoding(methods[index]);
            [inventory addObject:@{
                @"class": NSStringFromClass(currentClass) ?: @"<unknown>",
                @"depth": @(depth),
                @"selector": selector ? NSStringFromSelector(selector) : @"<unknown>",
                @"typeEncoding": typeEncoding ? [NSString stringWithUTF8String:typeEncoding] : @"",
            }];
        }
        free(methods);
        currentClass = class_getSuperclass(currentClass);
        depth += 1;
    }

    [inventory sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        NSComparisonResult classOrder = [left[@"class"] compare:right[@"class"]];
        if (classOrder != NSOrderedSame) {
            return classOrder;
        }
        return [left[@"selector"] compare:right[@"selector"]];
    }];
    InsulationProbeRecordMethodDump(@"MitigationController", inventory);
}
#endif

static id (*Orig_NSDictionary_dictionaryWithContentsOfFile)(Class self, SEL _cmd, id path);



static id (*Orig_CommonProduct_initProduct)(id self, SEL _cmd, id arg);
static void (*Orig_CommonProduct_tryTakeAction)(id self, SEL _cmd);
static void (*Orig_CommonProduct_handleMCSThermalPressure)(id self, SEL _cmd);
static void (*Orig_CommonProduct_simulateLightThermalPressure)(id self, SEL _cmd);
static void (*Orig_CommonProduct_updatePowerzoneTelemetry)(id self, SEL _cmd);

static void (*Orig_MitigationController_setPowerSaveActive)(id self, SEL _cmd, BOOL active);
static void (*Orig_MitigationController_setCPMSMitigationsEnabled)(id self, SEL _cmd, BOOL enabled);
static void (*Orig_MitigationController_setCPULevel)(id self, SEL _cmd, int level);
static void (*Orig_MitigationController_setCPULowPowerTarget)(id self, SEL _cmd, int power);
static void (*Orig_MitigationController_setCPUPowerCeilingFromDecisionSource)(id self, SEL _cmd, int power, int source);
static void (*Orig_MitigationController_setCPUPowerCeilingForDVD1Contributor)(id self, SEL _cmd, int power, int contributor);
static void (*Orig_MitigationController_setCPUPowerFloorFromDecisionSource)(id self, SEL _cmd, int power, int source);
static void (*Orig_MitigationController_setCPUPowerZoneTarget)(id self, SEL _cmd, int power);
static void (*Orig_MitigationController_setDVD1Level)(id self, SEL _cmd, int level);
static void (*Orig_MitigationController_setGPUPowerCeilingFromDecisionSource)(id self, SEL _cmd, int power, int source);
static void (*Orig_MitigationController_setGPUPowerFloorFromDecisionSource)(id self, SEL _cmd, int power, int source);
static void (*Orig_MitigationController_setGPUPowerZoneTarget)(id self, SEL _cmd, int power);
static void (*Orig_MitigationController_setSGXLevel)(id self, SEL _cmd, int level);
static void (*Orig_MitigationController_setMaxGraphicsDrivePowerTarget)(id self, SEL _cmd, int power);
static void (*Orig_MitigationController_setMaxCPUPowerTarget_useLegacyPath_setProperty)(id self, SEL _cmd, int power, BOOL useLegacyPath, id property);
static void (*Orig_MitigationController_setPackagePowerBudgetDirect_withDetails)(id self, SEL _cmd, int power, unsigned long long details);
static void (*Orig_MitigationController_setPackagePowerCeilingFromDecisionSource)(id self, SEL _cmd, int power, int source);
static void (*Orig_MitigationController_setPackagePowerFloorFromDecisionSource)(id self, SEL _cmd, int power, int source);
static void (*Orig_MitigationController_setMaxPackagePower)(id self, SEL _cmd, int power);
static void (*Orig_MitigationController_setPackageLowPowerTarget)(id self, SEL _cmd);
static void (*Orig_MitigationController_setPackagePowerZoneTarget)(id self, SEL _cmd);
static void (*Orig_MitigationController_updateCPU)(id self, SEL _cmd);
static void (*Orig_MitigationController_updateGPU)(id self, SEL _cmd);
static void (*Orig_MitigationController_updatePackage)(id self, SEL _cmd);
static void (*Orig_MitigationController_setDieTempControllerProperty)(id self, SEL _cmd, CFStringRef property, int level, BOOL scaleToFixedPoint);
static int (*Orig_MitigationController_setServiceProperty)(id self, SEL _cmd, unsigned service, CFStringRef key, int value, BOOL scaleToFixedPoint);
static void *InsulationLastObservedMitigationControllerPtr;


static id Insulation_NSDictionary_dictionaryWithContentsOfFile(Class self, SEL _cmd, id path) {
    id result = Orig_NSDictionary_dictionaryWithContentsOfFile ? Orig_NSDictionary_dictionaryWithContentsOfFile(self, _cmd, path) : nil;
    if ([path isKindOfClass:[NSString class]] && [(NSString *)path containsString:@"/System/Library/ThermalMonitor/"]) {
        if ([result isKindOfClass:[NSDictionary class]]) {
            return InsulationPatchThermalPlist((NSDictionary *)result);
        }
    }
    return result;
}


static BOOL InsulationHookClassMethod(Class cls, SEL selector, IMP replacement, IMP *originalOut) {
    __unused NSString *className = cls ? NSStringFromClass(cls) : @"<missing-class>";
    __unused NSString *selectorName = selector ? NSStringFromSelector(selector) : @"<missing-selector>";
    if (!cls || !selector || !replacement || !originalOut) {
        InsulationProbeRecordHookInstall(className, selectorName, NO);
        return NO;
    }
    Method method = class_getClassMethod(cls, selector);
    if (!method) {
        INSULATION_LOG(@"insulation objc-port: missing class method %@ on %@", selectorName, className);
        InsulationProbeRecordHookInstall(className, selectorName, NO);
        return NO;
    }
    *originalOut = method_getImplementation(method);
    method_setImplementation(method, replacement);
    INSULATION_LOG(@"insulation objc-port: hooked class method %@ on %@", selectorName, className);
    InsulationProbeRecordHookInstall(className, selectorName, YES);
    return YES;
}

static BOOL InsulationHookInstanceMethod(Class cls, SEL selector, IMP replacement, IMP *originalOut) {
    __unused NSString *className = cls ? NSStringFromClass(cls) : @"<missing-class>";
    __unused NSString *selectorName = selector ? NSStringFromSelector(selector) : @"<missing-selector>";
    if (!cls || !selector || !replacement || !originalOut) {
        InsulationProbeRecordHookInstall(className, selectorName, NO);
        return NO;
    }
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) {
        INSULATION_LOG(@"insulation objc-port: missing instance method %@ on %@", selectorName, className);
        InsulationProbeRecordHookInstall(className, selectorName, NO);
        return NO;
    }
    *originalOut = method_getImplementation(method);
    method_setImplementation(method, replacement);
    INSULATION_LOG(@"insulation objc-port: hooked instance method %@ on %@", selectorName, className);
    InsulationProbeRecordHookInstall(className, selectorName, YES);
    return YES;
}


static id Insulation_CommonProduct_initProduct(id self, SEL _cmd, id arg) {
    id result = Orig_CommonProduct_initProduct(self, _cmd, arg);
    InsulationSetCommonProductObject((CommonProduct *)self);
    // Probe27: isolate probe-line CommonProduct behavior. Direct apply only, no delayed soon replay.
    InsulationExecutePuppetEventWithSource(@"commonProduct.initProduct");
    return result;
}

static void Insulation_CommonProduct_tryTakeAction(id self, SEL _cmd) {
    CommonProduct *product = (CommonProduct *)self;
    BOOL bypass = InsulationThermalDimmingBypassActive();
    if (bypass) {
        [product putDeviceInThermalSimulationMode:@"nominal"];
        [product putDeviceInLowTempSimulationMode:@"nominal"];
    }
    Orig_CommonProduct_tryTakeAction(self, _cmd);
    // Probe27: no post-tryTakeAction apply. Tests whether removing stablebase replay causes repair.
}

static void Insulation_CommonProduct_suppressWhenDimmingActive(id self, SEL _cmd, void (*original)(id, SEL)) {
    BOOL bypass = InsulationThermalDimmingBypassActive();
    if (bypass) {
        // Probe27: bypass without apply. Tests CommonProduct replay removal independently from setter changes.
        return;
    }
    original(self, _cmd);
}

static void Insulation_CommonProduct_handleMCSThermalPressure(id self, SEL _cmd) {
    Insulation_CommonProduct_suppressWhenDimmingActive(self, _cmd, Orig_CommonProduct_handleMCSThermalPressure);
}

static void Insulation_CommonProduct_simulateLightThermalPressure(id self, SEL _cmd) {
    Insulation_CommonProduct_suppressWhenDimmingActive(self, _cmd, Orig_CommonProduct_simulateLightThermalPressure);
}

static void Insulation_CommonProduct_updatePowerzoneTelemetry(id self, SEL _cmd) {
    Insulation_CommonProduct_suppressWhenDimmingActive(self, _cmd, Orig_CommonProduct_updatePowerzoneTelemetry);
}

// HidSensors hook: block temperature events to prevent throttling


// MitigationController setter hooks: prevent double-swizzle by installing them here only,
// not in ThermalManagerDimmingPatch.m. Low-power mode writes setPowerSaveActive:/setCPULevel:
// directly and needs these hooks installed.


static void InsulationRecordMitigationSetter(id self, NSString *name, NSInteger originalValue, NSInteger patchedValue) {
    if (self) {
        InsulationSetMitigationControllerObject((MitigationController *)self);
    }
#if INSULATION_PROBE_ENABLED
    InsulationProbeRecordSetter(name, originalValue, patchedValue);
#else
    (void)name;
    (void)originalValue;
    (void)patchedValue;
#endif
}

static void Insulation_MitigationController_setPowerSaveActive(id self, SEL _cmd, BOOL active) {
    if (InsulationPowerMitigationsDisabled() || InsulationCPURestoreActive()) {
        InsulationSetMitigationControllerObject((MitigationController *)self);
        InsulationProbeRecordSetterDetails(@"setPowerSaveActive", active ? 1 : 0, 0, @{
            @"selector": @"setPowerSaveActive:",
            @"mode": @"fullPowerOrRestore",
        });
        Orig_MitigationController_setPowerSaveActive(self, _cmd, NO);
        return;
    }
    if (InsulationCPULimitEnabled()) {
        InsulationSetMitigationControllerObject((MitigationController *)self);
        InsulationProbeRecordSetterDetails(@"setPowerSaveActive", active ? 1 : 0, 1, @{
            @"selector": @"setPowerSaveActive:",
            @"mode": @"cpuLimit",
        });
        Orig_MitigationController_setPowerSaveActive(self, _cmd, YES);
        return;
    }
    InsulationSetMitigationControllerObject((MitigationController *)self);
    InsulationProbeRecordSetterDetails(@"setPowerSaveActive", active ? 1 : 0, active ? 1 : 0, @{
        @"selector": @"setPowerSaveActive:",
        @"mode": @"passthrough",
    });
    Orig_MitigationController_setPowerSaveActive(self, _cmd, active);
}

static void Insulation_MitigationController_setCPMSMitigationsEnabled(id self, SEL _cmd, BOOL enabled) {
    BOOL patched = InsulationPowerMitigationsDisabled() ? NO : enabled;
    InsulationSetMitigationControllerObject((MitigationController *)self);
    InsulationProbeRecordSetterDetails(@"setCPMSMitigationsEnabled", enabled ? 1 : 0, patched ? 1 : 0, @{
        @"selector": @"setCPMSMitigationsEnabled:",
    });
    Orig_MitigationController_setCPMSMitigationsEnabled(self, _cmd, patched);
}

static void Insulation_MitigationController_setCPULevel(id self, SEL _cmd, int level) {
    BOOL disabled = InsulationPowerMitigationsDisabled();
    int patched = disabled ? 0 : InsulationLimitedCPULevel(level);
    InsulationRecordMitigationSetter(self, @"setCPULevel", level, patched);
    Orig_MitigationController_setCPULevel(self, _cmd, patched);
}

static void Insulation_MitigationController_setCPULowPowerTarget(id self, SEL _cmd, int power) {
    // Cold-start repair guard: do not clear target/floor/zone to 0 in fullPower.
    // Stablebase used high unrestricted target semantics here; probe17's zeroing path
    // is correlated with startup repair state.
    int patched = InsulationPowerMitigationsDisabled() ? MAX(power, InsulationUnrestrictedPowerLimit()) : InsulationLimitedCPUPower(power);
    InsulationRecordMitigationSetter(self, @"setCPULowPowerTarget", power, patched);
    Orig_MitigationController_setCPULowPowerTarget(self, _cmd, patched);
}

static void Insulation_MitigationController_setCPUPowerCeilingFromDecisionSource(id self, SEL _cmd, int power, int source) {
    int patched = InsulationPowerMitigationsDisabled() ? MAX(power, InsulationUnrestrictedPowerLimit()) : InsulationLimitedCPUPower(power);
    InsulationSetMitigationControllerObject((MitigationController *)self);
    InsulationProbeRecordSetterDetails(@"setCPUPowerCeiling", power, patched, @{
        @"selector": @"setCPUPowerCeiling:fromDecisionSource:",
        @"source": @(source),
    });
    Orig_MitigationController_setCPUPowerCeilingFromDecisionSource(self, _cmd, patched, source);
}

static void Insulation_MitigationController_setCPUPowerCeilingForDVD1Contributor(id self, SEL _cmd, int power, int contributor) {
    int patched = InsulationPowerMitigationsDisabled() ? MAX(power, InsulationUnrestrictedPowerLimit()) : InsulationLimitedCPUPower(power);
    InsulationRecordMitigationSetter(self, @"setCPUPowerCeilingForDVD1Contributor", power, patched);
    Orig_MitigationController_setCPUPowerCeilingForDVD1Contributor(self, _cmd, patched, contributor);
}

static void Insulation_MitigationController_setCPUPowerFloorFromDecisionSource(id self, SEL _cmd, int power, int source) {
    int patched = InsulationPowerMitigationsDisabled() ? MAX(power, InsulationUnrestrictedPowerLimit()) : InsulationMitigationPowerFloor(power);
    InsulationRecordMitigationSetter(self, @"setCPUPowerFloor", power, patched);
    Orig_MitigationController_setCPUPowerFloorFromDecisionSource(self, _cmd, patched, source);
}

static void Insulation_MitigationController_setCPUPowerZoneTarget(id self, SEL _cmd, int power) {
    int patched = InsulationPowerMitigationsDisabled() ? MAX(power, InsulationUnrestrictedPowerLimit()) : InsulationLimitedCPUPower(power);
    InsulationRecordMitigationSetter(self, @"setCPUPowerZoneTarget", power, patched);
    Orig_MitigationController_setCPUPowerZoneTarget(self, _cmd, patched);
}

static void Insulation_MitigationController_setDVD1Level(id self, SEL _cmd, int level) {
    int patched = InsulationPowerMitigationsDisabled() ? 0 : level;
    InsulationRecordMitigationSetter(self, @"setDVD1Level", level, patched);
    Orig_MitigationController_setDVD1Level(self, _cmd, patched);
}

static void Insulation_MitigationController_setGPUPowerCeilingFromDecisionSource(id self, SEL _cmd, int power, int source) {
    int patched = InsulationPowerMitigationsDisabled() ? MAX(power, InsulationUnrestrictedPowerLimit()) : power;
    InsulationSetMitigationControllerObject((MitigationController *)self);
    InsulationProbeRecordSetterDetails(@"setGPUPowerCeiling", power, patched, @{
        @"selector": @"setGPUPowerCeiling:fromDecisionSource:",
        @"source": @(source),
    });
    Orig_MitigationController_setGPUPowerCeilingFromDecisionSource(self, _cmd, patched, source);
}

static void Insulation_MitigationController_setGPUPowerFloorFromDecisionSource(id self, SEL _cmd, int power, int source) {
    int patched = InsulationPowerMitigationsDisabled() ? MAX(power, InsulationUnrestrictedPowerLimit()) : power;
    InsulationRecordMitigationSetter(self, @"setGPUPowerFloor", power, patched);
    Orig_MitigationController_setGPUPowerFloorFromDecisionSource(self, _cmd, patched, source);
}

static void Insulation_MitigationController_setGPUPowerZoneTarget(id self, SEL _cmd, int power) {
    int patched = InsulationPowerMitigationsDisabled() ? MAX(power, InsulationUnrestrictedPowerLimit()) : power;
    InsulationRecordMitigationSetter(self, @"setGPUPowerZoneTarget", power, patched);
    Orig_MitigationController_setGPUPowerZoneTarget(self, _cmd, patched);
}

static void Insulation_MitigationController_setSGXLevel(id self, SEL _cmd, int level) {
    int patched = InsulationPowerMitigationsDisabled() ? 0 : level;
    InsulationRecordMitigationSetter(self, @"setSGXLevel", level, patched);
    Orig_MitigationController_setSGXLevel(self, _cmd, patched);
}

static void Insulation_MitigationController_setMaxGraphicsDrivePowerTarget(id self, SEL _cmd, int power) {
    int patched = InsulationPowerMitigationsDisabled() ? MAX(power, InsulationUnrestrictedPowerLimit()) : power;
    InsulationRecordMitigationSetter(self, @"setMaxGraphicsDrivePowerTarget", power, patched);
    Orig_MitigationController_setMaxGraphicsDrivePowerTarget(self, _cmd, patched);
}

static void Insulation_MitigationController_setMaxCPUPowerTarget_useLegacyPath_setProperty(id self, SEL _cmd, int power, BOOL useLegacyPath, id property) {
    // Cold-start repair guard: never lower the system-provided max CPU target.
    // Probe telemetry showed thermalmonitord requesting 65000 while probe17 clamped it to 50000.
    int patched = InsulationPowerMitigationsDisabled() ? MAX(power, InsulationUnrestrictedPowerLimit()) : power;
    InsulationSetMitigationControllerObject((MitigationController *)self);
    InsulationProbeRecordSetterDetails(@"setMaxCPUPowerTarget", power, patched, @{
        @"selector": @"setMaxCPUPowerTarget:useLegacyPath:setProperty:",
        @"useLegacyPath": @(useLegacyPath),
        @"propertyClass": property ? NSStringFromClass([property class]) : @"nil",
        @"propertyDescription": property ? [property description] : @"nil",
    });
    Orig_MitigationController_setMaxCPUPowerTarget_useLegacyPath_setProperty(self, _cmd, patched, useLegacyPath, property);
}

static void Insulation_MitigationController_setPackagePowerBudgetDirect_withDetails(id self, SEL _cmd, int power, unsigned long long details) {
    int patched = InsulationPowerMitigationsDisabled() ? MAX(power, InsulationUnrestrictedPowerLimit()) : power;
    InsulationSetMitigationControllerObject((MitigationController *)self);
    InsulationProbeRecordSetterDetails(@"setPackagePowerBudgetDirect", power, patched, @{
        @"selector": @"setPackagePowerBudgetDirect:withDetails:",
        @"details": @(details),
    });
    Orig_MitigationController_setPackagePowerBudgetDirect_withDetails(self, _cmd, patched, details);
}

static void Insulation_MitigationController_setPackagePowerCeilingFromDecisionSource(id self, SEL _cmd, int power, int source) {
    int patched = InsulationPowerMitigationsDisabled() ? MAX(power, InsulationUnrestrictedPowerLimit()) : power;
    InsulationSetMitigationControllerObject((MitigationController *)self);
    InsulationProbeRecordSetterDetails(@"setPackagePowerCeiling", power, patched, @{
        @"selector": @"setPackagePowerCeiling:fromDecisionSource:",
        @"source": @(source),
    });
    Orig_MitigationController_setPackagePowerCeilingFromDecisionSource(self, _cmd, patched, source);
}

static void Insulation_MitigationController_setPackagePowerFloorFromDecisionSource(id self, SEL _cmd, int power, int source) {
    int patched = InsulationPowerMitigationsDisabled() ? MAX(power, InsulationUnrestrictedPowerLimit()) : power;
    InsulationRecordMitigationSetter(self, @"setPackagePowerFloor", power, patched);
    Orig_MitigationController_setPackagePowerFloorFromDecisionSource(self, _cmd, patched, source);
}

static void Insulation_MitigationController_setMaxPackagePower(id self, SEL _cmd, int power) {
    int patched = InsulationPowerMitigationsDisabled() ? MAX(power, InsulationUnrestrictedPowerLimit()) : power;
    InsulationRecordMitigationSetter(self, @"setMaxPackagePower", power, patched);
    Orig_MitigationController_setMaxPackagePower(self, _cmd, patched);
}

static void Insulation_MitigationController_setPackageLowPowerTarget(id self, SEL _cmd) {
    if (InsulationPowerMitigationsDisabled()) {
        InsulationRecordMitigationSetter(self, @"setPackageLowPowerTarget", 1, 0);
        return;
    }
    InsulationRecordMitigationSetter(self, @"setPackageLowPowerTarget", 1, 1);
    Orig_MitigationController_setPackageLowPowerTarget(self, _cmd);
}

static void Insulation_MitigationController_setPackagePowerZoneTarget(id self, SEL _cmd) {
    if (InsulationPowerMitigationsDisabled()) {
        InsulationRecordMitigationSetter(self, @"setPackagePowerZoneTarget", 1, 0);
        return;
    }
    InsulationRecordMitigationSetter(self, @"setPackagePowerZoneTarget", 1, 1);
    Orig_MitigationController_setPackagePowerZoneTarget(self, _cmd);
}

// Update hooks capture the live MitigationController object. Low-power mode needs that
// object for direct setPowerSaveActive:/setCPULevel: writes after a thermalmonitord restart.
static BOOL InsulationCaptureMitigationControllerIfChanged(id self) {
    void *ptr = (__bridge void *)self;
    InsulationSetMitigationControllerObject((MitigationController *)self);
    if (!ptr || ptr == InsulationLastObservedMitigationControllerPtr) {
        return NO;
    }
    InsulationLastObservedMitigationControllerPtr = ptr;
    return YES;
}

static void InsulationApplyAfterMitigationControllerCapture(BOOL changed) {
    if (!changed) {
        return;
    }
    // Cold-start repair guard: restore stablebase cadence for new MitigationController.
    // Probe17's 0.25/0.75/1.5/3.0s burst repeatedly applied fullPower during startup
    // and is correlated with repair state.
    InsulationProbeRecordSelfHeal(@"newObjectStablebaseCadence");
    InsulationExecutePuppetEventWithSource(@"mitigation.newObject");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        InsulationExecutePuppetEventWithSource(@"mitigation.newObjectSoon");
    });
}

static void Insulation_MitigationController_updateCPU(id self, SEL _cmd) {
    BOOL changed = InsulationCaptureMitigationControllerIfChanged(self);
    InsulationProbeRecordMitigationUpdate(@"updateCPU", changed);
    Orig_MitigationController_updateCPU(self, _cmd);
    InsulationApplyAfterMitigationControllerCapture(changed);
}

static void Insulation_MitigationController_updateGPU(id self, SEL _cmd) {
    BOOL changed = InsulationCaptureMitigationControllerIfChanged(self);
    InsulationProbeRecordMitigationUpdate(@"updateGPU", changed);
    Orig_MitigationController_updateGPU(self, _cmd);
    InsulationApplyAfterMitigationControllerCapture(changed);
}

static void Insulation_MitigationController_updatePackage(id self, SEL _cmd) {
    BOOL changed = InsulationCaptureMitigationControllerIfChanged(self);
    InsulationProbeRecordMitigationUpdate(@"updatePackage", changed);
    Orig_MitigationController_updatePackage(self, _cmd);
    InsulationApplyAfterMitigationControllerCapture(changed);
}

#if INSULATION_PROBE_ENABLED
static NSString *InsulationProbeCopyCFString(CFStringRef value) {
    if (!value) {
        return @"nil";
    }
    return [(__bridge NSString *)value copy];
}

static void Insulation_MitigationController_setDieTempControllerProperty(id self, SEL _cmd, CFStringRef property, int level, BOOL scaleToFixedPoint) {
    if (InsulationThermalDimmingBypassActive()) {
        // Raise die temperature threshold to prevent thermal throttling
        int raisedLevel = scaleToFixedPoint ? 12500 : 125;
        Orig_MitigationController_setDieTempControllerProperty(self, _cmd, property, raisedLevel, scaleToFixedPoint);
    } else {
        Orig_MitigationController_setDieTempControllerProperty(self, _cmd, property, level, scaleToFixedPoint);
    }
}

static int Insulation_MitigationController_setServiceProperty(id self, SEL _cmd, unsigned service, CFStringRef key, int value, BOOL scaleToFixedPoint) {
    if (InsulationThermalDimmingBypassActive()) {
        // Suppress IOKit property writes that could cause throttling
        return Orig_MitigationController_setServiceProperty(self, _cmd, service, key, 0, scaleToFixedPoint);
    }
    return Orig_MitigationController_setServiceProperty(self, _cmd, service, key, value, scaleToFixedPoint);
}
#endif


static void InsulationInstallNSDictionaryHooks(void) {
    Class dictionaryClass = objc_getClass("NSDictionary");
    InsulationHookClassMethod(dictionaryClass,
                              @selector(dictionaryWithContentsOfFile:),
                              (IMP)Insulation_NSDictionary_dictionaryWithContentsOfFile,
                              (IMP *)&Orig_NSDictionary_dictionaryWithContentsOfFile);
}


static void InsulationInstallCommonProductHooks(void) {
    Class commonProductClass = objc_getClass("CommonProduct");
    InsulationHookInstanceMethod(commonProductClass,
                                 @selector(initProduct:),
                                 (IMP)Insulation_CommonProduct_initProduct,
                                 (IMP *)&Orig_CommonProduct_initProduct);
    InsulationHookInstanceMethod(commonProductClass,
                                 @selector(tryTakeAction),
                                 (IMP)Insulation_CommonProduct_tryTakeAction,
                                 (IMP *)&Orig_CommonProduct_tryTakeAction);
    InsulationHookInstanceMethod(commonProductClass,
                                 @selector(handleMCSThermalPressure),
                                 (IMP)Insulation_CommonProduct_handleMCSThermalPressure,
                                 (IMP *)&Orig_CommonProduct_handleMCSThermalPressure);
    InsulationHookInstanceMethod(commonProductClass,
                                 @selector(simulateLightThermalPressure),
                                 (IMP)Insulation_CommonProduct_simulateLightThermalPressure,
                                 (IMP *)&Orig_CommonProduct_simulateLightThermalPressure);
    InsulationHookInstanceMethod(commonProductClass,
                                 @selector(updatePowerzoneTelemetry),
                                 (IMP)Insulation_CommonProduct_updatePowerzoneTelemetry,
                                 (IMP *)&Orig_CommonProduct_updatePowerzoneTelemetry);
}


static void InsulationInstallMitigationControllerSetterHooks(void) {
    Class mitigationClass = objc_getClass("MitigationController");
    InsulationHookInstanceMethod(mitigationClass, @selector(setPowerSaveActive:), (IMP)Insulation_MitigationController_setPowerSaveActive, (IMP *)&Orig_MitigationController_setPowerSaveActive);
    InsulationHookInstanceMethod(mitigationClass, @selector(setCPMSMitigationsEnabled:), (IMP)Insulation_MitigationController_setCPMSMitigationsEnabled, (IMP *)&Orig_MitigationController_setCPMSMitigationsEnabled);
    InsulationHookInstanceMethod(mitigationClass, @selector(setCPULevel:), (IMP)Insulation_MitigationController_setCPULevel, (IMP *)&Orig_MitigationController_setCPULevel);
    InsulationHookInstanceMethod(mitigationClass, @selector(setCPULowPowerTarget:), (IMP)Insulation_MitigationController_setCPULowPowerTarget, (IMP *)&Orig_MitigationController_setCPULowPowerTarget);
    InsulationHookInstanceMethod(mitigationClass, @selector(setCPUPowerCeiling:fromDecisionSource:), (IMP)Insulation_MitigationController_setCPUPowerCeilingFromDecisionSource, (IMP *)&Orig_MitigationController_setCPUPowerCeilingFromDecisionSource);
    InsulationHookInstanceMethod(mitigationClass, @selector(setCPUPowerCeiling:forDVD1Contributor:), (IMP)Insulation_MitigationController_setCPUPowerCeilingForDVD1Contributor, (IMP *)&Orig_MitigationController_setCPUPowerCeilingForDVD1Contributor);
    InsulationHookInstanceMethod(mitigationClass, @selector(setCPUPowerFloor:fromDecisionSource:), (IMP)Insulation_MitigationController_setCPUPowerFloorFromDecisionSource, (IMP *)&Orig_MitigationController_setCPUPowerFloorFromDecisionSource);
    InsulationHookInstanceMethod(mitigationClass, @selector(setCPUPowerZoneTarget:), (IMP)Insulation_MitigationController_setCPUPowerZoneTarget, (IMP *)&Orig_MitigationController_setCPUPowerZoneTarget);
    InsulationHookInstanceMethod(mitigationClass, @selector(setDVD1Level:), (IMP)Insulation_MitigationController_setDVD1Level, (IMP *)&Orig_MitigationController_setDVD1Level);
    InsulationHookInstanceMethod(mitigationClass, @selector(setGPUPowerCeiling:fromDecisionSource:), (IMP)Insulation_MitigationController_setGPUPowerCeilingFromDecisionSource, (IMP *)&Orig_MitigationController_setGPUPowerCeilingFromDecisionSource);
    InsulationHookInstanceMethod(mitigationClass, @selector(setGPUPowerFloor:fromDecisionSource:), (IMP)Insulation_MitigationController_setGPUPowerFloorFromDecisionSource, (IMP *)&Orig_MitigationController_setGPUPowerFloorFromDecisionSource);
    InsulationHookInstanceMethod(mitigationClass, @selector(setGPUPowerZoneTarget:), (IMP)Insulation_MitigationController_setGPUPowerZoneTarget, (IMP *)&Orig_MitigationController_setGPUPowerZoneTarget);
    InsulationHookInstanceMethod(mitigationClass, @selector(setSGXLevel:), (IMP)Insulation_MitigationController_setSGXLevel, (IMP *)&Orig_MitigationController_setSGXLevel);
    InsulationHookInstanceMethod(mitigationClass, @selector(setMaxGraphicsDrivePowerTarget:), (IMP)Insulation_MitigationController_setMaxGraphicsDrivePowerTarget, (IMP *)&Orig_MitigationController_setMaxGraphicsDrivePowerTarget);
    InsulationHookInstanceMethod(mitigationClass, @selector(setMaxCPUPowerTarget:useLegacyPath:setProperty:), (IMP)Insulation_MitigationController_setMaxCPUPowerTarget_useLegacyPath_setProperty, (IMP *)&Orig_MitigationController_setMaxCPUPowerTarget_useLegacyPath_setProperty);
    InsulationHookInstanceMethod(mitigationClass, @selector(setPackagePowerBudgetDirect:withDetails:), (IMP)Insulation_MitigationController_setPackagePowerBudgetDirect_withDetails, (IMP *)&Orig_MitigationController_setPackagePowerBudgetDirect_withDetails);
    InsulationHookInstanceMethod(mitigationClass, @selector(setPackagePowerCeiling:fromDecisionSource:), (IMP)Insulation_MitigationController_setPackagePowerCeilingFromDecisionSource, (IMP *)&Orig_MitigationController_setPackagePowerCeilingFromDecisionSource);
    InsulationHookInstanceMethod(mitigationClass, @selector(setPackagePowerFloor:fromDecisionSource:), (IMP)Insulation_MitigationController_setPackagePowerFloorFromDecisionSource, (IMP *)&Orig_MitigationController_setPackagePowerFloorFromDecisionSource);
    InsulationHookInstanceMethod(mitigationClass, @selector(setMaxPackagePower:), (IMP)Insulation_MitigationController_setMaxPackagePower, (IMP *)&Orig_MitigationController_setMaxPackagePower);
    InsulationHookInstanceMethod(mitigationClass, @selector(setPackageLowPowerTarget), (IMP)Insulation_MitigationController_setPackageLowPowerTarget, (IMP *)&Orig_MitigationController_setPackageLowPowerTarget);
    InsulationHookInstanceMethod(mitigationClass, @selector(setPackagePowerZoneTarget), (IMP)Insulation_MitigationController_setPackagePowerZoneTarget, (IMP *)&Orig_MitigationController_setPackagePowerZoneTarget);
}

#if INSULATION_PROBE_ENABLED
static BOOL InsulationHookProbeInstanceMethodWithEncoding(Class cls, SEL selector, const char *expectedEncoding, IMP replacement, IMP *originalOut) {
    NSString *className = cls ? NSStringFromClass(cls) : @"<missing-class>";
    NSString *selectorName = selector ? NSStringFromSelector(selector) : @"<missing-selector>";
    Method method = (cls && selector) ? class_getInstanceMethod(cls, selector) : NULL;
    const char *actualEncoding = method ? method_getTypeEncoding(method) : NULL;
    if (!method || !actualEncoding || strcmp(actualEncoding, expectedEncoding) != 0) {
        InsulationProbeRecordHookInstall(className, selectorName, NO);
        return NO;
    }
    *originalOut = method_getImplementation(method);
    method_setImplementation(method, replacement);
    InsulationProbeRecordHookInstall(className, selectorName, YES);
    return YES;
}

static void InsulationInstallMitigationControllerDirectWriteProbeHooks(void) {
    Class mitigationClass = objc_getClass("MitigationController");
    InsulationHookProbeInstanceMethodWithEncoding(mitigationClass,
                                                   NSSelectorFromString(@"setDieTempControllerProperty:level:scaleToFixedPoint:"),
                                                   "v32@0:8^{__CFString=}16i24B28",
                                                   (IMP)Insulation_MitigationController_setDieTempControllerProperty,
                                                   (IMP *)&Orig_MitigationController_setDieTempControllerProperty);
    InsulationHookProbeInstanceMethodWithEncoding(mitigationClass,
                                                   NSSelectorFromString(@"setServiceProperty:key:value:scaleToFixedPoint:"),
                                                   "i36@0:8I16^{__CFString=}20i28B32",
                                                   (IMP)Insulation_MitigationController_setServiceProperty,
                                                   (IMP *)&Orig_MitigationController_setServiceProperty);
}
#endif

static void InsulationInstallMitigationControllerIOKitHooks(void) {
    Class mitigationClass = objc_getClass("MitigationController");
    InsulationHookProbeInstanceMethodWithEncoding(mitigationClass,
                                                   NSSelectorFromString(@"setDieTempControllerProperty:level:scaleToFixedPoint:"),
                                                   "v32@0:8^{__CFString=}16i24B28",
                                                   (IMP)Insulation_MitigationController_setDieTempControllerProperty,
                                                   (IMP *)&Orig_MitigationController_setDieTempControllerProperty);
    InsulationHookProbeInstanceMethodWithEncoding(mitigationClass,
                                                   NSSelectorFromString(@"setServiceProperty:key:value:scaleToFixedPoint:"),
                                                   "i36@0:8I16^{__CFString=}20i28B32",
                                                   (IMP)Insulation_MitigationController_setServiceProperty,
                                                   (IMP *)&Orig_MitigationController_setServiceProperty);
}

static void InsulationInstallMitigationControllerUpdateHooks(void) {
    Class mitigationClass = objc_getClass("MitigationController");
    // Disabled for cold-start repair isolation: stablebase did not hook the initializer.
    // Hooking initForFastLoop:noDisplay:powerSaveParams:powerZoneParams: captures the controller
    // during startup and immediately applies fullPower; that path is the current suspect.
    InsulationProbeRecordHookInstall(@"MitigationController", @"initForFastLoop:noDisplay:powerSaveParams:powerZoneParams:", NO);
    InsulationHookInstanceMethod(mitigationClass, @selector(updateCPU), (IMP)Insulation_MitigationController_updateCPU, (IMP *)&Orig_MitigationController_updateCPU);
    InsulationHookInstanceMethod(mitigationClass, @selector(updateGPU), (IMP)Insulation_MitigationController_updateGPU, (IMP *)&Orig_MitigationController_updateGPU);
    InsulationHookInstanceMethod(mitigationClass, @selector(updatePackage), (IMP)Insulation_MitigationController_updatePackage, (IMP *)&Orig_MitigationController_updatePackage);
}

void InsulationRuntimeHooksInstall(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        InsulationInstallNSDictionaryHooks();
        InsulationInstallCommonProductHooks();
        InsulationInstallMitigationControllerSetterHooks();
        InsulationInstallMitigationControllerUpdateHooks();
        InsulationInstallMitigationControllerIOKitHooks();
#if INSULATION_PROBE_ENABLED
        InsulationInstallMitigationControllerDirectWriteProbeHooks();
        InsulationRecordMitigationMethodInventory(objc_getClass("MitigationController"));
#endif
#if INSULATION_CPMS_PROBE_ENABLED
        InsulationCPMSProbeInstall();
#endif
    });
}
