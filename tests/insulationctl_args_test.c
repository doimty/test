#include "InsulationCtlArgs.h"

#include <stdbool.h>
#include <stdio.h>
#include <string.h>

static int failures = 0;

#define CHECK(cond, message) \
    do { \
        if (!(cond)) { \
            fprintf(stderr, "FAIL: %s:%d: %s\n", __FILE__, __LINE__, message); \
            failures++; \
        } \
    } while (0)

static InsulationCtlParseResult parse(int argc, const char *const argv[]) {
    InsulationCtlParseResult result;
    int rc = InsulationCtlParseArgs(argc, argv, &result);
    CHECK(rc == result.exitCode, "parse return code matches result.exitCode");
    return result;
}

static void expect_status(const char *label, int argc, const char *const argv[], bool raw, bool quiet) {
    InsulationCtlParseResult result = parse(argc, argv);
    CHECK(result.exitCode == INSULATION_CTL_EXIT_OK, label);
    CHECK(result.action == INSULATION_CTL_ACTION_STATUS, label);
    CHECK(result.raw == raw, label);
    CHECK(result.quiet == quiet, label);
    CHECK(result.mode == INSULATION_CTL_MODE_OFF, label);
}

static void expect_help(const char *label, int argc, const char *const argv[]) {
    InsulationCtlParseResult result = parse(argc, argv);
    CHECK(result.exitCode == INSULATION_CTL_EXIT_OK, label);
    CHECK(result.action == INSULATION_CTL_ACTION_HELP, label);
}

static void expect_set(const char *label,
                       int argc,
                       const char *const argv[],
                       InsulationCtlMode mode,
                       bool raw,
                       bool quiet,
                       const char *display,
                       const char *prefs) {
    InsulationCtlParseResult result = parse(argc, argv);
    CHECK(result.exitCode == INSULATION_CTL_EXIT_OK, label);
    CHECK(result.action == INSULATION_CTL_ACTION_SET_MODE, label);
    CHECK(result.mode == mode, label);
    CHECK(result.raw == raw, label);
    CHECK(result.quiet == quiet, label);
    CHECK(strcmp(InsulationCtlModeDisplayName(result.mode), display) == 0, label);
    CHECK(strcmp(InsulationCtlModePrefsValue(result.mode), prefs) == 0, label);
}

static void expect_probe_mark(const char *label, int argc, const char *const argv[], const char *markerName, bool quiet) {
    InsulationCtlParseResult result = parse(argc, argv);
    CHECK(result.exitCode == INSULATION_CTL_EXIT_OK, label);
    CHECK(result.action == INSULATION_CTL_ACTION_PROBE_MARK, label);
    CHECK(result.markerName != NULL, label);
    CHECK(strcmp(result.markerName, markerName) == 0, label);
    CHECK(result.quiet == quiet, label);
}

static void expect_usage_error(const char *label, int argc, const char *const argv[]) {
    InsulationCtlParseResult result = parse(argc, argv);
    CHECK(result.exitCode == INSULATION_CTL_EXIT_USAGE, label);
    CHECK(result.action == INSULATION_CTL_ACTION_ERROR, label);
    CHECK(result.errorMessage != NULL, label);
}

static void expect_prefs_value(const char *label, const char *prefs, InsulationCtlMode expected) {
    InsulationCtlMode mode = INSULATION_CTL_MODE_FULL_POWER;
    InsulationCtlModeFromPrefsValue(prefs, &mode);
    CHECK(mode == expected, label);
}

