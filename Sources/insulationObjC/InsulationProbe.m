#define INSULATION_PROBE_IMPLEMENTATION 1
#import "InsulationProbe.h"

#if INSULATION_PROBE_ENABLED

#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import "../insulationC/include/Tweak.h"

static NSString *InsulationProbePath(void) {
    return rootlessPath(@"/var/mobile/Library/Preferences/com.be-huge.insulation-decision-probe.plist");
}

static NSArray<NSString *> *InsulationProbePaths(void) {
    NSString *primary = InsulationProbePath();
    NSString *rawMobile = @"/var/mobile/Library/Preferences/com.be-huge.insulation-decision-probe.plist";
    NSString *tmp = @"/tmp/com.be-huge.insulation-decision-probe.plist";
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    for (NSString *path in @[primary, rawMobile, tmp]) {
        if ([path isKindOfClass:[NSString class]] && [path length] > 0 && ![paths containsObject:path]) {
            [paths addObject:path];
        }
    }
    return paths;
}

static dispatch_queue_t InsulationProbeQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.be-huge.insulation.decision-probe", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

static BOOL InsulationProbeFlushScheduled;
static NSUInteger InsulationProbeWriteCount;
static const NSTimeInterval InsulationProbeFlushDelay = 0.5;

static NSMutableDictionary *InsulationProbeState(void) {
    static NSMutableDictionary *state;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        state = [NSMutableDictionary dictionary];
        state[@"schemaVersion"] = @3;
        state[@"probeVersion"] = @"decision-pass-through-1";
        state[@"pid"] = @((int)[[NSProcessInfo processInfo] processIdentifier]);
        state[@"processStart"] = @([[NSDate date] timeIntervalSince1970]);
        state[@"events"] = [NSMutableDictionary dictionary];
        state[@"setters"] = [NSMutableDictionary dictionary];
        state[@"updates"] = [NSMutableDictionary dictionary];
        state[@"writeStatus"] = @"notAttempted";
        state[@"flushDelaySeconds"] = @(InsulationProbeFlushDelay);
    });
    return state;
}

static NSString *InsulationProbeWriteSnapshot(NSDictionary *snapshot, NSArray<NSString *> *paths) {
    NSError *serializationError = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:snapshot
                                                               format:NSPropertyListBinaryFormat_v1_0
                                                              options:0
                                                                error:&serializationError];
    if (!data) {
        return nil;
    }

    for (NSString *path in paths) {
        NSError *writeError = nil;
        if ([data writeToFile:path options:NSDataWritingAtomic error:&writeError]) {
            return path;
        }
    }
    return nil;
}

static void InsulationProbeWrite(NSMutableDictionary *state) {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSArray<NSString *> *paths = InsulationProbePaths();
    state[@"lastWriteAttemptAt"] = @(now);
    state[@"writePaths"] = paths;
    state[@"writeStatus"] = @"attempted";
    state[@"writeCount"] = @(++InsulationProbeWriteCount);

    NSDictionary *snapshot = [state copy];
    NSString *writtenPath = InsulationProbeWriteSnapshot(snapshot, paths);
    if (writtenPath) {
        state[@"lastWritePath"] = writtenPath;
        state[@"lastWriteStatus"] = @"written";
    } else {
        state[@"lastWriteStatus"] = @"failed";
    }
}

static void InsulationProbeScheduleWrite(void) {
    if (InsulationProbeFlushScheduled) {
        return;
    }
    InsulationProbeFlushScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(InsulationProbeFlushDelay * NSEC_PER_SEC)),
                   InsulationProbeQueue(), ^{
        InsulationProbeFlushScheduled = NO;
        InsulationProbeWrite(InsulationProbeState());
    });
}

static void InsulationProbeBump(NSMutableDictionary *dict, NSString *key) {
    NSNumber *old = dict[key];
    dict[key] = @([old integerValue] + 1);
}

void InsulationProbeMarkLoaded(NSString *stage) {
    dispatch_sync(InsulationProbeQueue(), ^{
        NSMutableDictionary *state = InsulationProbeState();
        NSMutableDictionary *events = state[@"events"];
        InsulationProbeBump(events, @"constructor.loaded");
        if ([stage isKindOfClass:[NSString class]] && [stage length] > 0) {
            InsulationProbeBump(events, [@"constructor." stringByAppendingString:stage]);
            state[@"lastConstructorStage"] = stage;
        }
        state[@"loadedAt"] = @([[NSDate date] timeIntervalSince1970]);
        InsulationProbeScheduleWrite();
    });
}

void InsulationProbeEvent(NSString *event) {
    if (![event isKindOfClass:[NSString class]] || [event length] == 0) {
        return;
    }
    dispatch_async(InsulationProbeQueue(), ^{
        NSMutableDictionary *state = InsulationProbeState();
        NSMutableDictionary *events = state[@"events"];
        InsulationProbeBump(events, event);
        state[@"lastEvent"] = event;
        InsulationProbeScheduleWrite();
    });
}

