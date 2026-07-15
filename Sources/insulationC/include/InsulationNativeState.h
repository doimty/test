#ifndef INSULATION_NATIVE_STATE_H
#define INSULATION_NATIVE_STATE_H

#ifdef __cplusplus
extern "C" {
#endif

int insulationResetOSNotifEnabled(void);
int insulationResetThermalMitigations(void);
int insulationResetHIP(void);
int insulationResetSimulateHIP(void);
int insulationResetSunlightOverride(void);

#ifdef __cplusplus
}
#endif

#endif
