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
    InsulationExecutePuppetEvent();
    InsulationExecutePuppetEventSoon();
}

static void InsulationRestartNotificationCallback(CFNotificationCenterRef center,
                                                  void *observer,
                                                  CFStringRef name,
                                                  const void *object,
                                                  CFDictionaryRef userInfo) {
    INSULATION_LOG(@"insulation: restarting thermalmonitord after CPU mode change");
    kill(getpid(), SIGTERM);
}

__attribute__((constructor)) static void InsulationObjCPortInit(void) {
    InsulationProbeMarkLoaded(@"init.begin");
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

    // A power-mode switch restarts thermalmonitord. The new process will not receive the
    // pre-restart apply notification, so replay prefs after startup.
    InsulationExecutePuppetEventSoon();
}
