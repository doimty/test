#import "InsulationProbe.h"

#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import "../insulationC/include/Tweak.h"

static NSString *InsulationProbePath(void) {
    return rootlessPath(@"/var/mobile/Library/Preferences/com.be-huge.insulation-probe.plist");
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
        state[@"version"] = @"0.1.36.3-probe";
        state[@"pid"] = @((int)[[NSProcessInfo processInfo] processIdentifier]);
        state[@"processStart"] = @([[NSDate date] timeIntervalSince1970]);
        state[@"events"] = [NSMutableDictionary dictionary];
        state[@"setters"] = [NSMutableDictionary dictionary];
        state[@"updates"] = [NSMutableDictionary dictionary];
    });
    return state;
}

static void InsulationProbeWrite(NSMutableDictionary *state) {
    NSString *path = InsulationProbePath();
    [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent]
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    state[@"lastWrite"] = @([[NSDate date] timeIntervalSince1970]);
    [state writeToFile:path atomically:YES];
}

static void InsulationProbeBump(NSMutableDictionary *dict, NSString *key) {
    NSNumber *old = dict[key];
    dict[key] = @([old integerValue] + 1);
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

void InsulationProbeRecordApply(NSString *mode, BOOL bootGuardActive) {
    dispatch_async(InsulationProbeQueue(), ^{
        NSMutableDictionary *state = InsulationProbeState();
        NSMutableDictionary *events = state[@"events"];
        InsulationProbeBump(events, @"apply");
        state[@"lastApply"] = @{
            @"time": @([[NSDate date] timeIntervalSince1970]),
            @"mode": mode ?: @"unknown",
            @"bootGuardActive": @(bootGuardActive),
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

void InsulationProbeRecordSetter(NSString *name, NSInteger originalValue, NSInteger patchedValue) {
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
        state[@"lastSetter"] = @{
            @"time": @([[NSDate date] timeIntervalSince1970]),
            @"name": name,
            @"original": @(originalValue),
            @"patched": @(patchedValue),
        };
        InsulationProbeWrite(state);
    });
}
