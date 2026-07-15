#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

BOOL InsulationRemovalCurrentMarkerIsValid(void);
BOOL InsulationRemovalInitializeFromMarker(void);
BOOL InsulationRemovalIsDisabled(void);
void InsulationRemovalLatchDisabled(void);

BOOL InsulationRemovalAcknowledgeCurrentMarker(NSError **errorOut);
BOOL InsulationRemovalPrepareAndWait(NSError **errorOut);
BOOL InsulationRemovalClearMarker(NSError **errorOut);

NS_ASSUME_NONNULL_END
