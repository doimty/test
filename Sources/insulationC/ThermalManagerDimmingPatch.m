#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "include/Tweak.h"
#import "../insulationObjC/InsulationDebug.h"
#include <string.h>

extern char ***_NSGetArgv(void);

static NSString *const InsulationPrefsPath = @"/var/mobile/Library/Preferences/com.be-huge.insulation-prefs.plist";
static NSString *const InsulationPreventDimmingKey = @"thermalPreventDimmingEnabled";
static NSString *const InsulationPowerModeKey = @"thermalPowerMode";
static const int InsulationUnrestrictedPowerTarget = 50000;

static BOOL insulationThermalPatchIsThermalmonitord(void) {
    char *argv0 = **_NSGetArgv();
    char *path = strrchr(argv0, '/');
    const char *name = path == NULL ? argv0 : path + 1;
    return strcmp(name, "thermalmonitord") == 0;
}

static BOOL insulationThermalPatchBoolPref(NSDictionary *prefs, NSString *key) {
    id value = [prefs objectForKey:key];
    if ([value isKindOfClass:[NSNumber class]]) {
        return [value boolValue];
    }
    if ([value isKindOfClass:[NSString class]]) {
        NSString *lower = [(NSString *)value lowercaseString];
        return [@[@"1", @"true", @"yes", @"on"] containsObject:lower];
    }
    return NO;
}

static NSTimeInterval cachedPrefsTime = -1.0;
static BOOL cachedPreventDimmingEnabled = NO;
static BOOL cachedFullPowerEnabled = NO;

static void insulationThermalPatchRefreshPrefsIfNeeded(void) {
    static dispatch_queue_t prefsCacheQueue = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        prefsCacheQueue = dispatch_queue_create("com.be-huge.insulation.prefs-cache", DISPATCH_QUEUE_SERIAL);
    });
    
    __block BOOL shouldRefresh = NO;
    dispatch_sync(prefsCacheQueue, ^{
        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
        if (cachedPrefsTime < 0 || now - cachedPrefsTime >= 0.05) {
            shouldRefresh = YES;
        }
    });
    
    if (!shouldRefresh) return;
    
    dispatch_sync(prefsCacheQueue, ^{
        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
        NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:InsulationPrefsPath];
        cachedPreventDimmingEnabled = insulationThermalPatchBoolPref(prefs, InsulationPreventDimmingKey);
        id mode = [prefs objectForKey:InsulationPowerModeKey];
        BOOL modeIsFullPower = [mode isKindOfClass:[NSString class]] && [mode isEqualToString:@"fullPower"];
        cachedFullPowerEnabled = modeIsFullPower;
        cachedPrefsTime = now;
    });
}

static BOOL insulationThermalPatchPreventDimmingEnabled(void) {
    insulationThermalPatchRefreshPrefsIfNeeded();
    return cachedPreventDimmingEnabled;
}

static BOOL insulationThermalPatchFullPowerEnabled(void) {
    insulationThermalPatchRefreshPrefsIfNeeded();
    return cachedFullPowerEnabled;
}

static BOOL insulationThermalPatchAggressiveFullPowerEnabled(void) {
    return insulationThermalPatchFullPowerEnabled() && !insulationFullPowerBootGuardActive();
}

static BOOL insulationThermalPatchDimmingBypassActive(void) {
    return insulationThermalPatchPreventDimmingEnabled() || insulationThermalPatchFullPowerEnabled();
}

static BOOL insulationThermalPatchShouldSuppressThermalPressure(void) {
    return insulationThermalPatchDimmingBypassActive();
}

// 满血：完全旁路（归零）。防暗屏：只封顶到 light，不归零，避免卡住 thermalmonitord watchdog checkin。
static const int64_t InsulationDimmingPressureCeiling = 1;

static int64_t insulationThermalPatchCapPressureLevel(int64_t level) {
    if (insulationThermalPatchAggressiveFullPowerEnabled()) {
        return 0;
    }
    if (insulationThermalPatchDimmingBypassActive()) {
        return level < InsulationDimmingPressureCeiling ? level : InsulationDimmingPressureCeiling;
    }
    return level;
}

// watchdog 只有满血才关；防暗屏保留原生过热看门狗。
static BOOL insulationThermalPatchShouldDisableWatchdog(void) {
    return insulationThermalPatchAggressiveFullPowerEnabled();
}

