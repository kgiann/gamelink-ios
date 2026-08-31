//
//  GLControllerNavigator.h
//  GameLink
//
//  Lets a physical game controller drive a settings screen: edge-detected
//  D-pad / left-stick navigation, A to confirm, B to cancel, plus a capture
//  mode that reports the flag of whatever button the user presses next.
//
//  iOS (unlike tvOS) does not route game controllers through the UIKit focus
//  engine, so we read the GCExtendedGamepad directly.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol GLControllerNavigatorDelegate <NSObject>
// delta: -1 to move up/previous, +1 to move down/next
- (void)navigatorMove:(int)delta;
- (void)navigatorConfirm;
- (void)navigatorCancel;
// Only fired while captureMode == YES. flag is a Limelight button flag.
- (void)navigatorCapturedFlag:(int)flag;
@end

@interface GLControllerNavigator : NSObject

@property (nonatomic, weak) id<GLControllerNavigatorDelegate> delegate;

// When YES, all navigation is suppressed and the next button press is reported
// via navigatorCapturedFlag:.
@property (nonatomic) BOOL captureMode;

// YES if a supported controller is currently attached.
@property (nonatomic, readonly) BOOL hasController;

// key: prefer a controller whose ControllerButtonRemap key matches; nil = first
// connected extended gamepad.
- (instancetype)initWithControllerKey:(nullable NSString *)key;

- (void)attach;
- (void)detach;

@end

NS_ASSUME_NONNULL_END
