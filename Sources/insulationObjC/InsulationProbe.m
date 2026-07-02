#import "InsulationProbe.h"

#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import "../insulationC/include/Tweak.h"

static NSString *InsulationProbePath(void) {
    return rootlessPath(@"/var/mobile/Library/Preferences/com.be-huge.insulation-probe.plist");
}

static NSArray<NSString *> *InsulationProbePaths(void) {
    NSString *primary = InsulationProbePath();
    NSString *rawMobile = @"/var/mobile/Library/Preferences/com.be-huge.insulation-probe.plist";
    NSString *tmp = @"/tmp/com.be-huge.insulation-probe.plist";
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
        queue = dispatch_queue_create("com.be-huge.insulation.probe", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

static NSMutableDictionary *InsulationProbeState(void) {
    static NSMutableDictionary *state;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        state = [NSMutableDictionary dictionary];
        state[@"version"] = @"0.1.36.10-probe16";
        state[@"pid"] = @((int)[[NSProcessInfo processInfo] processIdentifier]);
        state[@"processStart"] = @([[NSDate date] timeIntervalSince1970]);
        state[@"events"] = [NSMutableDictionary dictionary];
        state[@"setters"] = [NSMutableDictionary dictionary];
        state[@"updates"] = [NSMutableDictionary dictionary];
    });
    return state;
}

static void InsulationProbeWrite(NSMutableDictionary *state) {
    state[@"lastWrite"] = @([[NSDate date] timeIntervalSince1970]);
    state[@"primaryPath"] = InsulationProbePath();
    state[@"writePaths"] = InsulationProbePaths();
    NSDictionary *snapshot = [state copy];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *path in InsulationProbePaths()) {
        [fm createDirectoryAtPath:[path stringByDeletingLastPathComponent]
      withIntermediateDirectories:YES
                       attributes:nil
                            error:nil];
        [snapshot writeToFile:path atomically:YES];
    }
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
        InsulationProbeWrite(state);
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
        InsulationProbeWrite(state);
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
        InsulationProbeWrite(state);
    });
}

void InsulationProbeRecordMitigationUpdate(NSString *name, BOOL changed) {
    if (![name isKindOfClass:[NSString class]] || [name length] == 0) {
        return;
    }
    dispatch_async(InsulationProbeQueue(), ^{
        NSMutableDictionary *state = InsulationProbeState();
        NSMutableDictionary *updates = state[@"updates"];
        InsulationProbeBump(updates, name);
        InsulationProbeBump(updates, changed ? [name stringByAppendingString:@".changed"] : [name stringByAppendingString:@".same"]);
        state[@"lastUpdate"] = @{
            @"time": @([[NSDate date] timeIntervalSince1970]),
            @"name": name,
            @"changed": @(changed),
        };
        InsulationProbeWrite(state);
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
        InsulationProbeWrite(state);
    });
}

void InsulationProbeRecordSetterDetails(NSString *name, NSInteger originalValue, NSInteger patchedValue, NSDictionary *details) {
    if (![name isKindOfClass:[NSString class]] || [name length] == 0) {
        return;
    }
    dispatch_async(InsulationProbeQueue(), ^{
        NSMutableDictionary *state = InsulationProbeState();
        NSMutableDictionary *setters = state[@"setters"];
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
        stats[@"lastOriginal"] = @(originalValue);
        stats[@"lastPatched"] = @(patchedValue);
        stats[@"originalMin"] = @((oldOriginalMin && [oldOriginalMin integerValue] < originalValue) ? [oldOriginalMin integerValue] : originalValue);
        stats[@"originalMax"] = @((oldOriginalMax && [oldOriginalMax integerValue] > originalValue) ? [oldOriginalMax integerValue] : originalValue);
        stats[@"patchedMin"] = @((oldPatchedMin && [oldPatchedMin integerValue] < patchedValue) ? [oldPatchedMin integerValue] : patchedValue);
        stats[@"patchedMax"] = @((oldPatchedMax && [oldPatchedMax integerValue] > patchedValue) ? [oldPatchedMax integerValue] : patchedValue);
        stats[@"changedLast"] = @(originalValue != patchedValue);
        setters[detailKey] = stats;

        NSMutableDictionary *record = [@{
            @"time": @([[NSDate date] timeIntervalSince1970]),
            @"name": name,
            @"original": @(originalValue),
            @"patched": @(patchedValue),
        } mutableCopy];
        if ([details isKindOfClass:[NSDictionary class]] && [details count] > 0) {
            record[@"details"] = details;
        }
        state[@"lastSetter"] = record;
        InsulationProbeWrite(state);
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
        NSString *key = [NSString stringWithFormat:@"%@.%@", className, selectorName];
        InsulationProbeBump(events, installed ? @"hook.install.ok" : @"hook.install.missing");
        InsulationProbeBump(events, [NSString stringWithFormat:@"hook.install.%@.%@", installed ? @"ok" : @"missing", key]);
        state[@"lastHookInstall"] = @{
            @"time": @([[NSDate date] timeIntervalSince1970]),
            @"class": className,
            @"selector": selectorName,
            @"installed": @(installed),
        };
        InsulationProbeWrite(state);
    });
}

void InsulationProbeRecordMethodDump(NSString *className, NSArray<NSString *> *methods) {
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
        InsulationProbeWrite(state);
    });
}
