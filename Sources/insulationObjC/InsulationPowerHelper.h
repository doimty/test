#import <Foundation/Foundation.h>

@class CommonProduct;
@class MitigationController;

NS_ASSUME_NONNULL_BEGIN

void InsulationReloadPreferences(void);
BOOL InsulationPreventDimmingEnabled(void);
BOOL InsulationDisplayDimmingBypassEnabled(void);
NSString *InsulationPowerMode(void);
BOOL InsulationLowPowerModeEnabled(void);
BOOL InsulationFullPowerModeEnabled(void);
BOOL InsulationAggressiveFullPowerEnabled(void);
BOOL InsulationThermalDimmingBypassActive(void);
BOOL InsulationPowerMitigationsDisabled(void);
BOOL InsulationCPURestoreActive(void);
BOOL InsulationApplyInProgress(void);
BOOL InsulationCPULimitEnabled(void);
int InsulationForcedCPULevel(void);
int InsulationLimitedCPULevel(int level);
int InsulationUnrestrictedPowerLimit(void);
unsigned InsulationUnrestrictedPowerLimitUInt32(void);
int InsulationLimitedCPUPower(int power);
int InsulationMitigationPowerFloor(int power);
int InsulationFullCPUPower(int power);
void InsulationNoteComponentPowerCandidate(int power);
int InsulationBacklightThermalPowerFloor(void);
int InsulationMaxComponentPower(int power, int mitigationType);

void InsulationSetCommonProductObject(CommonProduct *_Nullable product);
void InsulationSetMitigationControllerObject(MitigationController *_Nullable controller);
void InsulationExecutePuppetEvent(void);
void InsulationExecutePuppetEventWithSource(NSString *_Nullable source);
void InsulationExecutePuppetEventSoon(void);
void InsulationExecutePuppetEventSoonWithSource(NSString *_Nullable source);

NS_ASSUME_NONNULL_END
