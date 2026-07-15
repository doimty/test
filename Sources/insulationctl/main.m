#import <Foundation/Foundation.h>

#import <grp.h>
#import <limits.h>
#import <mach-o/dyld.h>
#import <notify.h>
#import <pwd.h>
#import <stdbool.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import <sys/stat.h>
#import <sys/types.h>
#import <unistd.h>

#import "InsulationCtlArgs.h"

static NSString *const InsulationCtlPrefsKey = @"thermalPowerMode";
static NSString *const InsulationCtlPrefsBasePath = @"/var/mobile/Library/Preferences/com.be-huge.insulation-prefs.plist";
static const char *InsulationCtlModeChangeNotificationName = "com.be-huge.insulation-modeDidChange";

static NSString *InsulationCtlExecutablePath(void) {
    char buffer[PATH_MAX];
    uint32_t size = sizeof(buffer);
    if (_NSGetExecutablePath(buffer, &size) != 0) {
        return nil;
    }

    char resolved[PATH_MAX];
    const char *pathBytes = realpath(buffer, resolved) ? resolved : buffer;
    return [[NSFileManager defaultManager] stringWithFileSystemRepresentation:pathBytes length:strlen(pathBytes)];
}

static NSString *InsulationCtlRoothidePrefix(void) {
    NSString *executablePath = InsulationCtlExecutablePath();
    if (executablePath.length == 0) {
        return nil;
    }

    NSArray<NSString *> *suffixes = @[@"/usr/bin/insulationctl", @"/usr/bin/ins"];
    for (NSString *suffix in suffixes) {
        if (![executablePath hasSuffix:suffix]) {
            continue;
        }
        NSString *prefix = [executablePath substringToIndex:executablePath.length - suffix.length];
        if ([[prefix lastPathComponent] hasPrefix:@".jbroot-"]) {
            return prefix;
        }
    }
    return nil;
}

static NSString *InsulationCtlPrefsPath(void) {
    NSString *roothidePrefix = InsulationCtlRoothidePrefix();
    if (roothidePrefix.length > 0) {
        return [roothidePrefix stringByAppendingString:InsulationCtlPrefsBasePath];
    }
    return InsulationCtlPrefsBasePath;
}

static void InsulationCtlPrintUsage(FILE *stream) {
    fprintf(stream,
            "Usage: ins [off|low|max|status] [--raw] [--quiet]\n"
            "\n"
            "Modes:\n"
            "  off   Apple native thermal control\n"
            "  low   Simulated low-power frequency\n"
            "  max   Prevent thermal downclocking\n"
            "\n"
            "Aliases:\n"
            "  lowPower   same as low\n"
            "  fullPower  same as max\n"
            "\n"
            "Options:\n"
            "  --raw      print only off, low, or max\n"
            "  --quiet    suppress success output\n"
            "  -h, --help show this help\n");
}

static void InsulationCtlPrintMode(InsulationCtlMode mode, bool raw, bool quiet) {
    if (quiet) {
        return;
    }
    const char *display = InsulationCtlModeDisplayName(mode);
    if (raw) {
        printf("%s\n", display);
    } else {
        printf("Insulation: %s\n", display);
    }
}

static NSString *InsulationCtlNSErrorDescription(NSError *error) {
    if (!error) {
        return @"unknown error";
    }
    NSString *description = [error localizedDescription];
    return description ?: @"unknown error";
}

static bool InsulationCtlReadConfiguredMode(InsulationCtlMode *modeOut, NSString **errorOut) {
    if (modeOut) {
        *modeOut = INSULATION_CTL_MODE_OFF;
    }

    NSString *path = InsulationCtlPrefsPath();
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDirectory = NO;
    if (![fm fileExistsAtPath:path isDirectory:&isDirectory]) {
        return true;
    }
    if (isDirectory) {
        if (errorOut) {
            *errorOut = [NSString stringWithFormat:@"prefs path is a directory: %@", path];
        }
        return false;
    }

    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:path];
    if (!prefs) {
        if (errorOut) {
            *errorOut = [NSString stringWithFormat:@"failed to read prefs: %@", path];
        }
        return false;
    }

    id value = [prefs objectForKey:InsulationCtlPrefsKey];
    const char *prefsValue = [value isKindOfClass:[NSString class]] ? [(NSString *)value UTF8String] : NULL;
    InsulationCtlModeFromPrefsValue(prefsValue, modeOut);
    return true;
}

