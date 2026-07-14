#import "InsulationDebug.h"
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <dispatch/dispatch.h>
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

static void InsulationModeChangeNotificationCallback(CFNotificationCenterRef center,
                                                     void *observer,
                                                     CFStringRef name,
                                                     const void *object,
                                                     CFDictionaryRef userInfo) {
    InsulationExecutePuppetEventWithSource(@"notification.modeDidChange");
    INSULATION_LOG(@"insulation: mode apply drained; restarting thermalmonitord");
    kill(getpid(), SIGTERM);
}

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

    // A power-mode switch restarts thermalmonitord. The new process will not receive the
    // pre-restart apply notification, so replay prefs after startup.
    InsulationExecutePuppetEventSoonWithSource(@"constructor.startupSoon");
}
