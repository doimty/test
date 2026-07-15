#import "InsulationRemovalGuard.h"

#import <errno.h>
#import <fcntl.h>
#import <limits.h>
#import <mach-o/dyld.h>
#import <notify.h>
#import <signal.h>
#import <stdatomic.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import <sys/stat.h>
#import <unistd.h>

#import "../insulationC/InsulationRemovalProtocol.h"

#ifndef INSULATION_REMOVAL_TOOL
#define INSULATION_REMOVAL_TOOL 0
#endif

#if !INSULATION_REMOVAL_TOOL
#import "../insulationC/include/Tweak.h"
#endif

static atomic_bool InsulationRemovalDisabled = ATOMIC_VAR_INIT(false);
static const NSTimeInterval InsulationRemovalAcknowledgeTimeout = 5.0;
static const NSTimeInterval InsulationRemovalExitTimeout = 5.0;
static const useconds_t InsulationRemovalPollIntervalMicroseconds = 50000;

static NSError *InsulationRemovalError(NSInteger code, NSString *description) {
    return [NSError errorWithDomain:@"com.be-huge.insulation.removal"
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: description ?: @"unknown removal error"}];
}

#if INSULATION_REMOVAL_TOOL
static NSString *InsulationRemovalExecutablePath(void) {
    char buffer[PATH_MAX];
    uint32_t size = sizeof(buffer);
    if (_NSGetExecutablePath(buffer, &size) != 0) {
        return nil;
    }

    char resolved[PATH_MAX];
    const char *pathBytes = realpath(buffer, resolved) ? resolved : buffer;
    return [[NSFileManager defaultManager] stringWithFileSystemRepresentation:pathBytes length:strlen(pathBytes)];
}

static NSString *InsulationRemovalToolPrefix(void) {
    NSString *executablePath = InsulationRemovalExecutablePath();
    if (executablePath.length == 0) {
        return nil;
    }

    for (NSString *suffix in @[@"/usr/bin/insulationctl", @"/usr/bin/ins"]) {
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
#endif

static NSString *InsulationRemovalResolvedPath(const char *logicalPath) {
    NSString *path = [NSString stringWithUTF8String:logicalPath];
#if INSULATION_REMOVAL_TOOL
    NSString *prefix = InsulationRemovalToolPrefix();
    return prefix.length > 0 ? [prefix stringByAppendingString:path] : path;
#else
    return rootlessPath(path);
#endif
}

static NSString *InsulationRemovalMarkerPath(void) {
    return InsulationRemovalResolvedPath(INSULATION_REMOVAL_MARKER_LOGICAL_PATH);
}

static NSString *InsulationRemovalAcknowledgmentPath(void) {
    return InsulationRemovalResolvedPath(INSULATION_REMOVAL_ACK_LOGICAL_PATH);
}

static BOOL InsulationRemovalRemoveFileIfPresent(NSString *path, NSError **errorOut) {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path]) {
        return YES;
    }
    NSError *error = nil;
    if (![fm removeItemAtPath:path error:&error]) {
        if (errorOut) {
            *errorOut = error ?: InsulationRemovalError(1, [NSString stringWithFormat:@"failed to remove %@", path]);
        }
        return NO;
    }
    return YES;
}

