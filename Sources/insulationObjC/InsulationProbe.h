#import <Foundation/Foundation.h>

#ifndef INSULATION_PROBE_ENABLED
#define INSULATION_PROBE_ENABLED 0
#endif

#if INSULATION_PROBE_ENABLED || defined(INSULATION_PROBE_IMPLEMENTATION)

void InsulationProbeMarkLoaded(NSString *stage);
void InsulationProbeEvent(NSString *event);
void InsulationProbeRecordApply(NSString *mode, BOOL bootGuardActive, NSString *source);
void InsulationProbeRecordMitigationUpdate(NSString *name, BOOL changed);
void InsulationProbeRecordSelfHeal(NSString *reason);
void InsulationProbeRecordSetter(NSString *name, NSInteger originalValue, NSInteger patchedValue);
void InsulationProbeRecordSetterDetails(NSString *name, NSInteger originalValue, NSInteger patchedValue, NSDictionary *details);
void InsulationProbeRecordDirectCall(NSString *name, NSDictionary *details);
void InsulationProbeRecordHookInstall(NSString *className, NSString *selectorName, BOOL installed);
void InsulationProbeRecordMethodDump(NSString *className, NSArray *methods);
void InsulationProbeRecordMarker(NSString *name);

/* Phase 4: IOKit write probe (IORegistryEntrySetCFProperty/CFProperties) */
void InsulationProbeIOKitInstall(void);
NSArray *InsulationProbeIOKitSnapshot(void);

#else

#define InsulationProbeMarkLoaded(...) do { } while (0)
#define InsulationProbeEvent(...) do { } while (0)
#define InsulationProbeRecordApply(...) do { } while (0)
#define InsulationProbeRecordMitigationUpdate(...) do { } while (0)
#define InsulationProbeRecordSelfHeal(...) do { } while (0)
#define InsulationProbeRecordSetter(...) do { } while (0)
#define InsulationProbeRecordSetterDetails(...) do { } while (0)
#define InsulationProbeRecordDirectCall(...) do { } while (0)
#define InsulationProbeRecordHookInstall(...) do { } while (0)
#define InsulationProbeRecordMethodDump(...) do { } while (0)
#define InsulationProbeRecordMarker(...) do { } while (0)
#define InsulationProbeIOKitInstall() do { } while (0)
#define InsulationProbeIOKitSnapshot() nil

#endif
