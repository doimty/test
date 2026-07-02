#import "InsulationDebug.h"
#import "InsulationRuntimeHooks.h"

#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <objc/runtime.h>

#import "InsulationDictHelper.h"
#import "InsulationPowerHelper.h"
#import "InsulationProbe.h"
#import "../insulationC/include/Tweak.h"

static NSString *InsulationFilterMethodName(NSString *name) {
    if (![name isKindOfClass:[NSString class]] || [name length] == 0) {
        return nil;
    }
    NSSet<NSString *> *tokens = [NSSet setWithArray:@[@"TargetPower", @"LowPower", @"Ceiling", @"Floor", @"Zone", @"PowerSave", @"Level", @"Mitigation", @"Package", @"GPU", @"CPU"]];
    for (NSString *token in tokens) {
        if ([name rangeOfString:token].location != NSNotFound) {
            return name;
        }
    }
    return nil;
}

static void InsulationDumpClassMethods(Class cls, NSString *className) {
    if (!cls || !className) {
        return;
    }
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (unsigned int i = 0; i < count; i++) {
        SEL sel = method_getName(methods[i]);
        NSString *name = NSStringFromSelector(sel);
        NSString *filtered = InsulationFilterMethodName(name);
        if (filtered) {
            [names addObject:filtered];
        }
    }
    free(methods);
    [names sortUsingSelector:@selector(compare:)];
    InsulationProbeRecordMethodDump(className, names);
}

static BOOL InsulationCaptureMitigationControllerIfChanged(id self);
static void InsulationApplyAfterMitigationControllerCapture(BOOL changed);

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
static id (*Orig_MitigationController_initForFastLoop_noDisplay_powerSaveParams_powerZoneParams)(id self, SEL _cmd, BOOL fastLoop, BOOL noDisplay, id powerSaveParams, id powerZoneParams);
static void (*Orig_MitigationController_updateCPU)(id self, SEL _cmd);
static void (*Orig_MitigationController_updateGPU)(id self, SEL _cmd);
static void (*Orig_MitigationController_updatePackage)(id self, SEL _cmd);
static void *InsulationLastObservedMitigationControllerPtr;
static CFAbsoluteTime InsulationLastMitigationUpdateReapplyTime;


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
    if (!cls || !selector || !replacement || !originalOut) {
        return NO;
    }
    Method method = class_getClassMethod(cls, selector);
    BOOL installed = NO;
    if (method) {
        *originalOut = method_getImplementation(method);
        method_setImplementation(method, replacement);
        installed = YES;
        INSULATION_LOG(@"insulation objc-port: hooked class method %@ on %@", NSStringFromSelector(selector), NSStringFromClass(cls));
    } else {
        INSULATION_LOG(@"insulation objc-port: missing class method %@ on %@", NSStringFromSelector(selector), NSStringFromClass(cls));
    }
    InsulationProbeRecordHookInstall(NSStringFromClass(cls), NSStringFromSelector(selector), installed);
    return installed;
}

static BOOL InsulationHookInstanceMethod(Class cls, SEL selector, IMP replacement, IMP *originalOut) {
    if (!cls || !selector || !replacement || !originalOut) {
        return NO;
    }
    Method method = class_getInstanceMethod(cls, selector);
    BOOL installed = NO;
    if (method) {
        *originalOut = method_getImplementation(method);
        method_setImplementation(method, replacement);
        installed = YES;
        INSULATION_LOG(@"insulation objc-port: hooked instance method %@ on %@", NSStringFromSelector(selector), NSStringFromClass(cls));
    } else {
        INSULATION_LOG(@"insulation objc-port: missing instance method %@ on %@", NSStringFromSelector(selector), NSStringFromClass(cls));
    }
    InsulationProbeRecordHookInstall(NSStringFromClass(cls), NSStringFromSelector(selector), installed);
    return installed;
}


static void InsulationRecordCommonProductBypass(NSString *source) {
    NSString *safeSource = ([source isKindOfClass:[NSString class]] && [source length] > 0) ? source : @"commonProduct";
    InsulationProbeEvent([@"commonProduct.bypass." stringByAppendingString:safeSource]);
}