static bool InsulationCtlRepairPrefsOwnerIfRoot(NSString *path, NSString **errorOut) {
    if (geteuid() != 0) {
        return true;
    }

    struct passwd *mobileUser = getpwnam("mobile");
    uid_t uid = mobileUser ? mobileUser->pw_uid : 501;

    struct group *mobileGroup = getgrnam("mobile");
    gid_t gid = mobileGroup ? mobileGroup->gr_gid : 501;

    if (chown([path fileSystemRepresentation], uid, gid) != 0) {
        if (errorOut) {
            *errorOut = [NSString stringWithFormat:@"failed to chown prefs to mobile:mobile: %@", path];
        }
        return false;
    }
    /* Ensure daemon and Settings panel can read the prefs file. */
    chmod([path fileSystemRepresentation], 0644);
    return true;
}

static bool InsulationCtlWriteConfiguredMode(InsulationCtlMode mode, NSString **errorOut) {
    NSString *path = InsulationCtlPrefsPath();
    NSString *parent = [path stringByDeletingLastPathComponent];
    NSFileManager *fm = [NSFileManager defaultManager];

    NSError *mkdirError = nil;
    if (![fm createDirectoryAtPath:parent withIntermediateDirectories:YES attributes:nil error:&mkdirError]) {
        if (errorOut) {
            *errorOut = [NSString stringWithFormat:@"failed to create prefs directory %@: %@", parent, InsulationCtlNSErrorDescription(mkdirError)];
        }
        return false;
    }

    BOOL isDirectory = NO;
    BOOL exists = [fm fileExistsAtPath:path isDirectory:&isDirectory];
    if (exists && isDirectory) {
        if (errorOut) {
            *errorOut = [NSString stringWithFormat:@"prefs path is a directory: %@", path];
        }
        return false;
    }

    NSMutableDictionary *prefs = nil;
    if (exists) {
        NSDictionary *existingPrefs = [NSDictionary dictionaryWithContentsOfFile:path];
        if (!existingPrefs) {
            if (errorOut) {
                *errorOut = [NSString stringWithFormat:@"failed to read existing prefs: %@", path];
            }
            return false;
        }
        prefs = [existingPrefs mutableCopy];
    } else {
        prefs = [NSMutableDictionary dictionary];
    }

    NSString *prefsValue = [NSString stringWithUTF8String:InsulationCtlModePrefsValue(mode)];
    [prefs setObject:prefsValue forKey:InsulationCtlPrefsKey];

    if (![prefs writeToFile:path atomically:YES]) {
        if (errorOut) {
            *errorOut = [NSString stringWithFormat:@"failed to write prefs: %@", path];
        }
        return false;
    }

    return InsulationCtlRepairPrefsOwnerIfRoot(path, errorOut);
}

static bool InsulationCtlPostModeChange(NSString **errorOut) {
    int status = notify_post(InsulationCtlModeChangeNotificationName);
    if (status == NOTIFY_STATUS_OK) {
        return true;
    }

    if (errorOut) {
        *errorOut = [NSString stringWithFormat:@"mode notification failed: %d", status];
    }
    return false;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        InsulationCtlParseResult parsed;
        int parseCode = InsulationCtlParseArgs(argc, argv, &parsed);
        if (parseCode != INSULATION_CTL_EXIT_OK) {
            fprintf(stderr, "ins: %s\n", parsed.errorMessage ?: "invalid arguments");
            InsulationCtlPrintUsage(stderr);
            return parseCode;
        }

        if (parsed.action == INSULATION_CTL_ACTION_HELP) {
            InsulationCtlPrintUsage(stdout);
            return INSULATION_CTL_EXIT_OK;
        }

        if (parsed.action == INSULATION_CTL_ACTION_STATUS) {
            InsulationCtlMode mode = INSULATION_CTL_MODE_OFF;
            NSString *readError = nil;
            if (!InsulationCtlReadConfiguredMode(&mode, &readError)) {
                fprintf(stderr, "ins: %s\n", [readError UTF8String]);
                return INSULATION_CTL_EXIT_IO;
            }
            InsulationCtlPrintMode(mode, parsed.raw, parsed.quiet);
            return INSULATION_CTL_EXIT_OK;
        }

        if (parsed.action == INSULATION_CTL_ACTION_SET_MODE) {
            NSString *writeError = nil;
            if (!InsulationCtlWriteConfiguredMode(parsed.mode, &writeError)) {
                fprintf(stderr, "ins: %s\n", [writeError UTF8String]);
                return INSULATION_CTL_EXIT_IO;
            }

            NSString *notifyError = nil;
            bool notified = InsulationCtlPostModeChange(&notifyError);
            InsulationCtlPrintMode(parsed.mode, parsed.raw, parsed.quiet);
            if (!notified) {
                fprintf(stderr, "ins: Warning: mode saved, but apply notification failed: %s\n", [notifyError UTF8String]);
                return INSULATION_CTL_EXIT_NOTIFY;
            }
            return INSULATION_CTL_EXIT_OK;
        }

        fprintf(stderr, "ins: invalid action\n");
        InsulationCtlPrintUsage(stderr);
        return INSULATION_CTL_EXIT_USAGE;
    }
}
