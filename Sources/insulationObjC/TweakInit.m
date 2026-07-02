#import "InsulationDebug.h"
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <dispatch/dispatch.h>
#include <dlfcn.h>
#include <notify.h>

__attribute__((weak_import)) extern const char *const kOSThermalNotificationPressureLevelName;

static SCPreferencesRef InsulationResetThermalPrefs(void) {
    return SCPreferencesCreate(kCFAllocatorDefault, CFSTR("insulation-reset-native"), CFSTR("OSThermalStatus.plist"));
}

static int InsulationResetRemoveThermalKey(CFStringRef key) {
    SCPreferencesRef prefs = InsulationResetThermalPrefs();
    if (prefs == NULL) {
        return kSCStatusFailed;
    }

    (void)SCPreferencesRemoveValue(prefs, key);
    Boolean committed = SCPreferencesCommitChanges(prefs);
    if (committed) {
        (void)SCPreferencesApplyChanges(prefs);
    }
    int status = committed ? kSCStatusOK : SCError();
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
