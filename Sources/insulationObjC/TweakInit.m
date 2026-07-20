#import "InsulationDebug.h"
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <dispatch/dispatch.h>
#import <notify.h>
#import <signal.h>
#import <unistd.h>

#import "InsulationPowerHelper.h"
#import "InsulationProbe.h"
#import "InsulationRuntimeHooks.h"
#import "../insulationC/include/Tweak.h"

static void InsulationApplyNotificationCallback(CFNotificationCenterRef center,
                                                void *observer,
                                                CFStringRef name,
                                                const void *object,
                                                CFDictionaryRef userInfo) {
    InsulationExecutePuppetEventWithSource(@"notification.apply");
    InsulationExecutePuppetEventSoonWithSource(@"notification.applySoon");
}

static void InsulationRestartNotificationCallback(CFNotificationCenterRef center,
                                                  void *observer,
                                                  CFStringRef name,
                                                  const void *object,
                                                  CFDictionaryRef userInfo) {
    INSULATION_LOG(@"insulation: restarting thermalmonitord after CPU mode change");
    kill(getpid(), SIGTERM);
}

#if INSULATION_PROBE_ENABLED
static const uint64_t InsulationProbeMarkerMagic = 0x494E53554D41524BULL; /* ASCII 'INSUMARK' */

static BOOL InsulationProbeConsumeMarkerMagic(void) {
    int token = -1;
    int status = notify_register_check("com.be-huge.insulation.decisionProbe.mark.downclock", &token);
    uint64_t state = 0;
    if (status == NOTIFY_STATUS_OK) {
        status = notify_get_state(token, &state);
    }
    BOOL valid = status == NOTIFY_STATUS_OK && state == InsulationProbeMarkerMagic;
    if (valid) {
        valid = notify_set_state(token, 0) == NOTIFY_STATUS_OK;
    }
    if (token >= 0) {
        notify_cancel(token);
    }
    return valid;
}

static void InsulationProbeMarkerNotificationCallback(CFNotificationCenterRef center,
                                                       void *observer,
                                                       CFStringRef name,
                                                       const void *object,
                                                       CFDictionaryRef userInfo) {
    (void)center;
    (void)observer;
    (void)name;
    (void)object;
    (void)userInfo;
    if (InsulationProbeConsumeMarkerMagic()) {
        InsulationProbeRecordMarker(@"downclock");
    }
}
#endif

__attribute__((constructor)) static void InsulationObjCPortInit(void) {
    InsulationProbeMarkLoaded(@"init.begin");
    // Match DimmingPatch: filter + runtime gate. Do not install hooks outside thermalmonitord.
    if (!insulationIsThermalmonitordProcess()) {
        InsulationProbeMarkLoaded(@"init.skip.nonThermalmonitord");
        return;
    }
    insulationMarkProcessStart();
    InsulationRuntimeHooksInstall();
    InsulationProbeMarkLoaded(@"hooks.installed");

#if INSULATION_PROBE_ENABLED
    InsulationProbeIOKitInstall();
    InsulationProbeMarkLoaded(@"iokit.probe.installed");
#endif

    CFNotificationCenterRef center = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterAddObserver(center,
                                    NULL,
                                    InsulationApplyNotificationCallback,
                                    CFSTR("com.be-huge.insulation-executePuppetEvent"),
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(center,
                                    NULL,
                                    InsulationApplyNotificationCallback,
                                    CFSTR("com.be-huge.insulation.runtimeState"),
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(center,
                                    NULL,
                                    InsulationRestartNotificationCallback,
                                    CFSTR("com.be-huge.insulation-restartThermalMonitor"),
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
#if INSULATION_PROBE_ENABLED
    CFNotificationCenterAddObserver(center,
                                    NULL,
                                    InsulationProbeMarkerNotificationCallback,
                                    CFSTR("com.be-huge.insulation.decisionProbe.mark.downclock"),
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
#endif

    // A power-mode switch restarts thermalmonitord. The new process will not receive the
    // pre-restart apply notification, so replay prefs after startup.
    InsulationExecutePuppetEventSoonWithSource(@"constructor.startupSoon");
}
