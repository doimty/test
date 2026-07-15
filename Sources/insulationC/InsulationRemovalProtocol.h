#ifndef INSULATION_REMOVAL_PROTOCOL_H
#define INSULATION_REMOVAL_PROTOCOL_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

#define INSULATION_REMOVAL_MARKER_LOGICAL_PATH "/var/mobile/Library/Preferences/com.be-huge.insulation-removing"
#define INSULATION_REMOVAL_ACK_LOGICAL_PATH "/var/mobile/Library/Preferences/com.be-huge.insulation-removing.ack"
#define INSULATION_REMOVAL_PREPARE_NOTIFICATION "com.be-huge.insulation.prepareRemoval"
#define INSULATION_REMOVAL_ACK_NOTIFICATION "com.be-huge.insulation.removalPrepared"

bool InsulationRemovalNonceIsValid(const char *nonce);

bool InsulationRemovalParseAcknowledgment(const char *text,
                                          const char *expectedNonce,
                                          int *pidOut);

#ifdef __cplusplus
}
#endif

#endif
