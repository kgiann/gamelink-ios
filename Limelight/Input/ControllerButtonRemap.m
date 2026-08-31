//
//  ControllerButtonRemap.m
//  Moonlight
//

#import "ControllerButtonRemap.h"
#include "Limelight.h"

// NSUserDefaults key holding a dictionary of controllerKey -> (sourceFlagString -> targetFlagNumber)
static NSString* const kMappingsDefaultsKey = @"GLControllerMappings";

@implementation ControllerButtonRemap

+ (NSArray<NSDictionary *> *)remappableButtons {
    static NSArray* buttons;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        buttons = @[
            @{@"flag": @(A_FLAG),        @"name": @"A"},
            @{@"flag": @(B_FLAG),        @"name": @"B"},
            @{@"flag": @(X_FLAG),        @"name": @"X"},
            @{@"flag": @(Y_FLAG),        @"name": @"Y"},
            @{@"flag": @(UP_FLAG),       @"name": @"D-Pad Up"},
            @{@"flag": @(DOWN_FLAG),     @"name": @"D-Pad Down"},
            @{@"flag": @(LEFT_FLAG),     @"name": @"D-Pad Left"},
            @{@"flag": @(RIGHT_FLAG),    @"name": @"D-Pad Right"},
            @{@"flag": @(LB_FLAG),       @"name": @"Left Shoulder (LB)"},
            @{@"flag": @(RB_FLAG),       @"name": @"Right Shoulder (RB)"},
            @{@"flag": @(LS_CLK_FLAG),   @"name": @"Left Stick (L3)"},
            @{@"flag": @(RS_CLK_FLAG),   @"name": @"Right Stick (R3)"},
            @{@"flag": @(BACK_FLAG),     @"name": @"Back / Select"},
            @{@"flag": @(PLAY_FLAG),     @"name": @"Start"},
            @{@"flag": @(MISC_FLAG),     @"name": @"Guide / Home"},
            @{@"flag": @(SPECIAL_FLAG),  @"name": @"Share / Capture"},
            @{@"flag": @(PADDLE1_FLAG),  @"name": @"Paddle P1"},
            @{@"flag": @(PADDLE2_FLAG),  @"name": @"Paddle P2"},
            @{@"flag": @(PADDLE3_FLAG),  @"name": @"Paddle P3"},
            @{@"flag": @(PADDLE4_FLAG),  @"name": @"Paddle P4"},
            @{@"flag": @(TOUCHPAD_FLAG), @"name": @"Touchpad Button"},
        ];
    });
    return buttons;
}

+ (NSArray<NSDictionary *> *)targetButtons {
    static NSArray* targets;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray* t = [[self remappableButtons] mutableCopy];
        [t addObject:@{@"flag": @(0), @"name": @"None (disabled)"}];
        targets = t;
    });
    return targets;
}

+ (NSString *)nameForFlag:(int)flag {
    for (NSDictionary* b in [self targetButtons]) {
        if ([b[@"flag"] intValue] == flag) {
            return b[@"name"];
        }
    }
    return @"Unknown";
}

+ (NSString *)keyForGamepad:(GCController *)controller {
    NSString* vendor = controller.vendorName ?: @"Controller";
    NSString* category = @"";
    if (@available(iOS 14.0, tvOS 14.0, *)) {
        category = controller.productCategory ?: @"";
    }
    return [NSString stringWithFormat:@"%@|%@", vendor, category];
}

+ (NSDictionary<NSNumber *, NSNumber *> *)mappingForControllerKey:(NSString *)key {
    if (key == nil) {
        return @{};
    }

    NSDictionary* all = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kMappingsDefaultsKey];
    NSDictionary* stored = all[key];
    if (![stored isKindOfClass:[NSDictionary class]]) {
        return @{};
    }

    NSMutableDictionary<NSNumber *, NSNumber *>* result = [NSMutableDictionary dictionary];
    for (NSString* srcStr in stored) {
        NSNumber* tgt = stored[srcStr];
        if (![tgt isKindOfClass:[NSNumber class]]) {
            continue;
        }
        result[@([srcStr intValue])] = @(tgt.intValue);
    }
    return result;
}

+ (void)saveMapping:(NSDictionary<NSNumber *, NSNumber *> *)mapping
   forControllerKey:(NSString *)key {
    if (key == nil) {
        return;
    }

    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary* all = [[defaults dictionaryForKey:kMappingsDefaultsKey] mutableCopy];
    if (all == nil) {
        all = [NSMutableDictionary dictionary];
    }

    // Strip identity entries; persist as string keys / number values for plist safety.
    NSMutableDictionary* stored = [NSMutableDictionary dictionary];
    for (NSNumber* src in mapping) {
        NSNumber* tgt = mapping[src];
        if (tgt.intValue == src.intValue) {
            continue; // identity, no need to store
        }
        stored[[src stringValue]] = @(tgt.intValue);
    }

    if (stored.count == 0) {
        [all removeObjectForKey:key];
    } else {
        all[key] = stored;
    }

    [defaults setObject:all forKey:kMappingsDefaultsKey];
}

+ (void)clearMappingForControllerKey:(NSString *)key {
    [self saveMapping:@{} forControllerKey:key];
}

+ (NSArray<NSString *> *)savedControllerKeys {
    NSDictionary* all = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kMappingsDefaultsKey];
    return all.allKeys ?: @[];
}

@end
