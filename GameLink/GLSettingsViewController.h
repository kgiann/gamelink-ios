//
//  GLSettingsViewController.h
//  GameLink
//

#import <UIKit/UIKit.h>

@protocol GLSettingsDelegate <NSObject>
- (void)settingsDidSave;
@end

@interface GLSettingsViewController : UIViewController

@property (weak, nonatomic) id<GLSettingsDelegate> delegate;

@end
