#import "InsulationDebug.h"
#import "InsulationRuntimeHooks.h"

#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <objc/runtime.h>

#import "InsulationDictHelper.h"
#import "InsulationPowerHelper.h"
#import "../insulationC/include/Tweak.h"

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
static void (*Orig_MitigationController_setPackagePowerCeilingFromDecisionSource)(id self, SEL _cmd, int power, int source);
static void (*Orig_MitigationController_setPackagePowerFloorFromDecisionSource)(id self, SEL _cmd, int power, int source);
static void (*Orig_MitigationController_setMaxPackagePower)(id self, SEL _cmd, int power);
static void (*Orig_MitigationController_setPackageLowPowerTarget)(id self, SEL _cmd);
static void (*Orig_MitigationController_setPackagePowerZoneTarget)(id self, SEL _cmd);
static void (*Orig_MitigationController_updateCPU)(id self, SEL _cmd);
static void (*Orig_MitigationController_updateGPU)(id self, SEL _cmd);
static void (*Orig_MitigationController_updatePackage)(id self, SEL _cmd);
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
    if (!cls || !selector || !replacement || !originalOut) {
        return NO;
    }
    Method method = class_getClassMethod(cls, selector);
    if (!method) {
        INSULATION_LOG(@"insulation objc-port: missing class method %@ on %@", NSStringFromSelector(selector), NSStringFromClass(cls));
        return NO;
    }
    *originalOut = method_getImplementation(method);
    method_setImplementation(method, replacement);
    INSULATION_LOG(@"insulation objc-port: hooked class method %@ on %@", NSStringFromSelector(selector), NSStringFromClass(cls));
    return YES;
}

static BOOL InsulationHookInstanceMethod(Class cls, SEL selector, IMP replacement, IMP *originalOut) {
    if (!cls || !selector || !replacement || !originalOut) {
        return NO;
    }
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) {
        INSULATION_LOG(@"insulation objc-port: missing instance method %@ on %@", NSStringFromSelector(selector), NSStringFromClass(cls));
        return NO;
    }
    *originalOut = method_getImplementation(method);
    method_setImplementation(method, replacement);
    INSULATION_LOG(@"insulation objc-port: hooked instance method %@ on %@", NSStringFromSelector(selector), NSStringFromClass(cls));
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

static void Insulation_MitigationController_setPowerSaveActive(id self, SEL _cmd, BOOL active) {
    if (InsulationPowerMitigationsDisabled() || InsulationCPURestoreActive()) {
        Orig_MitigationController_setPowerSaveActive(self, _cmd, NO);
        return;
    }
    if (InsulationCPULimitEnabled()) {
        Orig_MitigationController_setPowerSaveActive(self, _cmd, YES);
        return;
    }
    Orig_MitigationController_setPowerSaveActive(self, _cmd, active);
}

static void Insulation_MitigationController_setCPMSMitigationsEnabled(id self, SEL _cmd, BOOL enabled) {
    BOOL patched = InsulationPowerMitigationsDisabled() ? NO : enabled;
    Orig_MitigationController_setCPMSMitigationsEnabled(self, _cmd, patched);
}

static void Insulation_MitigationController_setCPULevel(id self, SEL _cmd, int level) {
    BOOL disabled = InsulationPowerMitigationsDisabled();
    int patched = disabled ? 0 : InsulationLimitedCPULevel(level);
    Orig_MitigationController_setCPULevel(self, _cmd, patched);
}

static void Insulation_MitigationController_setCPULowPowerTarget(id self, SEL _cmd, int power) {
    int patched = InsulationPowerMitigationsDisabled() ? InsulationUnrestrictedPowerLimit() : InsulationLimitedCPUPower(power);
    Orig_MitigationController_setCPULowPowerTarget(self, _cmd, patched);
}

static void Insulation_MitigationController_setCPUPowerCeilingFromDecisionSource(id self, SEL _cmd, int power, int source) {
    int patched = InsulationPowerMitigationsDisabled() ? InsulationUnrestrictedPowerLimit() : InsulationLimitedCPUPower(power);
    Orig_MitigationController_setCPUPowerCeilingFromDecisionSource(self, _cmd, patched, source);
}

static void Insulation_MitigationController_setCPUPowerCeilingForDVD1Contributor(id self, SEL _cmd, int power, int contributor) {
    int patched = InsulationPowerMitigationsDisabled() ? InsulationUnrestrictedPowerLimit() : InsulationLimitedCPUPower(power);
    Orig_MitigationController_setCPUPowerCeilingForDVD1Contributor(self, _cmd, patched, contributor);
}

static void Insulation_MitigationController_setCPUPowerFloorFromDecisionSource(id self, SEL _cmd, int power, int source) {
    int patched = InsulationPowerMitigationsDisabled() ? InsulationUnrestrictedPowerLimit() : InsulationMitigationPowerFloor(power);
    Orig_MitigationController_setCPUPowerFloorFromDecisionSource(self, _cmd, patched, source);
}

static void Insulation_MitigationController_setCPUPowerZoneTarget(id self, SEL _cmd, int power) {
    int patched = InsulationPowerMitigationsDisabled() ? InsulationUnrestrictedPowerLimit() : InsulationLimitedCPUPower(power);
    Orig_MitigationController_setCPUPowerZoneTarget(self, _cmd, patched);
}

static void Insulation_MitigationController_setDVD1Level(id self, SEL _cmd, int level) {
    int patched = InsulationPowerMitigationsDisabled() ? 0 : level;
    Orig_MitigationController_setDVD1Level(self, _cmd, patched);
}

