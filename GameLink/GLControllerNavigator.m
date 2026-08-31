//
//  GLControllerNavigator.m
//  GameLink
//

#import "GLControllerNavigator.h"
#import "ControllerButtonRemap.h"

#include "Limelight.h"
@import GameController;

// Threshold / release points for using the left stick as a d-pad.
static const float kStickPress = 0.6f;
static const float kStickRelease = 0.35f;

@implementation GLControllerNavigator {
    NSString* _key;
    GCController* _controller;
    id _connectObserver;
    id _disconnectObserver;

    int _prevButtons;   // raw pressed bitmask from the last event
    int _prevStickDir;  // -1 up, 0 centre, +1 down
}

- (instancetype)initWithControllerKey:(NSString *)key {
    self = [super init];
    if (self) {
        _key = [key copy];
    }
    return self;
}

- (BOOL)hasController {
    return _controller != nil;
}

#pragma mark - Attach / detach

- (void)attach {
    __weak GLControllerNavigator* weakSelf = self;
    _connectObserver = [[NSNotificationCenter defaultCenter]
        addObserverForName:GCControllerDidConnectNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification* note) {
                    [weakSelf bindIfNeeded];
                }];
    _disconnectObserver = [[NSNotificationCenter defaultCenter]
        addObserverForName:GCControllerDidDisconnectNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification* note) {
                    if (note.object == weakSelf.controllerObject) {
                        [weakSelf unbind];
                        [weakSelf bindIfNeeded];
                    }
                }];
    [self bindIfNeeded];
}

- (void)detach {
    if (_connectObserver) {
        [[NSNotificationCenter defaultCenter] removeObserver:_connectObserver];
        _connectObserver = nil;
    }
    if (_disconnectObserver) {
        [[NSNotificationCenter defaultCenter] removeObserver:_disconnectObserver];
        _disconnectObserver = nil;
    }
    [self unbind];
}

// Exposed only so the disconnect observer can compare identities.
- (GCController*)controllerObject {
    return _controller;
}

- (GCController*)findController {
    NSArray<GCController*>* controllers = [GCController controllers];

    // Prefer a controller whose key matches the one being edited
    if (_key != nil) {
        for (GCController* c in controllers) {
            if (c.extendedGamepad != nil &&
                [[ControllerButtonRemap keyForGamepad:c] isEqualToString:_key]) {
                return c;
            }
        }
    }

    // Otherwise the first supported controller
    for (GCController* c in controllers) {
        if (c.extendedGamepad != nil) {
            return c;
        }
    }
    return nil;
}

- (void)bindIfNeeded {
    if (_controller != nil) {
        return;
    }
    GCController* controller = [self findController];
    if (controller == nil) {
        return;
    }

    _controller = controller;
    _prevButtons = 0;
    _prevStickDir = 0;

    __weak GLControllerNavigator* weakSelf = self;
    controller.extendedGamepad.valueChangedHandler =
        ^(GCExtendedGamepad* gamepad, GCControllerElement* element) {
            [weakSelf handleGamepad:gamepad];
        };
}

- (void)unbind {
    if (_controller != nil) {
        _controller.extendedGamepad.valueChangedHandler = nil;
        _controller = nil;
    }
    _prevButtons = 0;
    _prevStickDir = 0;
}

#pragma mark - Input handling