static id Insulation_CommonProduct_initProduct(id self, SEL _cmd, id arg) {
    id result = Orig_CommonProduct_initProduct(self, _cmd, arg);
    InsulationSetCommonProductObject((CommonProduct *)self);
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
    if (bypass) {
        InsulationRecordCommonProductBypass(@"tryTakeAction");
    }
}

static void Insulation_CommonProduct_suppressWhenDimmingActive(id self, SEL _cmd, void (*original)(id, SEL), NSString *source) {
    BOOL bypass = InsulationThermalDimmingBypassActive();
    if (bypass) {
        InsulationRecordCommonProductBypass(source);
        return;
    }
    original(self, _cmd);
}

static void Insulation_CommonProduct_handleMCSThermalPressure(id self, SEL _cmd) {
    Insulation_CommonProduct_suppressWhenDimmingActive(self, _cmd, Orig_CommonProduct_handleMCSThermalPressure, @"handleMCSThermalPressure");
}

static void Insulation_CommonProduct_simulateLightThermalPressure(id self, SEL _cmd) {
    Insulation_CommonProduct_suppressWhenDimmingActive(self, _cmd, Orig_CommonProduct_simulateLightThermalPressure, @"simulateLightThermalPressure");
}

static void Insulation_CommonProduct_updatePowerzoneTelemetry(id self, SEL _cmd) {
    Insulation_CommonProduct_suppressWhenDimmingActive(self, _cmd, Orig_CommonProduct_updatePowerzoneTelemetry, @"updatePowerzoneTelemetry");
}

// HidSensors hook: block temperature events to prevent throttling


// MitigationController setter hooks: prevent double-swizzle by installing them here only,
// not in ThermalManagerDimmingPatch.m. Low-power mode writes setPowerSaveActive:/setCPULevel:
// directly and needs these hooks installed.


static void InsulationRecordMitigationSetter(id self, NSString *name, NSInteger originalValue, NSInteger patchedValue) {
    if (self) {
        InsulationSetMitigationControllerObject((MitigationController *)self);
    }
    InsulationProbeRecordSetter(name, originalValue, patchedValue);
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
    // Match the original Swift fullPower semantics: clear CPU low-power target
    // instead of replacing it with a high ceiling value.
    int patched = InsulationPowerMitigationsDisabled() ? 0 : InsulationLimitedCPUPower(power);
    InsulationRecordMitigationSetter(self, @"setCPULowPowerTarget", power, patched);
    Orig_MitigationController_setCPULowPowerTarget(self, _cmd, patched);
}

static void Insulation_MitigationController_setCPUPowerCeilingFromDecisionSource(id self, SEL _cmd, int power, int source) {
    int patched = InsulationPowerMitigationsDisabled() ? InsulationUnrestrictedPowerLimit() : InsulationLimitedCPUPower(power);
    InsulationSetMitigationControllerObject((MitigationController *)self);
    InsulationProbeRecordSetterDetails(@"setCPUPowerCeiling", power, patched, @{
        @"selector": @"setCPUPowerCeiling:fromDecisionSource:",
        @"source": @(source),
    });
    Orig_MitigationController_setCPUPowerCeilingFromDecisionSource(self, _cmd, patched, source);
}

static void Insulation_MitigationController_setCPUPowerCeilingForDVD1Contributor(id self, SEL _cmd, int power, int contributor) {
    int patched = InsulationPowerMitigationsDisabled() ? InsulationUnrestrictedPowerLimit() : InsulationLimitedCPUPower(power);
    InsulationRecordMitigationSetter(self, @"setCPUPowerCeilingForDVD1Contributor", power, patched);
    Orig_MitigationController_setCPUPowerCeilingForDVD1Contributor(self, _cmd, patched, contributor);
}

static void Insulation_MitigationController_setCPUPowerFloorFromDecisionSource(id self, SEL _cmd, int power, int source) {
    // Match original Swift semantics: CPU floor is cleared in fullPower.
    int patched = InsulationMitigationPowerFloor(power);
    InsulationRecordMitigationSetter(self, @"setCPUPowerFloor", power, patched);
    Orig_MitigationController_setCPUPowerFloorFromDecisionSource(self, _cmd, patched, source);
}

