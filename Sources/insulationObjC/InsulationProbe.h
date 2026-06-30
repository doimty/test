#import <Foundation/Foundation.h>

void InsulationProbeMarkLoaded(NSString *stage);
void InsulationProbeEvent(NSString *event);
void InsulationProbeRecordApply(NSString *mode, BOOL bootGuardActive, NSString *source);
void InsulationProbeRecordMitigationUpdate(NSString *name, BOOL changed);
void InsulationProbeRecordSelfHeal(NSString *reason);
void InsulationProbeRecordSetter(NSString *name, NSInteger originalValue, NSInteger patchedValue);
