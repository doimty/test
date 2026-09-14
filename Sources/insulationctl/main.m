#import <Foundation/Foundation.h>

#import <dlfcn.h>
#import <errno.h>
#import <fcntl.h>
#import <stdint.h>
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
static const char *InsulationCtlRuntimeStateName = "com.be-huge.insulation.runtimeState";
static const char *InsulationCtlApplyNotificationName = "com.be-huge.insulation-executePuppetEvent";
static const char *InsulationCtlRestartNotificationName = "com.be-huge.insulation-restartThermalMonitor";
/* ASCII 'INSU' in high 32 bits; daemon checks this magic to confirm the
   notify_set_state sender is a genuine insulationctl instance. */
static const uint64_t InsulationCtlRuntimeStateMagic = 0x494E535500000000ULL;

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

static void InsulationCtlAddUniquePath(NSMutableArray<NSString *> *paths, NSMutableSet<NSString *> *seen, NSString *path) {
    if (path.length == 0 || [seen containsObject:path]) {
        return;
    }
    [seen addObject:path];
    [paths addObject:path];
}

static NSArray<NSString *> *InsulationCtlJbrootPrefixes(void) {
    NSMutableArray<NSString *> *prefixes = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    char prefix[PATH_MAX];
    NSString *exe = InsulationCtlExecutablePath();
    if (exe.length > 0 &&
        InsulationCtlJbrootPrefixFromPath(exe.fileSystemRepresentation, prefix, sizeof(prefix))) {
        InsulationCtlAddUniquePath(prefixes, seen, [NSString stringWithUTF8String:prefix]);
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *bases = @[
        @"/private/var/containers/Bundle/Application",
        @"/var/containers/Bundle/Application",
    ];
    for (NSString *base in bases) {
        NSArray<NSString *> *names = [fm contentsOfDirectoryAtPath:base error:nil];
        for (NSString *name in names) {
            if (![name hasPrefix:@".jbroot-"] || name.length < 9) {
                continue;
            }
            InsulationCtlAddUniquePath(prefixes, seen, [base stringByAppendingPathComponent:name]);
        }
    }
    return prefixes;
}

static void *InsulationCtlRoothideHandle(void) {
    static void *handle = NULL;
    static bool tried = false;
    if (tried) {
        return handle;
    }
    tried = true;
    for (NSString *prefix in InsulationCtlJbrootPrefixes()) {
        NSString *lib = [prefix stringByAppendingString:@"/usr/lib/libroothide.dylib"];
        handle = dlopen(lib.fileSystemRepresentation, RTLD_NOW);
        if (handle) {
            return handle;
        }
    }
    return NULL;
}

static NSString *InsulationCtlJbrootTranslate(NSString *path) {
    typedef char *(*JbrootAllocFn)(const char *);
    void *handle = InsulationCtlRoothideHandle();
    JbrootAllocFn jbrootAlloc;
    char *translated;
    if (!handle || path.length == 0) {
        return nil;
    }
    jbrootAlloc = (JbrootAllocFn)dlsym(handle, "jbroot_alloc");
    if (!jbrootAlloc) {
        return nil;
    }
    translated = jbrootAlloc(path.fileSystemRepresentation);
    if (!translated) {
        return nil;
    }
    NSString *result = [NSString stringWithUTF8String:translated];
    free(translated);
    return result;
}

static NSArray<NSString *> *InsulationCtlPrefsCandidates(void) {
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    NSArray<NSString *> *prefixes = InsulationCtlJbrootPrefixes();
    NSString *systemPath = [NSString stringWithUTF8String:InsulationCtlPrefsFilePath()];
    BOOL loaded = InsulationCtlRoothideHandle() != NULL;

    for (NSString *prefix in prefixes) {
        InsulationCtlAddUniquePath(paths, seen, [prefix stringByAppendingString:systemPath]);
    }
    if (loaded) {
        InsulationCtlAddUniquePath(paths, seen, InsulationCtlJbrootTranslate(systemPath));
        InsulationCtlAddUniquePath(paths, seen, systemPath);
    } else if (prefixes.count == 0) {
        InsulationCtlAddUniquePath(paths, seen, systemPath);
    }
    return paths;
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

    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *lastUnreadable = nil;
    for (NSString *path in InsulationCtlPrefsCandidates()) {
        BOOL isDirectory = NO;
        if (![fm fileExistsAtPath:path isDirectory:&isDirectory]) {
            continue;
        }
        if (isDirectory) {
            if (errorOut) {
                *errorOut = [NSString stringWithFormat:@"prefs path is a directory: %@", path];
            }
            return false;
        }
        NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:path];
        if (!prefs) {
            lastUnreadable = path;
            continue;
        }
        id value = [prefs objectForKey:InsulationCtlPrefsKey];
        const char *prefsValue = [value isKindOfClass:[NSString class]] ? [(NSString *)value UTF8String] : NULL;
        InsulationCtlModeFromPrefsValue(prefsValue, modeOut);
        return true;
    }
    if (lastUnreadable) {
        if (errorOut) {
            *errorOut = [NSString stringWithFormat:@"failed to read prefs: %@", lastUnreadable];
        }
        return false;
    }
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

    (void)errorOut;
    chown([path fileSystemRepresentation], uid, gid);
    chmod([path fileSystemRepresentation], 0644);
    return true;
}

