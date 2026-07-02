#import "InsulationDebug.h"
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <dispatch/dispatch.h>
#include <dlfcn.h>
#include <notify.h>

__attribute__((weak_import)) extern const char *const kOSThermalNotificationPressureLevelName;

typedef SCPreferencesRef (*InsulationSCPreferencesCreateFn)(CFAllocatorRef allocator, CFStringRef name, CFStringRef prefsID);
typedef Boolean (*InsulationSCPreferencesCommitChangesFn)(SCPreferencesRef prefs);
typedef Boolean (*InsulationSCPreferencesApplyChangesFn)(SCPreferencesRef prefs);
typedef Boolean (*InsulationSCPreferencesRemoveValueFn)(SCPreferencesRef prefs, CFStringRef key);
typedef int (*InsulationSCErrorFn)(void);

static void *InsulationResetSCSymbol(const char *name) {
    return dlsym(RTLD_DEFAULT, name);
}

static SCPreferencesRef InsulationResetThermalPrefs(void) {
    InsulationSCPreferencesCreateFn create = (InsulationSCPreferencesCreateFn)InsulationResetSCSymbol("SCPreferencesCreate");
    if (create == NULL) {
        return NULL;
    }
    return create(kCFAllocatorDefault, CFSTR("insulation-reset-native"), CFSTR("OSThermalStatus.plist"));
}

static int InsulationResetSCError(void) {
    InsulationSCErrorFn errorFn = (InsulationSCErrorFn)InsulationResetSCSymbol("SCError");
    return errorFn != NULL ? errorFn() : kSCStatusFailed;
}

static int InsulationResetRemoveThermalKey(CFStringRef key) {
    SCPreferencesRef prefs = InsulationResetThermalPrefs();
    if (prefs == NULL) {
        return kSCStatusFailed;
    }

    InsulationSCPreferencesRemoveValueFn removeValue = (InsulationSCPreferencesRemoveValueFn)InsulationResetSCSymbol("SCPreferencesRemoveValue");
    InsulationSCPreferencesCommitChangesFn commit = (InsulationSCPreferencesCommitChangesFn)InsulationResetSCSymbol("SCPreferencesCommitChanges");
    InsulationSCPreferencesApplyChangesFn apply = (InsulationSCPreferencesApplyChangesFn)InsulationResetSCSymbol("SCPreferencesApplyChanges");
    if (removeValue == NULL || commit == NULL || apply == NULL) {
        CFRelease(prefs);
        return kSCStatusFailed;
    }

    (void)removeValue(prefs, key);
    Boolean committed = commit(prefs);
    if (committed) {
        (void)apply(prefs);
    }
    int status = committed ? kSCStatusOK : InsulationResetSCError();
    CFRelease(prefs);
    return status;
}

static const char *InsulationResetThermalPressureNotifyName(void) {
    if (&kOSThermalNotificationPressureLevelName != NULL && kOSThermalNotificationPressureLevelName != NULL) {
        return kOSThermalNotificationPressureLevelName;
    }

    const char **name = (const char **)dlsym(RTLD_DEFAULT, "kOSThermalNotificationPressureLevelName");
    if (name != NULL && *name != NULL) {
        return *name;
    }

    return "com.apple.system.thermalpressurelevel";
}

static int InsulationResetDarwinThermalPressure(void) {
    int token = 0;
    const char *name = InsulationResetThermalPressureNotifyName();
    if (name == NULL || notify_register_check(name, &token) != NOTIFY_STATUS_OK) {
        return -1;
    }

    int status = notify_set_state(token, 0);
    if (status == NOTIFY_STATUS_OK) {
        status = notify_post(name);
    }
    notify_cancel(token);
    return status;
}

static void InsulationResetNativeThermalState(void) {
    static CFStringRef keys[] = {
        CFSTR("engageBehavior"),
        CFSTR("engageBehaviorPersistentlyEnabled"),
        CFSTR("OSThermalNotificationEnabled"),
        CFSTR("OSThermalNotificationPersistentlyEnabled"),
        CFSTR("hipOverride"),
        CFSTR("hipPersistentlyEnabled"),
        CFSTR("simulateHip"),
        CFSTR("sunlightOverride"),
        CFSTR("sunlightOverridePersistentlyEnabled"),
    };

    int lastStatus = kSCStatusOK;
    for (size_t i = 0; i < sizeof(keys) / sizeof(keys[0]); i++) {
        int status = InsulationResetRemoveThermalKey(keys[i]);
        if (status != kSCStatusOK) {
            lastStatus = status;
        }
    }
    int pressureStatus = InsulationResetDarwinThermalPressure();
    INSULATION_LOG(@"insulation reset-native-only: prefs=%d pressure=%d", lastStatus, pressureStatus);
    (void)lastStatus;
    (void)pressureStatus;
}

__attribute__((constructor)) static void InsulationObjCPortInit(void) {
    // Clean reset-only recovery build. It intentionally does not link runtime hooks,
    // power helper code, Darwin prefs replay, or performance apply logic.
    InsulationResetNativeThermalState();
    NSArray<NSNumber *> *delays = @[@0.25, @1.0, @2.0, @4.0];
    for (NSNumber *delay in delays) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)([delay doubleValue] * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
            InsulationResetNativeThermalState();
        });
    }
}