static BOOL insulationThermalPatchStringContainsAny(NSString *lower, NSArray<NSString *> *needles) {
    for (NSString *needle in needles) {
        if ([lower containsString:needle]) {
            return YES;
        }
    }
    return NO;
}

static NSNumber *insulationThermalPatchIntValue(id value) {
    if ([value isKindOfClass:[NSNumber class]]) {
        return value;
    }
    if ([value isKindOfClass:[NSString class]]) {
        NSString *trimmed = [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([trimmed length] == 0) {
            return nil;
        }
        NSScanner *scanner = [NSScanner scannerWithString:trimmed];
        NSInteger parsed = 0;
        if (![scanner scanInteger:&parsed] || ![scanner isAtEnd]) {
            return nil;
        }
        return @(parsed);
    }
    return nil;
}

static id insulationThermalPatchReplaceNumericObject(id value, NSInteger replacement) {
    if ([value isKindOfClass:[NSNumber class]]) {
        return @(replacement);
    }
    if ([value isKindOfClass:[NSString class]] && insulationThermalPatchIntValue(value)) {
        return [@(replacement) stringValue];
    }
    if ([value isKindOfClass:[NSArray class]]) {
        NSMutableArray *patched = [(NSArray *)value mutableCopy];
        BOOL changed = NO;
        for (NSUInteger i = 0; i < [patched count]; i++) {
            id item = patched[i];
            if ([item isKindOfClass:[NSNumber class]]) {
                patched[i] = @(replacement);
                changed = YES;
            } else if ([item isKindOfClass:[NSString class]] && insulationThermalPatchIntValue(item)) {
                patched[i] = [@(replacement) stringValue];
                changed = YES;
            }
        }
        return changed ? patched : nil;
    }
    return nil;
}

static id insulationThermalPatchRaisePowerObject(id value) {
    NSInteger target = InsulationUnrestrictedPowerTarget;
    NSNumber *number = insulationThermalPatchIntValue(value);
    if (number) {
        NSInteger raised = MAX([number integerValue], target);
        return [value isKindOfClass:[NSString class]] ? [@(raised) stringValue] : @(raised);
    }
    if ([value isKindOfClass:[NSArray class]]) {
        NSMutableArray *patched = [(NSArray *)value mutableCopy];
        BOOL changed = NO;
        for (NSUInteger i = 0; i < [patched count]; i++) {
            id item = patched[i];
            NSNumber *itemNumber = insulationThermalPatchIntValue(item);
            if (!itemNumber) {
                continue;
            }
            NSInteger raised = MAX([itemNumber integerValue], target);
            patched[i] = [item isKindOfClass:[NSString class]] ? [@(raised) stringValue] : @(raised);
            changed = YES;
        }
        return changed ? patched : nil;
    }
    return nil;
}

static id insulationThermalPatchPatchFullPowerConfigValue(NSString *keyHint, id value) {
    if (![keyHint isKindOfClass:[NSString class]]) {
        return value;
    }

    NSString *lower = [keyHint lowercaseString];
    if (insulationThermalPatchStringContainsAny(lower, @[@"mitigation", @"contextualclamp", @"clamp", @"thermalpressure", @"forcedthermal", @"powersave", @"lowpower", @"throttle", @"cpms"])) {
        id zeroed = insulationThermalPatchReplaceNumericObject(value, 0);
        return zeroed ?: value;
    }

    BOOL isPowerKey = [lower containsString:@"power"] || [lower containsString:@"dvd1"] || [lower containsString:@"sgx"];
    BOOL isPowerTarget = insulationThermalPatchStringContainsAny(lower, @[@"target", @"ceiling", @"floor", @"budget", @"limit", @"max", @"thermalpower", @"powerzone"]);
    if (isPowerKey && isPowerTarget && ![lower containsString:@"powersave"] && ![lower containsString:@"lowpower"]) {
        id raised = insulationThermalPatchRaisePowerObject(value);
        return raised ?: value;
    }

    return value;
}

static id insulationThermalPatchPatchFullPowerConfigObject(id object, NSString *keyHint) {
    if ([object isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *mutable = [object mutableCopy];
        for (id key in [[mutable allKeys] copy]) {
            NSString *childKey = [key isKindOfClass:[NSString class]] ? key : nil;
            id patched = insulationThermalPatchPatchFullPowerConfigObject(mutable[key], childKey);
            patched = insulationThermalPatchPatchFullPowerConfigValue(childKey, patched);
            mutable[key] = patched ?: [NSNull null];
        }
        return mutable;
    }
    if ([object isKindOfClass:[NSArray class]]) {
        NSMutableArray *mutable = [object mutableCopy];
        for (NSUInteger i = 0; i < [mutable count]; i++) {
            id patched = insulationThermalPatchPatchFullPowerConfigObject(mutable[i], keyHint);
            [mutable replaceObjectAtIndex:i withObject:patched ?: [NSNull null]];
        }
        return insulationThermalPatchPatchFullPowerConfigValue(keyHint, mutable);
    }
    return insulationThermalPatchPatchFullPowerConfigValue(keyHint, object);
}

/* ── ThermalManager ─────────────────────────────────── */

static IMP orig_ThermalManager_getConfigurationFor = NULL;

static void *hook_ThermalManager_getConfigurationFor(id self, SEL _cmd, void *configName) {
    void *result = NULL;
    if (orig_ThermalManager_getConfigurationFor) {
        result = ((void *(*)(id, SEL, void *))orig_ThermalManager_getConfigurationFor)(self, _cmd, configName);
    }

    BOOL displayDimmingBypass = insulationThermalPatchDimmingBypassActive();
    BOOL fullPower = insulationThermalPatchAggressiveFullPowerEnabled();
    if (!result || (!displayDimmingBypass && !fullPower)) {
        return result;
    }

    @try {
        CFTypeRef resultType = (CFTypeRef)result;
        if (CFGetTypeID(resultType) != CFDictionaryGetTypeID()) {
            return result;
        }

        CFDictionaryRef originalDict = (CFDictionaryRef)result;
        if (CFDictionaryGetCount(originalDict) == 0) {
            return result;
        }

        NSDictionary *bridged = (__bridge NSDictionary *)originalDict;
        NSMutableDictionary *modified = [bridged mutableCopy];
        if (!modified) {
            return result;
        }

        if (fullPower) {
            id recursivelyPatched = insulationThermalPatchPatchFullPowerConfigObject(modified, nil);
            if ([recursivelyPatched isKindOfClass:[NSDictionary class]]) {
                modified = [recursivelyPatched mutableCopy];
            }
        }

        if (displayDimmingBypass) {
            modified[@"needsPushingTSFDtoDisplayDriver"] = @NO;
            modified[@"displayBrightnessMitigation"] = @NO;
            modified[@"displayMitigation"] = @NO;
        }

        if (fullPower) {
            modified[@"needsContextualClamp"] = @NO;
            modified[@"shouldEnforceLightThermalPressure"] = @NO;
            modified[@"shouldEnforceThermalPressure"] = @NO;
            modified[@"thermalPressureMitigation"] = @NO;
            modified[@"forcedThermalLevel"] = @0;
            modified[@"performanceMitigation"] = @NO;
            modified[@"CPMSMitigationState"] = @NO;
            modified[@"CPMSMitigationLevel"] = @0;
            modified[@"maxPower"] = @(InsulationUnrestrictedPowerTarget);
            modified[@"packagePowerTarget"] = @(InsulationUnrestrictedPowerTarget);
        }

        // Return a new copy each time instead of caching
        // This prevents dangling pointer issues when the caller holds the reference
        CFDictionaryRef newConfig = CFDictionaryCreateCopy(kCFAllocatorDefault, (__bridge CFDictionaryRef)modified);
        if (!newConfig) {
            return result;
        }

        // Caller is responsible for managing the lifetime
        // In practice, thermalmonitord uses ARC or similar memory management
        // that will handle the CFDictionaryRef properly
        return (void *)newConfig;
    } @catch (NSException *exception) {
        INSULATION_LOG(@"insulation thermal manager dim patch exception: %@", exception);
        return result;
    }
}

static IMP orig_ThermalManager_getThermalSuggestion = NULL;
static id hook_ThermalManager_getThermalSuggestion(id self, SEL _cmd, id config) {
    if (insulationThermalPatchShouldSuppressThermalPressure()) return nil;
    if (!orig_ThermalManager_getThermalSuggestion) return nil;
    return ((id (*)(id, SEL, id))orig_ThermalManager_getThermalSuggestion)(self, _cmd, config);
}

static IMP orig_ThermalManager_thermalSuggestion = NULL;
static id hook_ThermalManager_thermalSuggestion(id self, SEL _cmd, id arg) {
    if (insulationThermalPatchShouldSuppressThermalPressure()) return nil;
    if (!orig_ThermalManager_thermalSuggestion) return nil;
    return ((id (*)(id, SEL, id))orig_ThermalManager_thermalSuggestion)(self, _cmd, arg);
}

static IMP orig_ThermalManager_thermalMitigation = NULL;
static id hook_ThermalManager_thermalMitigation(id self, SEL _cmd, id arg) {
    if (insulationThermalPatchShouldSuppressThermalPressure()) return nil;
    if (!orig_ThermalManager_thermalMitigation) return nil;
    return ((id (*)(id, SEL, id))orig_ThermalManager_thermalMitigation)(self, _cmd, arg);
}

static IMP orig_ThermalManager_thermalPressure = NULL;
static id hook_ThermalManager_thermalPressure(id self, SEL _cmd, id arg) {
    if (insulationThermalPatchAggressiveFullPowerEnabled()) return @0;
    if (!orig_ThermalManager_thermalPressure) return @0;
    id real = ((id (*)(id, SEL, id))orig_ThermalManager_thermalPressure)(self, _cmd, arg);
    if (insulationThermalPatchDimmingBypassActive() && [real isKindOfClass:[NSNumber class]]) {
        int64_t capped = insulationThermalPatchCapPressureLevel([real longLongValue]);
        return @(capped);
    }
    return real;
}

/* ── CommonProduct ─────────────────────────────────── */

static IMP orig_CommonProduct_thermalPressureLevel = NULL;
static int64_t hook_CommonProduct_thermalPressureLevel(id self, SEL _cmd) {
    if (insulationThermalPatchAggressiveFullPowerEnabled()) return 0;
    if (!orig_CommonProduct_thermalPressureLevel) return 0;
    int64_t real = ((int64_t (*)(id, SEL))orig_CommonProduct_thermalPressureLevel)(self, _cmd);
    return insulationThermalPatchCapPressureLevel(real);
}

static IMP orig_CommonProduct_setThermalState = NULL;
static void hook_CommonProduct_setThermalState(id self, SEL _cmd, int state) {
    if (!orig_CommonProduct_setThermalState) return;
    int patched = state;
    if (insulationThermalPatchAggressiveFullPowerEnabled()) {
        if (state != 0) return;
    } else if (insulationThermalPatchDimmingBypassActive()) {
        patched = (int)insulationThermalPatchCapPressureLevel(state);
    }
    ((void (*)(id, SEL, int))orig_CommonProduct_setThermalState)(self, _cmd, patched);
}

static IMP orig_CommonProduct_getPotentialForcedThermalPressureLevel = NULL;
static BOOL hook_CommonProduct_getPotentialForcedThermalPressureLevel(id self, SEL _cmd) {
    if (insulationThermalPatchShouldSuppressThermalPressure()) return NO;
    if (!orig_CommonProduct_getPotentialForcedThermalPressureLevel) return NO;
    return ((BOOL (*)(id, SEL))orig_CommonProduct_getPotentialForcedThermalPressureLevel)(self, _cmd);
}

static IMP orig_CommonProduct_getPotentialForcedThermalLevel = NULL;
static id hook_CommonProduct_getPotentialForcedThermalLevel(id self, SEL _cmd, id arg) {
    if (insulationThermalPatchShouldSuppressThermalPressure()) return nil;
    if (!orig_CommonProduct_getPotentialForcedThermalLevel) return nil;
    return ((id (*)(id, SEL, id))orig_CommonProduct_getPotentialForcedThermalLevel)(self, _cmd, arg);
}

static IMP orig_CommonProduct_thermalUpdatesToWatchdogEnabled = NULL;
static void hook_CommonProduct_thermalUpdatesToWatchdogEnabled(id self, SEL _cmd, id enabled) {
    if (!orig_CommonProduct_thermalUpdatesToWatchdogEnabled) return;
    id patched = insulationThermalPatchShouldDisableWatchdog() ? @NO : enabled;
    ((void (*)(id, SEL, id))orig_CommonProduct_thermalUpdatesToWatchdogEnabled)(self, _cmd, patched);
}

/* ── PackagePowerCC ────────────────────────────────── */

static IMP orig_PackagePowerCC_initWithParams = NULL;
static id hook_PackagePowerCC_initWithParams(id self, SEL _cmd, id params) {
    id patchedParams = params;
    if (insulationThermalPatchAggressiveFullPowerEnabled() && [params isKindOfClass:[NSDictionary class]]) {
        patchedParams = insulationThermalPatchPatchFullPowerConfigObject(params, nil);
    }
    if (!orig_PackagePowerCC_initWithParams) return self;
    return ((id (*)(id, SEL, id))orig_PackagePowerCC_initWithParams)(self, _cmd, patchedParams);
}

/* ── MitigationController ──────────────────────────── */

static IMP orig_MitigationController_DVD1Level = NULL;
static int hook_MitigationController_DVD1Level(id self, SEL _cmd) {
    if (insulationThermalPatchAggressiveFullPowerEnabled()) return 0;
    if (!orig_MitigationController_DVD1Level) return 0;
    return ((int (*)(id, SEL))orig_MitigationController_DVD1Level)(self, _cmd);
}

static IMP orig_MitigationController_SGXLevel = NULL;
static int hook_MitigationController_SGXLevel(id self, SEL _cmd) {
    if (insulationThermalPatchAggressiveFullPowerEnabled()) return 0;
    if (!orig_MitigationController_SGXLevel) return 0;
    return ((int (*)(id, SEL))orig_MitigationController_SGXLevel)(self, _cmd);
}

static IMP orig_MitigationController_getPackagePowerZoneMetric = NULL;
static int hook_MitigationController_getPackagePowerZoneMetric(id self, SEL _cmd) {
    if (insulationThermalPatchAggressiveFullPowerEnabled()) return 0;
    if (!orig_MitigationController_getPackagePowerZoneMetric) return 0;
    return ((int (*)(id, SEL))orig_MitigationController_getPackagePowerZoneMetric)(self, _cmd);
}

static IMP orig_MitigationController_getGPUTargetPower = NULL;
static int hook_MitigationController_getGPUTargetPower(id self, SEL _cmd) {
    if (insulationThermalPatchAggressiveFullPowerEnabled()) return InsulationUnrestrictedPowerTarget;
    if (!orig_MitigationController_getGPUTargetPower) return 0;
    return ((int (*)(id, SEL))orig_MitigationController_getGPUTargetPower)(self, _cmd);
}

static IMP orig_MitigationController_getPackageGPUPowerTarget = NULL;
static int hook_MitigationController_getPackageGPUPowerTarget(id self, SEL _cmd) {
    if (insulationThermalPatchAggressiveFullPowerEnabled()) return InsulationUnrestrictedPowerTarget;
    if (!orig_MitigationController_getPackageGPUPowerTarget) return 0;
    return ((int (*)(id, SEL))orig_MitigationController_getPackageGPUPowerTarget)(self, _cmd);
}

/* ── Installation ──────────────────────────────────── */

static void insulationInstallThermalManagerPatch(void) {
    Class commonProduct = objc_getClass("CommonProduct");
    if (commonProduct) {
        Method m = class_getInstanceMethod(commonProduct, @selector(thermalPressureLevel));
        if (m) { orig_CommonProduct_thermalPressureLevel = method_getImplementation(m);
            method_setImplementation(m, (IMP)hook_CommonProduct_thermalPressureLevel); }

        m = class_getInstanceMethod(commonProduct, @selector(setThermalState:));
        if (m) { orig_CommonProduct_setThermalState = method_getImplementation(m);
            method_setImplementation(m, (IMP)hook_CommonProduct_setThermalState); }

        m = class_getInstanceMethod(commonProduct, @selector(getPotentialForcedThermalPressureLevel));
        if (m) { orig_CommonProduct_getPotentialForcedThermalPressureLevel = method_getImplementation(m);
            method_setImplementation(m, (IMP)hook_CommonProduct_getPotentialForcedThermalPressureLevel); }

        m = class_getInstanceMethod(commonProduct, @selector(getPotentialForcedThermalLevel:));
        if (m) { orig_CommonProduct_getPotentialForcedThermalLevel = method_getImplementation(m);
            method_setImplementation(m, (IMP)hook_CommonProduct_getPotentialForcedThermalLevel); }

        m = class_getInstanceMethod(commonProduct, @selector(thermalUpdatesToWatchdogEnabled:));
        if (m) { orig_CommonProduct_thermalUpdatesToWatchdogEnabled = method_getImplementation(m);
            method_setImplementation(m, (IMP)hook_CommonProduct_thermalUpdatesToWatchdogEnabled); }
    }

    Class thermalManager = objc_getClass("ThermalManager");
    if (thermalManager) {
        Method m = class_getInstanceMethod(thermalManager, @selector(getConfigurationFor:));
        if (m) { orig_ThermalManager_getConfigurationFor = method_getImplementation(m);
            method_setImplementation(m, (IMP)hook_ThermalManager_getConfigurationFor); }

        m = class_getInstanceMethod(thermalManager, @selector(getThermalSuggestion:));
        if (m) { orig_ThermalManager_getThermalSuggestion = method_getImplementation(m);
            method_setImplementation(m, (IMP)hook_ThermalManager_getThermalSuggestion); }

        m = class_getInstanceMethod(thermalManager, @selector(thermalSuggestion:));
        if (m) { orig_ThermalManager_thermalSuggestion = method_getImplementation(m);
            method_setImplementation(m, (IMP)hook_ThermalManager_thermalSuggestion); }

        m = class_getInstanceMethod(thermalManager, @selector(thermalMitigation:));
        if (m) { orig_ThermalManager_thermalMitigation = method_getImplementation(m);
            method_setImplementation(m, (IMP)hook_ThermalManager_thermalMitigation); }

        m = class_getInstanceMethod(thermalManager, @selector(thermalPressure:));
        if (m) { orig_ThermalManager_thermalPressure = method_getImplementation(m);
            method_setImplementation(m, (IMP)hook_ThermalManager_thermalPressure); }
    }

    Class packagePowerCC = objc_getClass("PackagePowerCC");
    if (packagePowerCC) {
        Method m = class_getInstanceMethod(packagePowerCC, @selector(initWithParams:));
        if (m) { orig_PackagePowerCC_initWithParams = method_getImplementation(m);
            method_setImplementation(m, (IMP)hook_PackagePowerCC_initWithParams); }
    }

    Class mitigationController = objc_getClass("MitigationController");
    if (mitigationController) {
        Method m = class_getInstanceMethod(mitigationController, @selector(DVD1Level));
        if (m) { orig_MitigationController_DVD1Level = method_getImplementation(m);
            method_setImplementation(m, (IMP)hook_MitigationController_DVD1Level); }

        m = class_getInstanceMethod(mitigationController, @selector(SGXLevel));
        if (m) { orig_MitigationController_SGXLevel = method_getImplementation(m);
            method_setImplementation(m, (IMP)hook_MitigationController_SGXLevel); }

        m = class_getInstanceMethod(mitigationController, @selector(getPackagePowerZoneMetric));
        if (m) { orig_MitigationController_getPackagePowerZoneMetric = method_getImplementation(m);
            method_setImplementation(m, (IMP)hook_MitigationController_getPackagePowerZoneMetric); }

        m = class_getInstanceMethod(mitigationController, @selector(getGPUTargetPower));
        if (m) { orig_MitigationController_getGPUTargetPower = method_getImplementation(m);
            method_setImplementation(m, (IMP)hook_MitigationController_getGPUTargetPower); }

        m = class_getInstanceMethod(mitigationController, @selector(getPackageGPUPowerTarget));
        if (m) { orig_MitigationController_getPackageGPUPowerTarget = method_getImplementation(m);
            method_setImplementation(m, (IMP)hook_MitigationController_getPackageGPUPowerTarget); }

        // Disable MitigationController setter hooks here to prevent double-swizzle.
        // RuntimeHooks.m now owns all setter hooks (setPowerSaveActive:, setCPMSMitigationsEnabled:, setCPULevel:, etc.).
        // Only getter hooks (getGPUTargetPower, getPackageGPUPowerTarget, etc.) remain active here.
    }
}

__attribute__((constructor))
static void insulationThermalManagerPatchEntry(void) {
    if (!insulationThermalPatchIsThermalmonitord()) return;
    insulationMarkProcessStart();
    insulationInstallThermalManagerPatch();
}