static bool InsulationCtlWriteBytesToPath(NSString *path, NSData *data, NSString **errorOut) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *parent = [path stringByDeletingLastPathComponent];
    NSError *mkdirError = nil;
    if (![fm createDirectoryAtPath:parent withIntermediateDirectories:YES attributes:nil error:&mkdirError]) {
        if (errorOut) {
            *errorOut = [NSString stringWithFormat:@"failed to create prefs directory %@: %@", parent, InsulationCtlNSErrorDescription(mkdirError)];
        }
        return false;
    }

    BOOL isDirectory = NO;
    if ([fm fileExistsAtPath:path isDirectory:&isDirectory] && isDirectory) {
        if (errorOut) {
            *errorOut = [NSString stringWithFormat:@"prefs path is a directory: %@", path];
        }
        return false;
    }

    const char *cpath = path.fileSystemRepresentation;
    int fd = open(cpath, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) {
        if (errorOut) {
            *errorOut = [NSString stringWithFormat:@"failed to write prefs %@: %s", path, strerror(errno)];
        }
        return false;
    }

    const uint8_t *bytes = data.bytes;
    NSUInteger remaining = data.length;
    while (remaining > 0) {
        ssize_t n = write(fd, bytes, remaining);
        if (n < 0) {
            int err = errno;
            close(fd);
            if (errorOut) {
                *errorOut = [NSString stringWithFormat:@"failed to write prefs %@: %s", path, strerror(err)];
            }
            return false;
        }
        bytes += (size_t)n;
        remaining -= (NSUInteger)n;
    }
    fsync(fd);
    close(fd);
    return InsulationCtlRepairPrefsOwnerIfRoot(path, errorOut);
}

static bool InsulationCtlWriteConfiguredMode(InsulationCtlMode mode, NSString **errorOut) {
    NSMutableDictionary *prefs = [NSMutableDictionary dictionary];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *path in InsulationCtlPrefsCandidates()) {
        BOOL isDirectory = NO;
        if (![fm fileExistsAtPath:path isDirectory:&isDirectory] || isDirectory) {
            continue;
        }
        NSDictionary *existingPrefs = [NSDictionary dictionaryWithContentsOfFile:path];
        if (existingPrefs) {
            prefs = [existingPrefs mutableCopy];
            break;
        }
    }

    NSString *prefsValue = [NSString stringWithUTF8String:InsulationCtlModePrefsValue(mode)];
    [prefs setObject:prefsValue forKey:InsulationCtlPrefsKey];

    NSError *plistError = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:prefs
                                                             format:NSPropertyListBinaryFormat_v1_0
                                                            options:0
                                                              error:&plistError];
    if (!data) {
        if (errorOut) {
            *errorOut = [NSString stringWithFormat:@"failed to serialize prefs: %@", InsulationCtlNSErrorDescription(plistError)];
        }
        return false;
    }

    NSMutableArray<NSString *> *errors = [NSMutableArray array];
    for (NSString *path in InsulationCtlPrefsCandidates()) {
        NSString *writeError = nil;
        if (InsulationCtlWriteBytesToPath(path, data, &writeError)) {
            return true;
        }
        if (writeError) {
            [errors addObject:writeError];
        }
    }
    if (errorOut) {
        *errorOut = errors.count > 0 ? [errors componentsJoinedByString:@"; "] : @"failed to write prefs";
    }
    return false;
}

static int InsulationCtlPostRuntimeState(void) {
    int token = 0;
    int status = notify_register_check(InsulationCtlRuntimeStateName, &token);
    if (status != NOTIFY_STATUS_OK) {
        return status;
    }

    status = notify_set_state(token, InsulationCtlRuntimeStateMagic);
    if (status == NOTIFY_STATUS_OK) {
        status = notify_post(InsulationCtlRuntimeStateName);
    }
    notify_cancel(token);
    return status;
}

static bool InsulationCtlPostApplyAndRestart(NSString **errorOut) {
    int runtimeStatus = InsulationCtlPostRuntimeState();
    int applyStatus = notify_post(InsulationCtlApplyNotificationName);
    int restartStatus = notify_post(InsulationCtlRestartNotificationName);

    if (runtimeStatus == NOTIFY_STATUS_OK && applyStatus == NOTIFY_STATUS_OK && restartStatus == NOTIFY_STATUS_OK) {
        return true;
    }

    if (errorOut) {
        *errorOut = [NSString stringWithFormat:@"notification failed: runtime=%d apply=%d restart=%d", runtimeStatus, applyStatus, restartStatus];
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
            bool notified = InsulationCtlPostApplyAndRestart(&notifyError);
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