void InsulationProbeRecordApply(NSString *mode, BOOL bootGuardActive, NSString *source) {
    dispatch_async(InsulationProbeQueue(), ^{
        NSMutableDictionary *state = InsulationProbeState();
        NSMutableDictionary *events = state[@"events"];
        NSString *safeSource = ([source isKindOfClass:[NSString class]] && [source length] > 0) ? source : @"unknown";
        InsulationProbeBump(events, @"apply");
        InsulationProbeBump(events, [@"apply.source." stringByAppendingString:safeSource]);
        state[@"lastApply"] = @{
            @"time": @([[NSDate date] timeIntervalSince1970]),
            @"mode": mode ?: @"unknown",
            @"bootGuardActive": @(bootGuardActive),
            @"source": safeSource,
        };
        InsulationProbeScheduleWrite();
    });
}

void InsulationProbeRecordMitigationUpdate(NSString *name, BOOL changed) {
    if (![name isKindOfClass:[NSString class]] || [name length] == 0) {
        return;
    }
    dispatch_async(InsulationProbeQueue(), ^{
        NSMutableDictionary *state = InsulationProbeState();
        NSMutableDictionary *updates = state[@"updates"];
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
        InsulationProbeBump(updates, name);
        InsulationProbeBump(updates, changed ? [name stringByAppendingString:@".changed"] : [name stringByAppendingString:@".same"]);
        NSString *statsKey = [name stringByAppendingString:@".stats"];
        NSMutableDictionary *stats = [updates[statsKey] isKindOfClass:[NSDictionary class]] ? [updates[statsKey] mutableCopy] : [NSMutableDictionary dictionary];
        stats[@"lastAt"] = @(now);
        stats[@"changedLast"] = @(changed);
        updates[statsKey] = stats;
        state[@"lastUpdate"] = @{
            @"time": @(now),
            @"name": name,
            @"changed": @(changed),
        };
        InsulationProbeScheduleWrite();
    });
}

void InsulationProbeRecordSelfHeal(NSString *reason) {
    dispatch_async(InsulationProbeQueue(), ^{
        NSMutableDictionary *state = InsulationProbeState();
        NSMutableDictionary *events = state[@"events"];
        InsulationProbeBump(events, @"selfHeal");
        if (reason) {
            InsulationProbeBump(events, [@"selfHeal." stringByAppendingString:reason]);
        }
        state[@"lastSelfHeal"] = @{
            @"time": @([[NSDate date] timeIntervalSince1970]),
            @"reason": reason ?: @"unknown",
        };
        InsulationProbeScheduleWrite();
    });
}

void InsulationProbeRecordSetterDetails(NSString *name, NSInteger originalValue, NSInteger patchedValue, NSDictionary *details) {
    if (![name isKindOfClass:[NSString class]] || [name length] == 0) {
        return;
    }
    dispatch_async(InsulationProbeQueue(), ^{
        NSMutableDictionary *state = InsulationProbeState();
        NSMutableDictionary *setters = state[@"setters"];
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
        InsulationProbeBump(setters, name);
        if (originalValue != patchedValue) {
            InsulationProbeBump(setters, [name stringByAppendingString:@".patched"]);
        }

        NSString *detailKey = [name stringByAppendingString:@".stats"];
        NSMutableDictionary *stats = [setters[detailKey] isKindOfClass:[NSDictionary class]] ? [setters[detailKey] mutableCopy] : [NSMutableDictionary dictionary];
        NSNumber *oldOriginalMin = stats[@"originalMin"];
        NSNumber *oldOriginalMax = stats[@"originalMax"];
        NSNumber *oldPatchedMin = stats[@"patchedMin"];
        NSNumber *oldPatchedMax = stats[@"patchedMax"];
        stats[@"lastAt"] = @(now);
        stats[@"lastOriginal"] = @(originalValue);
        stats[@"lastPatched"] = @(patchedValue);
        stats[@"originalMin"] = @((oldOriginalMin && [oldOriginalMin integerValue] < originalValue) ? [oldOriginalMin integerValue] : originalValue);
        stats[@"originalMax"] = @((oldOriginalMax && [oldOriginalMax integerValue] > originalValue) ? [oldOriginalMax integerValue] : originalValue);
        stats[@"patchedMin"] = @((oldPatchedMin && [oldPatchedMin integerValue] < patchedValue) ? [oldPatchedMin integerValue] : patchedValue);
        stats[@"patchedMax"] = @((oldPatchedMax && [oldPatchedMax integerValue] > patchedValue) ? [oldPatchedMax integerValue] : patchedValue);
        stats[@"changedLast"] = @(originalValue != patchedValue);
        NSInteger extremeTarget = 65000;
        if (originalValue > patchedValue) {
            InsulationProbeBump(stats, @"cappedBelowOriginalCount");
            NSInteger delta = originalValue - patchedValue;
            NSNumber *oldDelta = stats[@"cappedBelowOriginalMaxDelta"];
            stats[@"cappedBelowOriginalMaxDelta"] = @((oldDelta && [oldDelta integerValue] > delta) ? [oldDelta integerValue] : delta);
        }
        if (patchedValue > originalValue) {
            InsulationProbeBump(stats, @"raisedAboveOriginalCount");
            NSInteger delta = patchedValue - originalValue;
            NSNumber *oldDelta = stats[@"raisedAboveOriginalMaxDelta"];
            stats[@"raisedAboveOriginalMaxDelta"] = @((oldDelta && [oldDelta integerValue] > delta) ? [oldDelta integerValue] : delta);
        }
        if (patchedValue > 0 && patchedValue < extremeTarget) {
            InsulationProbeBump(stats, @"belowExtremeTargetCount");
            stats[@"lastBelowExtremeTarget"] = @(patchedValue);
        }
        setters[detailKey] = stats;

        NSMutableDictionary *record = [@{
            @"time": @(now),
            @"name": name,
            @"original": @(originalValue),
            @"patched": @(patchedValue),
        } mutableCopy];
        if ([details isKindOfClass:[NSDictionary class]] && [details count] > 0) {
            record[@"details"] = details;
        }
        state[@"lastSetter"] = record;
        InsulationProbeScheduleWrite();
    });
}

