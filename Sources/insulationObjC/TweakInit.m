#import "InsulationDebug.h"
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <dispatch/dispatch.h>
#import <signal.h>
#import <unistd.h>

#import "InsulationPowerHelper.h"
#import "InsulationProbe.h"
#import "InsulationRemovalGuard.h"
#import "InsulationRuntimeHooks.h"
#import "../insulationC/InsulationRemovalProtocol.h"
#import "../insulationC/include/Tweak.h"

static void InsulationApplyNotificationCallback(CFNotificationCenterRef center,
                                                void *observer,
                                                CFStringRef name,
                                                const void *object,
                                                CFDictionaryRef userInfo) {
    if (InsulationRemovalIsDisabled()) {
        return;
    }
    InsulationExecutePuppetEventWithSource(@"notification.apply");
    InsulationExecutePuppetEventSoonWithSource(@"notification.applySoon");
}

static void InsulationModeChangeNotificationCallback(CFNotificationCenterRef center,
                                                     void *observer,
                                                     CFStringRef name,
                                                     const void *object,
                                                     CFDictionaryRef userInfo) {
    if (InsulationRemovalIsDisabled()) {
        return;
    }
    InsulationExecutePuppetEventWithSource(@"notification.modeDidChange");
    INSULATION_LOG(@"insulation: mode apply drained; restarting thermalmonitord");
    kill(getpid(), SIGTERM);
}

static void InsulationPrepareRemovalNotificationCallback(CFNotificationCenterRef center,
                                                          void *observer,
                                                          CFStringRef name,
                                                          const void *object,
                                                          CFDictionaryRef userInfo) {
    if (!InsulationRemovalCurrentMarkerIsValid()) {
        return;
    }
    InsulationPreparePuppetEventsForRemoval();
    NSError *error = nil;
    if (!InsulationRemovalAcknowledgeCurrentMarker(&error)) {
        INSULATION_LOG(@"insulation: removal acknowledgment failed: %@", error);
        return;
    }
    kill(getpid(), SIGTERM);
}

static void InsulationRegisterRemovalObserver(void) {
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    NULL,
                                    InsulationPrepareRemovalNotificationCallback,
                                    CFSTR(INSULATION_REMOVAL_PREPARE_NOTIFICATION),
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
}

__attribute__((constructor)) static void InsulationObjCPortInit(void) {
    InsulationProbeMarkLoaded(@"init.begin");
    // Match DimmingPatch: filter + runtime gate. Do not install hooks outside thermalmonitord.
    if (!insulationIsThermalmonitordProcess()) {
        InsulationProbeMarkLoaded(@"init.skip.nonThermalmonitord");
        return;
    }
    if (InsulationRemovalInitializeFromMarker()) {
        InsulationRegisterRemovalObserver();
        InsulationPrepareRemovalNotificationCallback(NULL, NULL, NULL, NULL, NULL);
        return;
    }
    insulationMarkProcessStart();
    InsulationRuntimeHooksInstall();
    InsulationProbeMarkLoaded(@"hooks.installed");

    CFNotificationCenterRef center = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterAddObserver(center,
                                    NULL,
                                    InsulationApplyNotificationCallback,
                                    CFSTR("com.be-huge.insulation-executePuppetEvent"),
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(center,
                                    NULL,
                                    InsulationModeChangeNotificationCallback,
                                    CFSTR("com.be-huge.insulation-modeDidChange"),
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    InsulationRegisterRemovalObserver();

    // A power-mode switch restarts thermalmonitord. The new process will not receive the
    // pre-restart apply notification, so replay prefs after startup.
    InsulationExecutePuppetEventSoonWithSource(@"constructor.startupSoon");
}