static void Insulation_MitigationController_setCPUPowerZoneTarget(id self, SEL _cmd, int power) {
    // Match original Swift semantics: fullPower blocks CPU zone target writes.
    if (InsulationPowerMitigationsDisabled()) {
        InsulationRecordMitigationSetter(self, @"setCPUPowerZoneTarget", power, 0);
        return;
    }
    int patched = InsulationLimitedCPUPower(power);
    InsulationRecordMitigationSetter(self, @"setCPUPowerZoneTarget", power, patched);
    Orig_MitigationController_setCPUPowerZoneTarget(self, _cmd, patched);
}

static void Insulation_MitigationController_setDVD1Level(id self, SEL _cmd, int level) {
    int patched = InsulationPowerMitigationsDisabled() ? 0 : level;
    InsulationRecordMitigationSetter(self, @"setDVD1Level", level, patched);
    Orig_MitigationController_setDVD1Level(self, _cmd, patched);
}

static void Insulation_MitigationController_setGPUPowerCeilingFromDecisionSource(id self, SEL _cmd, int power, int source) {
    int patched = InsulationPowerMitigationsDisabled() ? InsulationUnrestrictedPowerLimit() : power;
    InsulationSetMitigationControllerObject((MitigationController *)self);
    InsulationProbeRecordSetterDetails(@"setGPUPowerCeiling", power, patched, @{
        @"selector": @"setGPUPowerCeiling:fromDecisionSource:",
        @"source": @(source),
    });
    Orig_MitigationController_setGPUPowerCeilingFromDecisionSource(self, _cmd, patched, source);
}

static void Insulation_MitigationController_setGPUPowerFloorFromDecisionSource(id self, SEL _cmd, int power, int source) {
    int patched = InsulationPowerMitigationsDisabled() ? 0 : power;
    InsulationRecordMitigationSetter(self, @"setGPUPowerFloor", power, patched);
    Orig_MitigationController_setGPUPowerFloorFromDecisionSource(self, _cmd, patched, source);
}

static void Insulation_MitigationController_setGPUPowerZoneTarget(id self, SEL _cmd, int power) {
    // Match original Swift semantics: fullPower blocks GPU zone target writes.
    if (InsulationPowerMitigationsDisabled()) {
        InsulationRecordMitigationSetter(self, @"setGPUPowerZoneTarget", power, 0);
        return;
    }
    InsulationRecordMitigationSetter(self, @"setGPUPowerZoneTarget", power, power);
    Orig_MitigationController_setGPUPowerZoneTarget(self, _cmd, power);
}

static void Insulation_MitigationController_setSGXLevel(id self, SEL _cmd, int level) {
    int patched = InsulationPowerMitigationsDisabled() ? 0 : level;
    InsulationRecordMitigationSetter(self, @"setSGXLevel", level, patched);
    Orig_MitigationController_setSGXLevel(self, _cmd, patched);
}

static void Insulation_MitigationController_setMaxGraphicsDrivePowerTarget(id self, SEL _cmd, int power) {
    int patched = InsulationPowerMitigationsDisabled() ? InsulationUnrestrictedPowerLimit() : power;
    InsulationRecordMitigationSetter(self, @"setMaxGraphicsDrivePowerTarget", power, patched);
    Orig_MitigationController_setMaxGraphicsDrivePowerTarget(self, _cmd, patched);
}

static void Insulation_MitigationController_setMaxCPUPowerTarget_useLegacyPath_setProperty(id self, SEL _cmd, int power, BOOL useLegacyPath, id property) {
    int patched = InsulationPowerMitigationsDisabled() ? InsulationUnrestrictedPowerLimit() : power;
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
    int patched = InsulationPowerMitigationsDisabled() ? InsulationUnrestrictedPowerLimit() : power;
    InsulationSetMitigationControllerObject((MitigationController *)self);
    InsulationProbeRecordSetterDetails(@"setPackagePowerBudgetDirect", power, patched, @{
        @"selector": @"setPackagePowerBudgetDirect:withDetails:",
        @"details": @(details),
    });
    Orig_MitigationController_setPackagePowerBudgetDirect_withDetails(self, _cmd, patched, details);
}

