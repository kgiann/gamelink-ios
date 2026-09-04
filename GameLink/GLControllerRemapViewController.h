//
//  GLControllerRemapViewController.h
//  GameLink
//
//  Grouped-list remapping screen for a single controller model. Each physical
//  button is a row showing its current target; tapping picks a new target.
//

#import <UIKit/UIKit.h>

@interface GLControllerRemapViewController : UITableViewController

- (instancetype)initWithControllerKey:(NSString *)key displayName:(NSString *)name;

@end
