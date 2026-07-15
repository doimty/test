#include "InsulationRemovalProtocol.h"

#include <ctype.h>
#include <limits.h>
#include <stdio.h>
#include <string.h>

bool InsulationRemovalNonceIsValid(const char *nonce) {
    if (nonce == NULL || strlen(nonce) != 36) {
        return false;
    }
    for (size_t index = 0; index < 36; index++) {
        bool hyphenPosition = index == 8 || index == 13 || index == 18 || index == 23;
        if (hyphenPosition ? nonce[index] != '-' : !isxdigit((unsigned char)nonce[index])) {
            return false;
        }
    }
    return true;
}

bool InsulationRemovalParseAcknowledgment(const char *text,
                                          const char *expectedNonce,
                                          int *pidOut) {
    if (text == NULL || !InsulationRemovalNonceIsValid(expectedNonce) || pidOut == NULL) {
        return false;
    }

    char nonce[65] = {0};
    char trailing = '\0';
    long parsedPID = 0;
    int fields = sscanf(text, " %64s %ld %c", nonce, &parsedPID, &trailing);
    if (fields != 2 || strcmp(nonce, expectedNonce) != 0 || parsedPID <= 1 || parsedPID > INT_MAX) {
        return false;
    }

    *pidOut = (int)parsedPID;
    return true;
}