static BOOL InsulationRemovalWriteStringAtomically(NSString *value, NSString *path, NSError **errorOut) {
    NSString *parent = [path stringByDeletingLastPathComponent];
    NSError *mkdirError = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:parent
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:&mkdirError]) {
        if (errorOut) {
            *errorOut = mkdirError ?: InsulationRemovalError(2, [NSString stringWithFormat:@"failed to create %@", parent]);
        }
        return NO;
    }

    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
    NSString *temporaryPath = [NSString stringWithFormat:@"%@.tmp.%d.%@", path, getpid(), [[NSUUID UUID] UUIDString]];
    int fd = open([temporaryPath fileSystemRepresentation], O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0600);
    if (fd < 0) {
        if (errorOut) {
            *errorOut = InsulationRemovalError(errno, [NSString stringWithFormat:@"failed to create secure temporary file for %@", path]);
        }
        return NO;
    }

    const uint8_t *bytes = data.bytes;
    NSUInteger remaining = data.length;
    BOOL success = YES;
    while (remaining > 0) {
        ssize_t written = write(fd, bytes, remaining);
        if (written < 0 && errno == EINTR) {
            continue;
        }
        if (written <= 0) {
            success = NO;
            break;
        }
        bytes += written;
        remaining -= (NSUInteger)written;
    }
    if (success && fsync(fd) != 0) {
        success = NO;
    }
    int savedErrno = success ? 0 : errno;
    if (close(fd) != 0 && success) {
        success = NO;
        savedErrno = errno;
    }
    if (success && rename([temporaryPath fileSystemRepresentation], [path fileSystemRepresentation]) != 0) {
        success = NO;
        savedErrno = errno;
    }
    if (!success) {
        unlink([temporaryPath fileSystemRepresentation]);
        if (errorOut) {
            *errorOut = InsulationRemovalError(savedErrno ?: EIO, [NSString stringWithFormat:@"failed to write %@", path]);
        }
        return NO;
    }
    return YES;
}

static BOOL InsulationRemovalPathIsSecureRegularFile(NSString *path) {
    struct stat info;
    if (lstat([path fileSystemRepresentation], &info) != 0) {
        return NO;
    }
    return S_ISREG(info.st_mode) && info.st_uid == 0 && (info.st_mode & 0077) == 0 && info.st_nlink == 1;
}

static NSString *InsulationRemovalReadTrimmedString(NSString *path) {
    if (!InsulationRemovalPathIsSecureRegularFile(path)) {
        return nil;
    }
    NSError *error = nil;
    NSString *value = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];
    if (!value) {
        return nil;
    }
    NSString *trimmed = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return trimmed.length > 0 ? trimmed : nil;
}

BOOL InsulationRemovalCurrentMarkerIsValid(void) {
    NSString *nonce = InsulationRemovalReadTrimmedString(InsulationRemovalMarkerPath());
    return nonce.length > 0 && InsulationRemovalNonceIsValid([nonce UTF8String]);
}

BOOL InsulationRemovalInitializeFromMarker(void) {
    BOOL markerPresent = InsulationRemovalCurrentMarkerIsValid();
    if (markerPresent) {
        atomic_store_explicit(&InsulationRemovalDisabled, true, memory_order_release);
    }
    return markerPresent;
}

BOOL InsulationRemovalIsDisabled(void) {
    return atomic_load_explicit(&InsulationRemovalDisabled, memory_order_acquire);
}

void InsulationRemovalLatchDisabled(void) {
    atomic_store_explicit(&InsulationRemovalDisabled, true, memory_order_release);
}

BOOL InsulationRemovalAcknowledgeCurrentMarker(NSError **errorOut) {
    NSString *nonce = InsulationRemovalReadTrimmedString(InsulationRemovalMarkerPath());
    if (nonce.length == 0 || !InsulationRemovalNonceIsValid([nonce UTF8String])) {
        if (errorOut) {
            *errorOut = InsulationRemovalError(4, @"removal marker is missing or invalid");
        }
        return NO;
    }

    NSString *acknowledgment = [NSString stringWithFormat:@"%@ %d\n", nonce, getpid()];
    if (!InsulationRemovalWriteStringAtomically(acknowledgment, InsulationRemovalAcknowledgmentPath(), errorOut)) {
        return NO;
    }

    (void)notify_post(INSULATION_REMOVAL_ACK_NOTIFICATION);
    return YES;
}

static BOOL InsulationRemovalReadAcknowledgedPID(NSString *nonce, int *pidOut) {
    NSString *acknowledgment = InsulationRemovalReadTrimmedString(InsulationRemovalAcknowledgmentPath());
    if (!acknowledgment) {
        return NO;
    }
    return InsulationRemovalParseAcknowledgment([acknowledgment UTF8String], [nonce UTF8String], pidOut);
}

