#import "InsulationDebug.h"
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <dispatch/dispatch.h>

#import "../insulationC/include/Tweak.h"

static void InsulationResetNativeThermalState(void) {
    int retMitigation = insulationResetThermalMitigations();
    int retNotif = insulationResetOSNotifEnabled();
    int retHIP = insulationResetHIP();
    int retSimHIP = insulationResetSimulateHIP();
    int retSunlight = insulationResetSunlightOverride();
    int retPressure = insulationSetDarwinThermalPressure(0);
    INSULATION_LOG(@"insulation reset-native: mitigation=%d notif=%d hip=%d simHIP=%d sunlight=%d pressure=%d",
                   retMitigation,
                   retNotif,
                   retHIP,
                   retSimHIP,
                   retSunlight,
                   retPressure);
    (void)retMitigation;
    (void)retNotif;
    (void)retHIP;
    (void)retSimHIP;
    (void)retSunlight;
    (void)retPressure;
}


static void InsulationApplyNotificationCallback(CFNotificationCenterRef center,
                                                void *observer,
                                                CFStringRef name,
                                                const void *object,
                                                CFDictionaryRef userInfo) {
    (void)center;
    (void)observer;
    (void)name;
    (void)object;
    (void)userInfo;
    InsulationResetNativeThermalState();
}

static void InsulationRestartNotificationCallback(CFNotificationCenterRef center,
                                                  void *observer,
                                                  CFStringRef name,
                                                  const void *object,
                                                  CFDictionaryRef userInfo) {
    (void)center;
    (void)observer;
    (void)name;
    (void)object;
    (void)userInfo;
    InsulationResetNativeThermalState();
}

__attribute__((constructor)) static void InsulationObjCPortInit(void) {
    // Reset-only recovery build. Do not install runtime hooks and do not replay user prefs.
    // This clears persistent thermal state that earlier diagnostic/fullPower builds may
    // have left behind, then stays inert so it cannot immediately re-disable thermal policy.
    insulationMarkProcessStart();
    (void)InsulationApplyNotificationCallback;
    (void)InsulationRestartNotificationCallback;
    InsulationResetNativeThermalState();
    NSArray<NSNumber *> *delays = @[@0.25, @1.0, @2.0, @4.0];
    for (NSNumber *delay in delays) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)([delay doubleValue] * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
            InsulationResetNativeThermalState();
        });
    }
}
