#import <Foundation/Foundation.h>

void InsulationProbeEvent(NSString *event);
void InsulationProbeRecordApply(NSString *mode, BOOL bootGuardActive);
void InsulationProbeRecordMitigationUpdate(NSString *name, BOOL changed);
void InsulationProbeRecordSelfHeal(NSString *reason);
void InsulationProbeRecordSetter(NSString *name, NSInteger originalValue, NSInteger patchedValue);