int main(void) {
    const char *empty[] = {"ins"};
    expect_status("empty argv defaults to status", 1, empty, false, false);

    const char *status[] = {"ins", "status"};
    expect_status("status", 2, status, false, false);

    const char *raw_status_1[] = {"ins", "--raw", "status"};
    expect_status("raw before status", 3, raw_status_1, true, false);

    const char *raw_status_2[] = {"ins", "status", "--raw"};
    expect_status("raw after status", 3, raw_status_2, true, false);

    const char *raw_default[] = {"ins", "--raw"};
    expect_status("raw defaults to status", 2, raw_default, true, false);

    const char *help[] = {"ins", "help"};
    expect_help("help", 2, help);

    const char *long_help[] = {"ins", "--help"};
    expect_help("--help", 2, long_help);

    const char *short_help[] = {"ins", "-h"};
    expect_help("-h", 2, short_help);

    const char *off[] = {"ins", "off"};
    expect_set("off", 2, off, INSULATION_CTL_MODE_OFF, false, false, "off", "off");

    const char *low[] = {"ins", "low"};
    expect_set("low", 2, low, INSULATION_CTL_MODE_LOW_POWER, false, false, "low", "lowPower");

    const char *low_power[] = {"ins", "lowPower"};
    expect_set("lowPower alias", 2, low_power, INSULATION_CTL_MODE_LOW_POWER, false, false, "low", "lowPower");

    const char *max[] = {"ins", "max"};
    expect_set("max", 2, max, INSULATION_CTL_MODE_FULL_POWER, false, false, "max", "fullPower");

    const char *full_power[] = {"ins", "fullPower"};
    expect_set("fullPower alias", 2, full_power, INSULATION_CTL_MODE_FULL_POWER, false, false, "max", "fullPower");

    const char *quiet_max_1[] = {"ins", "--quiet", "max"};
    expect_set("quiet before max", 3, quiet_max_1, INSULATION_CTL_MODE_FULL_POWER, false, true, "max", "fullPower");

    const char *quiet_max_2[] = {"ins", "max", "--quiet"};
    expect_set("quiet after max", 3, quiet_max_2, INSULATION_CTL_MODE_FULL_POWER, false, true, "max", "fullPower");

    const char *raw_max[] = {"ins", "max", "--raw"};
    expect_set("raw set mode", 3, raw_max, INSULATION_CTL_MODE_FULL_POWER, true, false, "max", "fullPower");

    const char *quiet_raw_max[] = {"ins", "--quiet", "max", "--raw"};
    expect_set("quiet and raw set mode", 4, quiet_raw_max, INSULATION_CTL_MODE_FULL_POWER, true, true, "max", "fullPower");

    const char *probe_mark[] = {"ins", "probe-mark", "downclock"};
    expect_probe_mark("probe mark downclock", 3, probe_mark, "downclock", false);

    const char *quiet_probe_mark[] = {"ins", "--quiet", "probe-mark", "downclock"};
    expect_probe_mark("quiet probe mark downclock", 4, quiet_probe_mark, "downclock", true);

    const char *probe_mark_missing[] = {"ins", "probe-mark"};
    expect_usage_error("probe mark requires name", 2, probe_mark_missing);

    const char *probe_mark_unknown[] = {"ins", "probe-mark", "thermal"};
    expect_usage_error("probe mark rejects unknown name", 3, probe_mark_unknown);

    const char *bad_mode[] = {"ins", "turbo"};
    expect_usage_error("unknown mode", 2, bad_mode);

    const char *bad_flag[] = {"ins", "--loud"};
    expect_usage_error("unknown flag", 2, bad_flag);

    const char *too_many[] = {"ins", "low", "max"};
    expect_usage_error("multiple actions", 3, too_many);

    expect_prefs_value("prefs off", "off", INSULATION_CTL_MODE_OFF);
    expect_prefs_value("prefs lowPower", "lowPower", INSULATION_CTL_MODE_LOW_POWER);
    expect_prefs_value("prefs fullPower", "fullPower", INSULATION_CTL_MODE_FULL_POWER);
    expect_prefs_value("invalid prefs falls back to off", "fulPower", INSULATION_CTL_MODE_OFF);
    expect_prefs_value("missing prefs falls back to off", NULL, INSULATION_CTL_MODE_OFF);

    return failures == 0 ? 0 : 1;
}
