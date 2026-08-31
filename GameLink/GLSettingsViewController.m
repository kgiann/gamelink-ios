#import "GLSettingsViewController.h"
#import "GLConnectionSettingsViewController.h"
#import "GLControllerListViewController.h"

@implementation GLSettingsViewController {
    GLConnectionSettingsViewController *_connectionVC;
    GLControllerListViewController *_mappingVC;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
#if TARGET_OS_TV
    self.view.backgroundColor = [UIColor blackColor];
#else
    self.view.backgroundColor = [UIColor systemBackgroundColor];
#endif
    
    self.navigationItem.title = @"Settings";
    
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:@"Save"
                style:UIBarButtonItemStyleDone
               target:self
               action:@selector(saveAndDismiss)];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:@"Cancel"
                style:UIBarButtonItemStylePlain
               target:self
               action:@selector(cancel)];
    
    // First tab: Connection (GLSettingsViewController)
    _connectionVC = [[GLConnectionSettingsViewController alloc] init];
    _connectionVC.title = @"Connection";
    self.navigationController.tabBarItem = [[UITabBarItem alloc] initWithTitle:_connectionVC.title image:[UIImage systemImageNamed:@"gearshape"] selectedImage:[UIImage systemImageNamed:@"gearshape.fill"]];
    
    // Second tab: Button Mapping (GLControllerListViewController)
    _mappingVC = [[GLControllerListViewController alloc] init];
    _mappingVC.title = @"Button Mapping";
    self.navigationController.tabBarItem = [[UITabBarItem alloc] initWithTitle:_mappingVC.title image:[UIImage systemImageNamed:@"gamecontroller"] selectedImage:[UIImage systemImageNamed:@"gamecontroller.fill"]];
    
    self.viewControllers = @[ _connectionVC, _mappingVC ];
}

- (void)saveAndDismiss {
    [_connectionVC save];

    [self dismissViewControllerAnimated:YES completion:^{
        [self.delegate settingsDidSave];
    }];
}

- (void)cancel {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
