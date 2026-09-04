#import "GLSettingsViewController.h"
#import "GLConnectionSettingsViewController.h"
#import "GLControllerListViewController.h"

@implementation GLSettingsViewController {
    GLConnectionSettingsViewController *_connectionVC;
    GLControllerListViewController *_mappingVC;
    BOOL _dismissing;
}

- (void)viewDidLoad {
    [super viewDidLoad];

#if TARGET_OS_TV
    self.view.backgroundColor = [UIColor blackColor];
#else
    self.view.backgroundColor = [UIColor systemBackgroundColor];
#endif

    self.navigationItem.title = @"Settings";

    // Settings are saved automatically on dismiss, so there's just a Done button.
#if !TARGET_OS_TV
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                             target:self
                             action:@selector(done)];
#endif

    // First tab: Connection
    _connectionVC = [[GLConnectionSettingsViewController alloc] init];
    _connectionVC.title = @"Connection";
    self.navigationController.tabBarItem = [[UITabBarItem alloc] initWithTitle:_connectionVC.title image:[UIImage systemImageNamed:@"gearshape"] selectedImage:[UIImage systemImageNamed:@"gearshape.fill"]];

    // Second tab: Button Mapping
    _mappingVC = [[GLControllerListViewController alloc] init];
    _mappingVC.title = @"Button Mapping";
    self.navigationController.tabBarItem = [[UITabBarItem alloc] initWithTitle:_mappingVC.title image:[UIImage systemImageNamed:@"gamecontroller"] selectedImage:[UIImage systemImageNamed:@"gamecontroller.fill"]];

    self.viewControllers = @[ _connectionVC, _mappingVC ];
}

- (void)done {
    [self dismissViewControllerAnimated:YES completion:nil];
}

// Persist on any dismissal (Done button, or the tvOS Menu/Back button). We're
// presented as the root of a navigation controller, so on tvOS it's the nav
// controller that gets dismissed -- our own isBeingDismissed stays NO. Check both.
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (self.isBeingDismissed || self.navigationController.isBeingDismissed) {
        _dismissing = YES;
        [_connectionVC save];
    }
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    if (_dismissing) {
        _dismissing = NO;
        [self.delegate settingsDidSave];
    }
}

@end
