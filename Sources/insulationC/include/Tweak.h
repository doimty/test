#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#if __has_include(<roothide.h>)
#import <roothide.h>
#else
#define jbroot(path) (path)
#endif
#import <spawn.h>
#include <stdbool.h>

#include "InsulationNativeState.h"
#import "./Power_header/CommonProduct.h"
#import "./Power_header/MitigationController.h"
#import "./Power_header/HidSensors.h"
#import "./Power_header/ThermalManager.h"
#import "./Power_header/PackagePowerCC.h"
#import "./Power_header/ComponentControl.h"
#import "./Power_header/CPMSHelper.h"
#import "./NSDictionary_header/NSDictionary.h"

static NSString *_Nonnull rootlessPath(NSString* _Nonnull path) __attribute__((unused));
static NSString *_Nonnull rootlessPath(NSString* _Nonnull path) {
  return jbroot(path);
}

typedef NS_ENUM(NSInteger, InsulationThermalPressureLevel) {
  InsulationThermalPressureNominal = 0,
  InsulationThermalPressureLight = 1,
  InsulationThermalPressureModerate = 2,
  InsulationThermalPressureHeavy = 3,
  InsulationThermalPressureTrapping = 4,
  InsulationThermalPressureSleeping = 5,
};

void insulationMarkProcessStart(void);
bool insulationFullPowerBootGuardActive(void);
double insulationFullPowerBootGuardDurationSeconds(void);
bool insulationIsThermalmonitordProcess(void);
int insulationSetDarwinThermalPressure(int pressure);
int insulationSetOSNotifEnabled(bool enable, bool persist);
int insulationSetOSNotifNative(void);
int insulationSetThermalMitigationsEnabled(bool enable, bool persist);
int insulationSetThermalMitigationsNative(void);
int insulationSetHIPEnabled(bool enable, bool persist);
int insulationSetHIPNative(void);
int insulationSetSimulateHIPEnabled(bool enable);
int insulationSetSunlightOverride(bool enable, bool persist);
