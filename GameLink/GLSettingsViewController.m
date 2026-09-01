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

#if TARGET_OS_TV
    [self setupTVActionButtons];
#endif
}

#if TARGET_OS_TV
// tvOS has no navigation bar over a tab bar controller, and nothing can sit above
// the system tab bar. The tab titles are centered, so place Cancel/Save flanking
// them at the top (top-leading / top-trailing) where they won't overlap.
- (void)setupTVActionButtons {
    UIButton* cancelButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [cancelButton setTitle:@"Cancel" forState:UIControlStateNormal];
    cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    [cancelButton addTarget:self action:@selector(cancel) forControlEvents:UIControlEventPrimaryActionTriggered];
    [self.view addSubview:cancelButton];

    UIButton* saveButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [saveButton setTitle:@"Save" forState:UIControlStateNormal];
    saveButton.translatesAutoresizingMaskIntoConstraints = NO;
    [saveButton addTarget:self action:@selector(saveAndDismiss) forControlEvents:UIControlEventPrimaryActionTriggered];
    [self.view addSubview:saveButton];

    UILayoutGuide* safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [cancelButton.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [cancelButton.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:40],

        [saveButton.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [saveButton.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-40],
    ]];
}
#endif

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
