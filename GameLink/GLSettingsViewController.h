#import <UIKit/UIKit.h>

@protocol GLSettingsDelegate <NSObject>
- (void)settingsDidSave;
@end

@interface GLSettingsViewController : UITabBarController

@property (weak, nonatomic) id<GLSettingsDelegate> delegate;

- (void)saveAndDismiss;
- (void)cancel;

@end
