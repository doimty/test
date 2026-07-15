#include <stdio.h>
#include <string.h>

#include "InsulationRemovalProtocol.h"

static int failures;

#define CHECK(condition, label) \
    do { \
        if (!(condition)) { \
            fprintf(stderr, "FAIL: %s (line %d)\n", label, __LINE__); \
            failures++; \
        } \
    } while (0)

static void test_nonce_validation(void) {
    CHECK(InsulationRemovalNonceIsValid("01234567-89AB-CDEF-0123-456789ABCDEF"),
          "generated UUID nonce format is accepted");
    CHECK(!InsulationRemovalNonceIsValid("nonce"),
          "short attacker-controlled nonce is rejected");
    CHECK(!InsulationRemovalNonceIsValid("01234567-89AB-CDEF-0123-456789ABCDEG"),
          "non-hex UUID nonce is rejected");
}

static void test_valid_ack_matches_nonce_and_pid(void) {
    int pid = 0;
    CHECK(InsulationRemovalParseAcknowledgment("01234567-89AB-CDEF-0123-456789ABCDEF 321\n",
                                               "01234567-89AB-CDEF-0123-456789ABCDEF",
                                               &pid),
          "valid acknowledgment parses");
    CHECK(pid == 321, "valid acknowledgment exposes daemon pid");
}

static void test_stale_nonce_is_rejected(void) {
    int pid = 0;
    CHECK(!InsulationRemovalParseAcknowledgment("AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA 321\n",
                                                "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
                                                &pid),
          "stale acknowledgment nonce is rejected");
}

static void test_malformed_ack_is_rejected(void) {
    const char *nonce = "01234567-89AB-CDEF-0123-456789ABCDEF";
    int pid = 0;
    CHECK(!InsulationRemovalParseAcknowledgment("01234567-89AB-CDEF-0123-456789ABCDEF\n", nonce, &pid),
          "missing pid is rejected");
    CHECK(!InsulationRemovalParseAcknowledgment("01234567-89AB-CDEF-0123-456789ABCDEF 1\n", nonce, &pid),
          "non-daemon pid is rejected");
    CHECK(!InsulationRemovalParseAcknowledgment("01234567-89AB-CDEF-0123-456789ABCDEF 321 trailing\n", nonce, &pid),
          "trailing data is rejected");
    CHECK(!InsulationRemovalParseAcknowledgment(NULL, nonce, &pid),
          "missing acknowledgment is rejected");
}

static void test_protocol_paths_are_persistent(void) {
    CHECK(strncmp(INSULATION_REMOVAL_MARKER_LOGICAL_PATH, "/var/mobile/Library/Preferences/", 32) == 0,
          "marker lives under persistent mobile preferences");
    CHECK(strncmp(INSULATION_REMOVAL_ACK_LOGICAL_PATH, "/var/mobile/Library/Preferences/", 32) == 0,
          "ack lives under persistent mobile preferences");
    CHECK(strncmp(INSULATION_REMOVAL_MARKER_LOGICAL_PATH, "/var/run/", 9) != 0,
          "marker is not stored in tmpfs var/run");
}

int main(void) {
    test_nonce_validation();
    test_valid_ack_matches_nonce_and_pid();
    test_stale_nonce_is_rejected();
    test_malformed_ack_is_rejected();
    test_protocol_paths_are_persistent();

    if (failures != 0) {
        fprintf(stderr, "%d removal-protocol test(s) failed\n", failures);
        return 1;
    }
    puts("All removal-protocol tests passed.");
    return 0;
}
