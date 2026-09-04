//
//  ControllerButtonRemap.h
//  Moonlight
//
//  Per-controller button remapping storage shared between the input pipeline
//  (ControllerSupport) and the GameLink remapping UI.
//

#import <Foundation/Foundation.h>
@import GameController;

NS_ASSUME_NONNULL_BEGIN

@interface ControllerButtonRemap : NSObject

// Ordered list of remappable physical buttons.
// Each entry: @{ @"flag": NSNumber(int), @"name": NSString }
+ (NSArray<NSDictionary *> *)remappableButtons;

// Ordered list of targets a button can be mapped to
// (all remappable buttons + Guide + "None").
+ (NSArray<NSDictionary *> *)targetButtons;

// Human-readable name for a flag value (0 == "None").
+ (NSString *)nameForFlag:(int)flag;

// Stable identity for a gamepad (vendor name + product category).
+ (NSString *)keyForGamepad:(GCController *)controller;

// Loads the saved source-flag -> target-flag mapping for a controller key.
// Returns an empty dictionary (identity) if nothing is saved. Only
// non-identity entries are present.
+ (NSDictionary<NSNumber *, NSNumber *> *)mappingForControllerKey:(NSString *)key;

// Persists a mapping. Identity entries are stripped before saving.
+ (void)saveMapping:(NSDictionary<NSNumber *, NSNumber *> *)mapping
   forControllerKey:(NSString *)key;

// Removes any saved mapping for a controller key.
+ (void)clearMappingForControllerKey:(NSString *)key;

// All controller keys that currently have a saved mapping.
+ (NSArray<NSString *> *)savedControllerKeys;

@end

NS_ASSUME_NONNULL_END
