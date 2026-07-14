#import "include/Tweak.h"

#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#import <SystemConfiguration/SystemConfiguration.h>
#include <dlfcn.h>
#include <notify.h>
#include <string.h>

__attribute__((weak_import)) extern const char *const kOSThermalNotificationPressureLevelName;

static CFAbsoluteTime InsulationProcessStartTime = 0;
static const double InsulationFullPowerBootGuardDuration = 0.25;

void insulationMarkProcessStart(void) {
    if (InsulationProcessStartTime <= 0) {
        InsulationProcessStartTime = CFAbsoluteTimeGetCurrent();
    }
}

bool insulationIsThermalmonitordProcess(void) {
    extern char ***_NSGetArgv(void);
    char ***argvp = _NSGetArgv();
    if (argvp == NULL || *argvp == NULL || **argvp == NULL) {
        return false;
    }
    char *argv0 = **argvp;
    char *slash = strrchr(argv0, '/');
    const char *name = slash == NULL ? argv0 : slash + 1;
    return strcmp(name, "thermalmonitord") == 0;
}

bool insulationFullPowerBootGuardActive(void) {
    insulationMarkProcessStart();
    return (CFAbsoluteTimeGetCurrent() - InsulationProcessStartTime) < InsulationFullPowerBootGuardDuration;
}

double insulationFullPowerBootGuardDurationSeconds(void) {
    return InsulationFullPowerBootGuardDuration;
}

static const char *insulationThermalPressureNotifyName(void) {
    if (&kOSThermalNotificationPressureLevelName != NULL && kOSThermalNotificationPressureLevelName != NULL) {
        return kOSThermalNotificationPressureLevelName;
    }

    const char **name = (const char **)dlsym(RTLD_DEFAULT, "kOSThermalNotificationPressureLevelName");
    if (name != NULL && *name != NULL) {
        return *name;
    }

    return "com.apple.system.thermalpressurelevel";
}

static uint64_t insulationDarwinPressureValue(int pressure) {
    switch (pressure) {
        case InsulationThermalPressureLight:
            return 10;
        case InsulationThermalPressureModerate:
            return 20;
        case InsulationThermalPressureHeavy:
            return 30;
        case InsulationThermalPressureTrapping:
            return 40;
        case InsulationThermalPressureSleeping:
            return 50;
        case InsulationThermalPressureNominal:
        default:
            return 0;
    }
}

int insulationSetDarwinThermalPressure(int pressure) {
    int token = 0;
    const char *name = insulationThermalPressureNotifyName();
    if (name == NULL || notify_register_check(name, &token) != NOTIFY_STATUS_OK) {
        return -1;
    }

    uint64_t value = insulationDarwinPressureValue(pressure);
    int status = notify_set_state(token, value);
    if (status == NOTIFY_STATUS_OK) {
        status = notify_post(name);
    }
    notify_cancel(token);

    return status;
}

typedef SCPreferencesRef (*InsulationSCPreferencesCreateFn)(CFAllocatorRef allocator, CFStringRef name, CFStringRef prefsID);
typedef Boolean (*InsulationSCPreferencesCommitChangesFn)(SCPreferencesRef prefs);
typedef Boolean (*InsulationSCPreferencesApplyChangesFn)(SCPreferencesRef prefs);
typedef Boolean (*InsulationSCPreferencesSetValueFn)(SCPreferencesRef prefs, CFStringRef key, CFPropertyListRef value);
typedef int (*InsulationSCErrorFn)(void);

static void *insulationSCSymbol(const char *name) {
    return dlsym(RTLD_DEFAULT, name);
}

static SCPreferencesRef insulationThermalPrefs(void) {
    InsulationSCPreferencesCreateFn create = (InsulationSCPreferencesCreateFn)insulationSCSymbol("SCPreferencesCreate");
    if (create == NULL) {
        return NULL;
    }

    return create(kCFAllocatorDefault, CFSTR("insulation"), CFSTR("OSThermalStatus.plist"));
}

static int insulationSCError(void) {
    InsulationSCErrorFn errorFn = (InsulationSCErrorFn)insulationSCSymbol("SCError");
    return errorFn != NULL ? errorFn() : kSCStatusFailed;
}

static int insulationSaveThermalPrefs(SCPreferencesRef prefs) {
    if (prefs == NULL) {
        return kSCStatusFailed;
    }

    InsulationSCPreferencesCommitChangesFn commit = (InsulationSCPreferencesCommitChangesFn)insulationSCSymbol("SCPreferencesCommitChanges");
    InsulationSCPreferencesApplyChangesFn apply = (InsulationSCPreferencesApplyChangesFn)insulationSCSymbol("SCPreferencesApplyChanges");
    if (commit == NULL || apply == NULL) {
        return kSCStatusFailed;
    }

    Boolean committed = commit(prefs);
    if (!committed) {
        return insulationSCError();
    }

    (void)apply(prefs);
    return kSCStatusOK;
}

static int insulationSetThermalBool(CFStringRef key, CFStringRef persistKey, bool enable, bool persist) {
    SCPreferencesRef prefs = insulationThermalPrefs();
    if (prefs == NULL) {
        return kSCStatusFailed;
    }

    InsulationSCPreferencesSetValueFn setValue = (InsulationSCPreferencesSetValueFn)insulationSCSymbol("SCPreferencesSetValue");
    if (setValue == NULL) {
        CFRelease(prefs);
        return kSCStatusFailed;
    }

    setValue(prefs, key, enable ? kCFBooleanTrue : kCFBooleanFalse);
    if (persistKey != NULL) {
        setValue(prefs, persistKey, persist ? kCFBooleanTrue : kCFBooleanFalse);
    }

    int status = insulationSaveThermalPrefs(prefs);
    CFRelease(prefs);
    return status;
}

int insulationSetOSNotifEnabled(bool enable, bool persist) {
    return insulationSetThermalBool(CFSTR("OSThermalNotificationEnabled"),
                                    CFSTR("OSThermalNotificationPersistentlyEnabled"),
                                    enable,
                                    persist);
}

int insulationSetOSNotifNative(void) {
    return insulationSetOSNotifEnabled(true, false);
}

int insulationSetThermalMitigationsEnabled(bool enable, bool persist) {
    return insulationSetThermalBool(CFSTR("engageBehavior"),
                                    CFSTR("engageBehaviorPersistentlyEnabled"),
                                    enable,
                                    persist);
}

int insulationSetThermalMitigationsNative(void) {
    return insulationSetThermalMitigationsEnabled(true, false);
}

int insulationSetHIPEnabled(bool enable, bool persist) {
    return insulationSetThermalBool(CFSTR("hipOverride"),
                                    CFSTR("hipPersistentlyEnabled"),
                                    enable,
                                    persist);
}

int insulationSetHIPNative(void) {
    int ret1 = insulationSetHIPEnabled(true, false);
    int ret2 = insulationSetSimulateHIPEnabled(false);
    return ret1 != kSCStatusOK ? ret1 : ret2;
}

int insulationSetSimulateHIPEnabled(bool enable) {
    return insulationSetThermalBool(CFSTR("simulateHip"), NULL, enable, false);
}

int insulationSetSunlightOverride(bool enable, bool persist) {
    return insulationSetThermalBool(CFSTR("sunlightOverride"),
                                    CFSTR("sunlightOverridePersistentlyEnabled"),
                                    enable,
                                    persist);
}
