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
    // pre-restart apply notification, so replay prefs after startup. The short retries
    // intentionally stay under boot guard and should not perform fullPower writes.
    InsulationExecutePuppetEventSoonWithSource(@"constructor.startupSoon");

    // Full-power writes are risky while iOS and jailbreak services are still starting.
    // Apply once after the boot guard expires so fullPower still becomes active without
    // blocking the boot path.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(65.0 * NSEC_PER_SEC)),
                   dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        InsulationExecutePuppetEventWithSource(@"constructor.bootGuardExpired");
    });
}