// Build a raw (unmapped) Limelight button bitmask from the current gamepad state.
- (int)pressedButtonsFor:(GCExtendedGamepad*)g {
    int mask = 0;
    if (g.buttonA.pressed)        mask |= A_FLAG;
    if (g.buttonB.pressed)        mask |= B_FLAG;
    if (g.buttonX.pressed)        mask |= X_FLAG;
    if (g.buttonY.pressed)        mask |= Y_FLAG;
    if (g.dpad.up.pressed)        mask |= UP_FLAG;
    if (g.dpad.down.pressed)      mask |= DOWN_FLAG;
    if (g.dpad.left.pressed)      mask |= LEFT_FLAG;
    if (g.dpad.right.pressed)     mask |= RIGHT_FLAG;
    if (g.leftShoulder.pressed)   mask |= LB_FLAG;
    if (g.rightShoulder.pressed)  mask |= RB_FLAG;
    if (@available(iOS 12.1, tvOS 12.1, *)) {
        if (g.leftThumbstickButton.pressed)  mask |= LS_CLK_FLAG;
        if (g.rightThumbstickButton.pressed) mask |= RS_CLK_FLAG;
    }
    if (@available(iOS 13.0, tvOS 13.0, *)) {
        if (g.buttonOptions.pressed) mask |= BACK_FLAG;
        if (g.buttonMenu.pressed)    mask |= PLAY_FLAG;
    }
    if (@available(iOS 14.0, tvOS 14.0, *)) {
        if (g.buttonHome.pressed) mask |= MISC_FLAG;

        // Extended buttons exposed only through the physical input profile.
        GCPhysicalInputProfile* profile = g.controller.physicalInputProfile;
        if (profile.buttons[GCInputXboxPaddleOne].pressed)   mask |= PADDLE1_FLAG;
        if (profile.buttons[GCInputXboxPaddleTwo].pressed)   mask |= PADDLE2_FLAG;
        if (profile.buttons[GCInputXboxPaddleThree].pressed) mask |= PADDLE3_FLAG;
        if (profile.buttons[GCInputXboxPaddleFour].pressed)  mask |= PADDLE4_FLAG;
        if (profile.buttons[GCInputDualShockTouchpadButton].pressed) mask |= TOUCHPAD_FLAG;
        if (@available(iOS 15.0, tvOS 15.0, *)) {
            if (profile.buttons[GCInputButtonShare].pressed) mask |= SPECIAL_FLAG;
        }
    }
    return mask;
}

- (void)handleGamepad:(GCExtendedGamepad*)g {
    int buttons = [self pressedButtonsFor:g];
    int rising = buttons & ~_prevButtons;

    // Left stick emulates the d-pad for navigation, with hysteresis.
    float y = g.leftThumbstick.yAxis.value;
    int stickDir = _prevStickDir;
    if (y > kStickPress)        stickDir = -1; // up
    else if (y < -kStickPress)  stickDir = 1;  // down
    else if (fabsf(y) < kStickRelease) stickDir = 0;
    int stickEdge = (stickDir != _prevStickDir && stickDir != 0) ? stickDir : 0;

    _prevButtons = buttons;
    _prevStickDir = stickDir;

    if (self.captureMode) {
        if (rising != 0) {
            int flag = [self firstMappableFlagIn:rising];
            if (flag != 0 || (rising & MISC_FLAG)) {
                [self dispatch:^(id<GLControllerNavigatorDelegate> d) {
                    [d navigatorCapturedFlag:flag];
                }];
            }
        }
        return;
    }

    // Navigation mode
    if ((rising & UP_FLAG) || stickEdge == -1) {
        [self dispatch:^(id<GLControllerNavigatorDelegate> d) { [d navigatorMove:-1]; }];
    }
    else if ((rising & DOWN_FLAG) || stickEdge == 1) {
        [self dispatch:^(id<GLControllerNavigatorDelegate> d) { [d navigatorMove:1]; }];
    }

    if (rising & A_FLAG) {
        [self dispatch:^(id<GLControllerNavigatorDelegate> d) { [d navigatorConfirm]; }];
    }
    else if (rising & B_FLAG) {
        [self dispatch:^(id<GLControllerNavigatorDelegate> d) { [d navigatorCancel]; }];
    }
}

// Return the first remappable flag present in the mask (deterministic order).
- (int)firstMappableFlagIn:(int)mask {
    for (NSDictionary* button in [ControllerButtonRemap remappableButtons]) {
        int flag = [button[@"flag"] intValue];
        if (mask & flag) {
            return flag;
        }
    }
    return 0;
}

- (void)dispatch:(void (^)(id<GLControllerNavigatorDelegate>))block {
    id<GLControllerNavigatorDelegate> delegate = self.delegate;
    if (delegate == nil) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        block(delegate);
    });
}

@end
