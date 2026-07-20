#import <Foundation/Foundation.h>

#ifndef INSULATION_PROBE_ENABLED
#define INSULATION_PROBE_ENABLED 0
#endif

#if INSULATION_PROBE_ENABLED

void InsulationMachIOProbeInstall(void);
NSArray *InsulationMachIOProbeSnapshot(void);

#else

#define InsulationMachIOProbeInstall() do { } while (0)
#define InsulationMachIOProbeSnapshot() nil

#endif