void InsulationProbeRecordSetter(NSString *name, NSInteger originalValue, NSInteger patchedValue) {
    InsulationProbeRecordSetterDetails(name, originalValue, patchedValue, nil);
}

void InsulationProbeRecordHookInstall(NSString *className, NSString *selectorName, BOOL installed) {
    if (![className isKindOfClass:[NSString class]] || ![selectorName isKindOfClass:[NSString class]] || [className length] == 0 || [selectorName length] == 0) {
        return;
    }
    dispatch_async(InsulationProbeQueue(), ^{
        NSMutableDictionary *state = InsulationProbeState();
        NSMutableDictionary *events = state[@"events"];
        NSMutableDictionary *hooks = state[@"hooks"];
        if (!hooks) {
            hooks = [NSMutableDictionary dictionary];
            state[@"hooks"] = hooks;
        }
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
        NSString *key = [NSString stringWithFormat:@"%@.%@", className, selectorName];
        InsulationProbeBump(events, installed ? @"hook.install.ok" : @"hook.install.missing");
        InsulationProbeBump(events, [NSString stringWithFormat:@"hook.install.%@.%@", installed ? @"ok" : @"missing", key]);
        hooks[key] = @{
            @"time": @(now),
            @"class": className,
            @"selector": selectorName,
            @"installed": @(installed),
        };
        state[@"lastHookInstall"] = hooks[key];
        InsulationProbeScheduleWrite();
    });
}

void InsulationProbeRecordMethodDump(NSString *className, NSArray *methods) {
    if (![className isKindOfClass:[NSString class]] || [className length] == 0 || ![methods isKindOfClass:[NSArray class]]) {
        return;
    }
    dispatch_async(InsulationProbeQueue(), ^{
        NSMutableDictionary *state = InsulationProbeState();
        NSMutableDictionary *dumps = state[@"methodDumps"];
        if (!dumps) {
            dumps = [NSMutableDictionary dictionary];
            state[@"methodDumps"] = dumps;
        }
        dumps[className] = methods;
        state[@"lastMethodDump"] = @{
            @"time": @([[NSDate date] timeIntervalSince1970]),
            @"class": className,
            @"count": @([methods count]),
        };
        InsulationProbeScheduleWrite();
    });
}

#else

void InsulationProbeMarkLoaded(NSString *stage) { (void)stage; }
void InsulationProbeEvent(NSString *event) { (void)event; }
void InsulationProbeRecordApply(NSString *mode, BOOL bootGuardActive, NSString *source) { (void)mode; (void)bootGuardActive; (void)source; }
void InsulationProbeRecordMitigationUpdate(NSString *name, BOOL changed) { (void)name; (void)changed; }
void InsulationProbeRecordSelfHeal(NSString *reason) { (void)reason; }
void InsulationProbeRecordSetter(NSString *name, NSInteger originalValue, NSInteger patchedValue) { (void)name; (void)originalValue; (void)patchedValue; }
void InsulationProbeRecordSetterDetails(NSString *name, NSInteger originalValue, NSInteger patchedValue, NSDictionary *details) { (void)name; (void)originalValue; (void)patchedValue; (void)details; }
void InsulationProbeRecordHookInstall(NSString *className, NSString *selectorName, BOOL installed) { (void)className; (void)selectorName; (void)installed; }
void InsulationProbeRecordMethodDump(NSString *className, NSArray *methods) { (void)className; (void)methods; }

#endif
