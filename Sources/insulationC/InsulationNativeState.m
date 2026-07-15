#import "include/InsulationNativeState.h"

#import <CoreFoundation/CoreFoundation.h>
#import <SystemConfiguration/SystemConfiguration.h>
#include <dlfcn.h>
#include <pthread.h>
#include <stdbool.h>

typedef SCPreferencesRef (*InsulationNativeSCPreferencesCreateFn)(CFAllocatorRef allocator, CFStringRef name, CFStringRef prefsID);
typedef CFPropertyListRef (*InsulationNativeSCPreferencesGetValueFn)(SCPreferencesRef prefs, CFStringRef key);
typedef Boolean (*InsulationNativeSCPreferencesRemoveValueFn)(SCPreferencesRef prefs, CFStringRef key);
typedef Boolean (*InsulationNativeSCPreferencesCommitChangesFn)(SCPreferencesRef prefs);
typedef Boolean (*InsulationNativeSCPreferencesApplyChangesFn)(SCPreferencesRef prefs);
typedef int (*InsulationNativeSCErrorFn)(void);

static void *InsulationNativeSCHandle;
static pthread_once_t InsulationNativeSCHandleOnce = PTHREAD_ONCE_INIT;

static void insulationNativeOpenSystemConfiguration(void) {
    InsulationNativeSCHandle = dlopen("/System/Library/Frameworks/SystemConfiguration.framework/SystemConfiguration",
                                      RTLD_LAZY | RTLD_LOCAL);
}

static void *insulationNativeSCSymbol(const char *name) {
    pthread_once(&InsulationNativeSCHandleOnce, insulationNativeOpenSystemConfiguration);
    if (InsulationNativeSCHandle == NULL) {
        return NULL;
    }
    return dlsym(InsulationNativeSCHandle, name);
}

static int insulationNativeSCError(InsulationNativeSCErrorFn errorFn) {
    return errorFn != NULL ? errorFn() : kSCStatusFailed;
}

static int insulationVerifyThermalKeysAbsent(InsulationNativeSCPreferencesCreateFn create,
                                             InsulationNativeSCPreferencesGetValueFn getValue,
                                             const CFStringRef *keys,
                                             size_t count) {
    SCPreferencesRef verifyPrefs = create(kCFAllocatorDefault,
                                          CFSTR("insulation-native-state-verify"),
                                          CFSTR("OSThermalStatus.plist"));
    if (verifyPrefs == NULL) {
        return kSCStatusFailed;
    }
    for (size_t index = 0; index < count; index++) {
        if (getValue(verifyPrefs, keys[index]) != NULL) {
            CFRelease(verifyPrefs);
            return kSCStatusFailed;
        }
    }
    CFRelease(verifyPrefs);
    return kSCStatusOK;
}

static int insulationResetThermalKeys(const CFStringRef *keys, size_t count) {
    InsulationNativeSCPreferencesCreateFn create =
        (InsulationNativeSCPreferencesCreateFn)insulationNativeSCSymbol("SCPreferencesCreate");
    InsulationNativeSCPreferencesGetValueFn getValue =
        (InsulationNativeSCPreferencesGetValueFn)insulationNativeSCSymbol("SCPreferencesGetValue");
    InsulationNativeSCPreferencesRemoveValueFn removeValue =
        (InsulationNativeSCPreferencesRemoveValueFn)insulationNativeSCSymbol("SCPreferencesRemoveValue");
    InsulationNativeSCPreferencesCommitChangesFn commit =
        (InsulationNativeSCPreferencesCommitChangesFn)insulationNativeSCSymbol("SCPreferencesCommitChanges");
    InsulationNativeSCPreferencesApplyChangesFn apply =
        (InsulationNativeSCPreferencesApplyChangesFn)insulationNativeSCSymbol("SCPreferencesApplyChanges");
    InsulationNativeSCErrorFn errorFn =
        (InsulationNativeSCErrorFn)insulationNativeSCSymbol("SCError");
    if (create == NULL || getValue == NULL || removeValue == NULL || commit == NULL || apply == NULL) {
        return kSCStatusFailed;
    }

    SCPreferencesRef prefs = create(kCFAllocatorDefault,
                                    CFSTR("insulation-native-state"),
                                    CFSTR("OSThermalStatus.plist"));
    if (prefs == NULL) {
        return kSCStatusFailed;
    }

    bool changed = false;
    for (size_t index = 0; index < count; index++) {
        if (getValue(prefs, keys[index]) == NULL) {
            continue;
        }
        if (!removeValue(prefs, keys[index])) {
            int status = insulationNativeSCError(errorFn);
            CFRelease(prefs);
            return status;
        }
        changed = true;
    }

    if (!changed) {
        CFRelease(prefs);
        return insulationVerifyThermalKeysAbsent(create, getValue, keys, count);
    }

    if (!commit(prefs)) {
        int status = insulationNativeSCError(errorFn);
        CFRelease(prefs);
        return status;
    }
    if (!apply(prefs)) {
        int status = insulationNativeSCError(errorFn);
        CFRelease(prefs);
        return status;
    }

    CFRelease(prefs);
    return insulationVerifyThermalKeysAbsent(create, getValue, keys, count);
}

int insulationResetOSNotifEnabled(void) {
    const CFStringRef keys[] = {
        CFSTR("OSThermalNotificationEnabled"),
        CFSTR("OSThermalNotificationPersistentlyEnabled"),
    };
    return insulationResetThermalKeys(keys, sizeof(keys) / sizeof(keys[0]));
}

int insulationResetThermalMitigations(void) {
    const CFStringRef keys[] = {
        CFSTR("engageBehavior"),
        CFSTR("engageBehaviorPersistentlyEnabled"),
    };
    return insulationResetThermalKeys(keys, sizeof(keys) / sizeof(keys[0]));
}

int insulationResetHIP(void) {
    const CFStringRef keys[] = {
        CFSTR("hipOverride"),
        CFSTR("hipPersistentlyEnabled"),
    };
    return insulationResetThermalKeys(keys, sizeof(keys) / sizeof(keys[0]));
}

int insulationResetSimulateHIP(void) {
    const CFStringRef keys[] = {
        CFSTR("simulateHip"),
    };
    return insulationResetThermalKeys(keys, sizeof(keys) / sizeof(keys[0]));
}

int insulationResetSunlightOverride(void) {
    const CFStringRef keys[] = {
        CFSTR("sunlightOverride"),
        CFSTR("sunlightOverridePersistentlyEnabled"),
    };
    return insulationResetThermalKeys(keys, sizeof(keys) / sizeof(keys[0]));
}

int insulationResetAllNativeThermalState(void) {
    const CFStringRef keys[] = {
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
    return insulationResetThermalKeys(keys, sizeof(keys) / sizeof(keys[0]));
}