static void Insulation_MitigationController_setGPUPowerCeilingFromDecisionSource(id self, SEL _cmd, int power, int source) {
    int patched = InsulationPowerMitigationsDisabled() ? InsulationUnrestrictedPowerLimit() : power;
    Orig_MitigationController_setGPUPowerCeilingFromDecisionSource(self, _cmd, patched, source);
}

static void Insulation_MitigationController_setGPUPowerFloorFromDecisionSource(id self, SEL _cmd, int power, int source) {
    int patched = InsulationPowerMitigationsDisabled() ? 0 : power;
    Orig_MitigationController_setGPUPowerFloorFromDecisionSource(self, _cmd, patched, source);
}

static void Insulation_MitigationController_setGPUPowerZoneTarget(id self, SEL _cmd, int power) {
    if (InsulationPowerMitigationsDisabled()) {
        return;
    }
    Orig_MitigationController_setGPUPowerZoneTarget(self, _cmd, power);
}

static void Insulation_MitigationController_setSGXLevel(id self, SEL _cmd, int level) {
    int patched = InsulationPowerMitigationsDisabled() ? 0 : level;
    Orig_MitigationController_setSGXLevel(self, _cmd, patched);
}

static void Insulation_MitigationController_setMaxGraphicsDrivePowerTarget(id self, SEL _cmd, int power) {
    int patched = InsulationPowerMitigationsDisabled() ? InsulationUnrestrictedPowerLimit() : power;
    Orig_MitigationController_setMaxGraphicsDrivePowerTarget(self, _cmd, patched);
}

static void Insulation_MitigationController_setPackagePowerCeilingFromDecisionSource(id self, SEL _cmd, int power, int source) {
    int patched = InsulationPowerMitigationsDisabled() ? InsulationUnrestrictedPowerLimit() : power;
    Orig_MitigationController_setPackagePowerCeilingFromDecisionSource(self, _cmd, patched, source);
}

static void Insulation_MitigationController_setPackagePowerFloorFromDecisionSource(id self, SEL _cmd, int power, int source) {
    int patched = InsulationPowerMitigationsDisabled() ? InsulationUnrestrictedPowerLimit() : power;
    Orig_MitigationController_setPackagePowerFloorFromDecisionSource(self, _cmd, patched, source);
}

static void Insulation_MitigationController_setMaxPackagePower(id self, SEL _cmd, int power) {
    int patched = InsulationPowerMitigationsDisabled() ? InsulationUnrestrictedPowerLimit() : power;
    Orig_MitigationController_setMaxPackagePower(self, _cmd, patched);
}

static void Insulation_MitigationController_setPackageLowPowerTarget(id self, SEL _cmd) {
    if (InsulationPowerMitigationsDisabled()) {
        return;
    }
    Orig_MitigationController_setPackageLowPowerTarget(self, _cmd);
}

static void Insulation_MitigationController_setPackagePowerZoneTarget(id self, SEL _cmd) {
    if (InsulationPowerMitigationsDisabled()) {
        return;
    }
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
    // Immediate apply + single delayed retry at 0.5s (reduced from 5 applications to 2)
    InsulationExecutePuppetEvent();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        InsulationExecutePuppetEvent();
    });
}

static void Insulation_MitigationController_updateCPU(id self, SEL _cmd) {
    BOOL changed = InsulationCaptureMitigationControllerIfChanged(self);
    Orig_MitigationController_updateCPU(self, _cmd);
    InsulationApplyAfterMitigationControllerCapture(changed);
}

static void Insulation_MitigationController_updateGPU(id self, SEL _cmd) {
    BOOL changed = InsulationCaptureMitigationControllerIfChanged(self);
    Orig_MitigationController_updateGPU(self, _cmd);
    InsulationApplyAfterMitigationControllerCapture(changed);
}

static void Insulation_MitigationController_updatePackage(id self, SEL _cmd) {
    BOOL changed = InsulationCaptureMitigationControllerIfChanged(self);
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
    InsulationHookInstanceMethod(mitigationClass, @selector(setPackagePowerCeiling:fromDecisionSource:), (IMP)Insulation_MitigationController_setPackagePowerCeilingFromDecisionSource, (IMP *)&Orig_MitigationController_setPackagePowerCeilingFromDecisionSource);
    InsulationHookInstanceMethod(mitigationClass, @selector(setPackagePowerFloor:fromDecisionSource:), (IMP)Insulation_MitigationController_setPackagePowerFloorFromDecisionSource, (IMP *)&Orig_MitigationController_setPackagePowerFloorFromDecisionSource);
    InsulationHookInstanceMethod(mitigationClass, @selector(setMaxPackagePower:), (IMP)Insulation_MitigationController_setMaxPackagePower, (IMP *)&Orig_MitigationController_setMaxPackagePower);
    InsulationHookInstanceMethod(mitigationClass, @selector(setPackageLowPowerTarget), (IMP)Insulation_MitigationController_setPackageLowPowerTarget, (IMP *)&Orig_MitigationController_setPackageLowPowerTarget);
    InsulationHookInstanceMethod(mitigationClass, @selector(setPackagePowerZoneTarget), (IMP)Insulation_MitigationController_setPackagePowerZoneTarget, (IMP *)&Orig_MitigationController_setPackagePowerZoneTarget);
}

static void InsulationInstallMitigationControllerUpdateHooks(void) {
    Class mitigationClass = objc_getClass("MitigationController");
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