static void Insulation_MitigationController_setPackagePowerCeilingFromDecisionSource(id self, SEL _cmd, int power, int source) {
    int patched = InsulationPowerMitigationsDisabled() ? InsulationUnrestrictedPowerLimit() : power;
    InsulationSetMitigationControllerObject((MitigationController *)self);
    InsulationProbeRecordSetterDetails(@"setPackagePowerCeiling", power, patched, @{
        @"selector": @"setPackagePowerCeiling:fromDecisionSource:",
        @"source": @(source),
    });
    Orig_MitigationController_setPackagePowerCeilingFromDecisionSource(self, _cmd, patched, source);
}

static void Insulation_MitigationController_setPackagePowerFloorFromDecisionSource(id self, SEL _cmd, int power, int source) {
    int patched = InsulationPowerMitigationsDisabled() ? InsulationUnrestrictedPowerLimit() : power;
    InsulationRecordMitigationSetter(self, @"setPackagePowerFloor", power, patched);
    Orig_MitigationController_setPackagePowerFloorFromDecisionSource(self, _cmd, patched, source);
}

static void Insulation_MitigationController_setMaxPackagePower(id self, SEL _cmd, int power) {
    int patched = InsulationPowerMitigationsDisabled() ? InsulationUnrestrictedPowerLimit() : power;
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

static id Insulation_MitigationController_initForFastLoop_noDisplay_powerSaveParams_powerZoneParams(id self, SEL _cmd, BOOL fastLoop, BOOL noDisplay, id powerSaveParams, id powerZoneParams) {
    id result = Orig_MitigationController_initForFastLoop_noDisplay_powerSaveParams_powerZoneParams ? ((id (*)(id, SEL, BOOL, BOOL, id, id))Orig_MitigationController_initForFastLoop_noDisplay_powerSaveParams_powerZoneParams)(self, _cmd, fastLoop, noDisplay, powerSaveParams, powerZoneParams) : self;
    BOOL changed = InsulationCaptureMitigationControllerIfChanged(self);
    InsulationProbeEvent(@"mitigation.initForFastLoop");
    InsulationApplyAfterMitigationControllerCapture(changed);
    return result;
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
    if (InsulationApplyInProgress()) {
        return;
    }

    if (changed) {
        // A new MitigationController usually appears during thermalmonitord startup/restart.
        // The daemon can continue applying late mitigation decisions after the first 0.5s,
        // so use a short bounded stabilization burst instead of a single delayed retry.
        InsulationProbeRecordSelfHeal(@"newObjectBurst");
        InsulationExecutePuppetEventWithSource(@"mitigation.newObjectBurst");
        NSArray<NSNumber *> *delays = @[@0.25, @0.75, @1.5, @3.0];
        for (NSNumber *delay in delays) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)([delay doubleValue] * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
                InsulationExecutePuppetEventWithSource(@"mitigation.newObjectBurstSoon");
            });
        }
        return;
    }

    if (!InsulationPowerMitigationsDisabled()) {
        return;
    }

    // Same-object update paths can still re-apply throttle decisions. Self-heal them,
    // but throttle the repair to avoid turning every thermal update into a burst.
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if ((now - InsulationLastMitigationUpdateReapplyTime) < 0.75) {
        return;
    }
    InsulationLastMitigationUpdateReapplyTime = now;
    InsulationProbeRecordSelfHeal(@"sameObjectDebounced");
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        InsulationExecutePuppetEventWithSource(@"mitigation.sameObjectDebounced");
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
    InsulationDumpClassMethods(mitigationClass, @"MitigationController");
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

static void InsulationInstallMitigationControllerUpdateHooks(void) {
    Class mitigationClass = objc_getClass("MitigationController");
    InsulationDumpClassMethods(mitigationClass, @"MitigationController.update");
    InsulationHookInstanceMethod(mitigationClass, @selector(initForFastLoop:noDisplay:powerSaveParams:powerZoneParams:), (IMP)Insulation_MitigationController_initForFastLoop_noDisplay_powerSaveParams_powerZoneParams, (IMP *)&Orig_MitigationController_initForFastLoop_noDisplay_powerSaveParams_powerZoneParams);
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
    });
}