static BOOL InsulationRemovalWaitForAcknowledgment(NSString *nonce, int notifyToken, int *pidOut) {
    NSTimeInterval deadline = [NSDate timeIntervalSinceReferenceDate] + InsulationRemovalAcknowledgeTimeout;
    NSUInteger pollCount = 0;
    while ([NSDate timeIntervalSinceReferenceDate] < deadline) {
        int changed = 0;
        (void)notify_check(notifyToken, &changed);
        if (InsulationRemovalReadAcknowledgedPID(nonce, pidOut)) {
            return YES;
        }
        pollCount += 1;
        if (pollCount == 10 || pollCount == 30 || pollCount == 60) {
            (void)notify_post(INSULATION_REMOVAL_PREPARE_NOTIFICATION);
        }
        usleep(InsulationRemovalPollIntervalMicroseconds);
    }
    return NO;
}

static BOOL InsulationRemovalWaitForPIDExit(int pid) {
    NSTimeInterval deadline = [NSDate timeIntervalSinceReferenceDate] + InsulationRemovalExitTimeout;
    while ([NSDate timeIntervalSinceReferenceDate] < deadline) {
        if (kill(pid, 0) != 0 && errno == ESRCH) {
            return YES;
        }
        usleep(InsulationRemovalPollIntervalMicroseconds);
    }
    return kill(pid, 0) != 0 && errno == ESRCH;
}

BOOL InsulationRemovalPrepareAndWait(NSError **errorOut) {
    NSString *nonce = [[NSUUID UUID] UUIDString];
    NSError *removeError = nil;
    if (!InsulationRemovalRemoveFileIfPresent(InsulationRemovalAcknowledgmentPath(), &removeError)) {
        if (errorOut) {
            *errorOut = removeError;
        }
        return NO;
    }
    if (!InsulationRemovalWriteStringAtomically([nonce stringByAppendingString:@"\n"], InsulationRemovalMarkerPath(), errorOut)) {
        return NO;
    }

    int notifyToken = 0;
    int registerStatus = notify_register_check(INSULATION_REMOVAL_ACK_NOTIFICATION, &notifyToken);
    if (registerStatus != NOTIFY_STATUS_OK) {
        if (errorOut) {
            *errorOut = InsulationRemovalError(5, [NSString stringWithFormat:@"ack registration failed: %d", registerStatus]);
        }
        return NO;
    }

    int postStatus = notify_post(INSULATION_REMOVAL_PREPARE_NOTIFICATION);
    if (postStatus != NOTIFY_STATUS_OK) {
        notify_cancel(notifyToken);
        if (errorOut) {
            *errorOut = InsulationRemovalError(6, [NSString stringWithFormat:@"prepare notification failed: %d", postStatus]);
        }
        return NO;
    }

    int daemonPID = 0;
    BOOL acknowledged = InsulationRemovalWaitForAcknowledgment(nonce, notifyToken, &daemonPID);
    notify_cancel(notifyToken);
    if (!acknowledged) {
        if (errorOut) {
            *errorOut = InsulationRemovalError(7, @"timed out waiting for daemon removal acknowledgment");
        }
        return NO;
    }
    if (!InsulationRemovalWaitForPIDExit(daemonPID)) {
        if (errorOut) {
            *errorOut = InsulationRemovalError(8, [NSString stringWithFormat:@"acknowledged daemon pid %d did not exit", daemonPID]);
        }
        return NO;
    }
    return YES;
}

BOOL InsulationRemovalClearMarker(NSError **errorOut) {
    NSError *ackError = nil;
    if (!InsulationRemovalRemoveFileIfPresent(InsulationRemovalAcknowledgmentPath(), &ackError)) {
        if (errorOut) {
            *errorOut = ackError;
        }
        return NO;
    }
    return InsulationRemovalRemoveFileIfPresent(InsulationRemovalMarkerPath(), errorOut);
}
