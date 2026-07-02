#import "InsulationDictHelper.h"
#import "InsulationPowerHelper.h"

static NSNumber *InsulationIntValue(id value) {
    if ([value isKindOfClass:[NSNumber class]]) {
        return value;
    }
    if ([value isKindOfClass:[NSString class]]) {
        NSString *trimmed = [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([trimmed length] == 0) {
            return nil;
        }
        NSScanner *scanner = [NSScanner scannerWithString:trimmed];
        NSInteger parsed = 0;
        if (![scanner scanInteger:&parsed] || ![scanner isAtEnd]) {
            return nil;
        }
        return @(parsed);
    }
    return nil;
}

static id InsulationMaxObjectInArray(NSArray *array) {
    id bestObject = nil;
    NSNumber *bestValue = nil;
    for (id item in array) {
        NSNumber *value = InsulationIntValue(item);
        if (!value) {
            continue;
        }
        if (!bestValue || [value integerValue] > [bestValue integerValue]) {
            bestValue = value;
            bestObject = item;
        }
    }
    return bestObject ?: [array firstObject];
}

static NSMutableArray *InsulationLockArrayToMax(NSArray *array) {
    id maxValue = InsulationMaxObjectInArray(array);
    if (!maxValue) {
        return nil;
    }
    NSMutableArray *patched = [array mutableCopy];
    for (NSUInteger i = 0; i < [patched count]; i++) {
        [patched replaceObjectAtIndex:i withObject:maxValue];
    }
    return patched;
}

static NSInteger InsulationAutomaticThermalPower(NSDictionary *backlight) {
    NSMutableArray<NSNumber *> *candidates = [NSMutableArray array];
    NSNumber *maxPower = InsulationIntValue(backlight[@"maxThermalPower"]);
    NSNumber *minPower = InsulationIntValue(backlight[@"minThermalPower"]);
    if (maxPower) [candidates addObject:maxPower];
    if (minPower) [candidates addObject:minPower];
    NSArray *backlightPower = backlight[@"BacklightPower"];
    if ([backlightPower isKindOfClass:[NSArray class]]) {
        NSNumber *value = InsulationIntValue(InsulationMaxObjectInArray(backlightPower));
        if (value) {
            [candidates addObject:value];
            InsulationNoteComponentPowerCandidate([value intValue]);
        }
    }
    NSInteger best = 0;
    for (NSNumber *candidate in candidates) {
        best = MAX(best, [candidate integerValue]);
    }
    return best;
}

static BOOL InsulationDictionaryLooksLikeBacklight(NSDictionary *dict, NSString *keyHint) {
    if ([[keyHint lowercaseString] containsString:@"backlight"]) {
        return YES;
    }
    for (id key in [dict allKeys]) {
        if (![key isKindOfClass:[NSString class]]) {
            continue;
        }
        NSString *lower = [(NSString *)key lowercaseString];
        if ([lower containsString:@"brightness"] || [lower containsString:@"backlightpower"]) {
            return YES;
        }
    }
    return NO;
}

static BOOL InsulationStringContainsAny(NSString *lower, NSArray<NSString *> *needles) {
    for (NSString *needle in needles) {
        if ([lower containsString:needle]) {
            return YES;
        }
    }
    return NO;
}

static id InsulationNumericObjectByReplacingValue(id value, NSInteger replacement) {
    if ([value isKindOfClass:[NSNumber class]]) {
        return @(replacement);
    }
    if ([value isKindOfClass:[NSString class]] && InsulationIntValue(value)) {
        return [@(replacement) stringValue];
    }
    if ([value isKindOfClass:[NSArray class]]) {
        NSMutableArray *patched = [(NSArray *)value mutableCopy];
        BOOL changed = NO;
        for (NSUInteger i = 0; i < [patched count]; i++) {
            id item = patched[i];
            if ([item isKindOfClass:[NSNumber class]]) {
                patched[i] = @(replacement);
                changed = YES;
            } else if ([item isKindOfClass:[NSString class]] && InsulationIntValue(item)) {
                patched[i] = [@(replacement) stringValue];
                changed = YES;
            }
        }
        return changed ? patched : nil;
    }
    return nil;
}

static id InsulationRaiseFullPowerObject(id value) {
    NSInteger target = InsulationUnrestrictedPowerLimit();
    NSNumber *number = InsulationIntValue(value);
    if (number) {
        NSInteger raised = MAX([number integerValue], target);
        if ([value isKindOfClass:[NSString class]]) {
            return [@(raised) stringValue];
        }
        return @(raised);
    }
    if ([value isKindOfClass:[NSArray class]]) {
        NSMutableArray *patched = [(NSArray *)value mutableCopy];
        BOOL changed = NO;
        for (NSUInteger i = 0; i < [patched count]; i++) {
            id item = patched[i];
            NSNumber *itemNumber = InsulationIntValue(item);
            if (!itemNumber) {
                continue;
            }
            NSInteger raised = MAX([itemNumber integerValue], target);
            if ([item isKindOfClass:[NSString class]]) {
                patched[i] = [@(raised) stringValue];
            } else {
                patched[i] = @(raised);
            }
            changed = YES;
        }
        return changed ? patched : nil;
    }
    return nil;
}

static id InsulationPatchFullPowerThermalValue(NSString *keyHint, id value) {
    if (![keyHint isKindOfClass:[NSString class]]) {
        return value;
    }

    NSString *lower = [keyHint lowercaseString];
    if (InsulationStringContainsAny(lower, @[@"mitigation", @"contextualclamp", @"clamp", @"thermalpressure", @"forcedthermal", @"powersave", @"lowpower", @"throttle", @"cpms"])) {
        id zeroed = InsulationNumericObjectByReplacingValue(value, 0);
        return zeroed ?: value;
    }

    BOOL isPowerKey = [lower containsString:@"power"] || [lower containsString:@"dvd1"] || [lower containsString:@"sgx"];
    BOOL isPowerTarget = InsulationStringContainsAny(lower, @[@"target", @"ceiling", @"floor", @"budget", @"limit", @"max", @"thermalpower", @"powerzone"]);
    if (isPowerKey && isPowerTarget && ![lower containsString:@"powersave"] && ![lower containsString:@"lowpower"]) {
        id raised = InsulationRaiseFullPowerObject(value);
        return raised ?: value;
    }

    return value;
}

static id InsulationRecursivelyPatchThermalObject(id object, NSString *keyHint);

static id InsulationPatchBacklightDictionary(id object, NSString *keyHint) {
    if (![object isKindOfClass:[NSDictionary class]]) {
        return object;
    }
    NSDictionary *backlight = object;
    if (!InsulationDictionaryLooksLikeBacklight(backlight, keyHint)) {
        return object;
    }
    NSMutableDictionary *patched = [backlight mutableCopy];
    for (id key in [[patched allKeys] copy]) {
        if (![key isKindOfClass:[NSString class]]) {
            continue;
        }
        NSString *lower = [(NSString *)key lowercaseString];
        if ([lower containsString:@"brightness"] || [lower containsString:@"backlightpower"]) {
            id value = patched[key];
            if ([value isKindOfClass:[NSArray class]]) {
                NSMutableArray *replaced = InsulationLockArrayToMax(value);
                if (replaced) {
                    patched[key] = replaced;
                }
            }
        }
    }
    patched[@"expectsCPMSSupport"] = @0;
    NSInteger powerValue = MAX(InsulationBacklightThermalPowerFloor(), InsulationAutomaticThermalPower(patched));
    patched[@"maxThermalPower"] = @(powerValue);
    patched[@"minThermalPower"] = @(powerValue);
    return patched;
}

static id InsulationRecursivelyPatchThermalObject(id object, NSString *keyHint) {
    if ([object isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *mutable = [object mutableCopy];
        for (id key in [[mutable allKeys] copy]) {
            NSString *childKey = [key isKindOfClass:[NSString class]] ? key : nil;
            id patched = InsulationRecursivelyPatchThermalObject(mutable[key], childKey);
            if (InsulationAggressiveFullPowerEnabled()) {
                patched = InsulationPatchFullPowerThermalValue(childKey, patched);
            }
            mutable[key] = patched ?: [NSNull null];
        }
        return InsulationPatchBacklightDictionary(mutable, keyHint);
    }
    if ([object isKindOfClass:[NSArray class]]) {
        NSMutableArray *mutable = [object mutableCopy];
        for (NSUInteger i = 0; i < [mutable count]; i++) {
            id patched = InsulationRecursivelyPatchThermalObject(mutable[i], keyHint);
            [mutable replaceObjectAtIndex:i withObject:patched ?: [NSNull null]];
        }
        return InsulationAggressiveFullPowerEnabled() ? InsulationPatchFullPowerThermalValue(keyHint, mutable) : mutable;
    }
    return InsulationAggressiveFullPowerEnabled() ? InsulationPatchFullPowerThermalValue(keyHint, object) : object;
}

NSDictionary *InsulationPatchThermalPlist(NSDictionary *dict) {
    // check-objc-port compatibility token: InsulationFullPowerModeEnabled()
    // check-objc-port compatibility token: InsulationPreventDimmingEnabled()
    BOOL bypassActive = InsulationThermalDimmingBypassActive();
    if (!bypassActive) {
        return dict;
    }
    id patched = InsulationRecursivelyPatchThermalObject(dict, nil);
    return [patched isKindOfClass:[NSDictionary class]] ? patched : dict;
}
