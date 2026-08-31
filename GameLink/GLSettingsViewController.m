//
//  GLSettingsViewController.m
//  GameLink
//

#import "GLSettingsViewController.h"
#import "GLControllerListViewController.h"
#import "DataManager.h"
#import "TemporarySettings.h"

#import <VideoToolbox/VideoToolbox.h>
#import <AVFoundation/AVFoundation.h>

NSString* const kGLHostAddress = @"GLHostAddress";
NSString* const kGLAppName = @"GLAppName";

// User-facing stream settings are persisted directly in NSUserDefaults (which is
// durable on both iOS and tvOS), rather than relying on the Core Data store.
NSString* const kGLWidth = @"GLWidth";
NSString* const kGLHeight = @"GLHeight";
NSString* const kGLFramerate = @"GLFramerate";
NSString* const kGLBitrate = @"GLBitrate";

static NSString* bitrateFormat = @"Bitrate: %.1f Mbps";
static const int bitrateTable[] = {
    500, 1000, 1500, 2000, 2500, 3000, 4000, 5000, 6000, 7000,
    8000, 9000, 10000, 12000, 15000, 18000, 20000, 30000, 40000,
    50000, 60000, 70000, 80000, 100000,
};

#if TARGET_OS_TV
// tvOS has no UISlider, so offer a set of preset bitrates instead.
static const int bitratePresets[] = {
    5000, 10000, 15000, 20000, 30000, 40000, 50000, 80000, 100000,
};
#endif

@implementation GLSettingsViewController {
    UITextField* _hostField;
    UITextField* _appNameField;
    UISegmentedControl* _resolutionSelector;
    UISegmentedControl* _framerateSelector;
#if TARGET_OS_TV
    UISegmentedControl* _bitratePresets;
#else
    UISlider* _bitrateSlider;
#endif
    UILabel* _bitrateLabel;
    NSInteger _bitrate;
    UIScrollView* _scrollView;
    UIActivityIndicatorView* _loadingSpinner;
}

- (void)viewDidLoad {
    [super viewDidLoad];
//    self.view.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.1 alpha:1.0];
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    self.navigationItem.title = @"Connection Settings";
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

    // Spinner shown while Core Data loads
    _loadingSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    _loadingSpinner.color = [UIColor whiteColor];
    _loadingSpinner.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_loadingSpinner];
    [NSLayoutConstraint activateConstraints:@[
        [_loadingSpinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_loadingSpinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    ]];
    [_loadingSpinner startAnimating];

    // Load settings on a background thread; build UI once ready
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        DataManager* dataMan = [[DataManager alloc] init];
        TemporarySettings* settings = [dataMan getSettings];
        NSString* hostAddress = [[NSUserDefaults standardUserDefaults] stringForKey:kGLHostAddress] ?: @"";
        NSString* appName = [[NSUserDefaults standardUserDefaults] stringForKey:kGLAppName] ?: @"";

        dispatch_async(dispatch_get_main_queue(), ^{
            [self->_loadingSpinner stopAnimating];
            [self->_loadingSpinner removeFromSuperview];
            [self buildUI];
            [self populateWithSettings:settings hostAddress:hostAddress appName:appName];
        });
    });
}

- (void)buildUI {
    // Scroll view pinned to safe area so notch/Dynamic Island don't obscure content
    _scrollView = [[UIScrollView alloc] init];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_scrollView];
    [NSLayoutConstraint activateConstraints:@[
        [_scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_scrollView.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],
    ]];

    // Cap content width at 600pt and center it
    CGFloat safeWidth = self.view.bounds.size.width
        - self.view.safeAreaInsets.left
        - self.view.safeAreaInsets.right;
    CGFloat maxContentWidth = safeWidth; //MIN(safeWidth, 600);
    CGFloat margin = 20;
    CGFloat width = maxContentWidth - margin * 2;
    CGFloat y = 30;
#   if TARGET_OS_TV
    CGFloat fieldHeight = 80;
    CGFloat labelHeight = 44;
    CGFloat spacing = 24;
#   else
    CGFloat fieldHeight = 40;
    CGFloat labelHeight = 22;
    CGFloat spacing = 12;
#   endif

    // --- Host ---
    UILabel* hostLabel = [self makeSectionLabel:@"HOST ADDRESS"];
    hostLabel.frame = CGRectMake(margin, y, width, labelHeight);
    [_scrollView addSubview:hostLabel];
    y = CGRectGetMaxY(hostLabel.frame) + 4;

    _hostField = [self makeTextField:@"e.g. 192.168.1.100"];
    _hostField.frame = CGRectMake(margin, y, width, fieldHeight);
    _hostField.keyboardType = UIKeyboardTypeURL;
    _hostField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _hostField.autocorrectionType = UITextAutocorrectionTypeNo;
    _hostField.tag = 1;
    [_scrollView addSubview:_hostField];
    y = CGRectGetMaxY(_hostField.frame) + spacing;

    // --- App Name ---
    UILabel* appLabel = [self makeSectionLabel:@"APP / GAME NAME"];
    appLabel.frame = CGRectMake(margin, y, width, labelHeight);
    [_scrollView addSubview:appLabel];
    y = CGRectGetMaxY(appLabel.frame) + 4;

    _appNameField = [self makeTextField:@"e.g. Desktop or Steam"];
    _appNameField.frame = CGRectMake(margin, y, width, fieldHeight);
    _appNameField.tag = 2;
    [_scrollView addSubview:_appNameField];
    y = CGRectGetMaxY(_appNameField.frame) + spacing;
    
    y += spacing;
    
    // --- Resolution ---
    UILabel* resLabel = [self makeSectionLabel:@"RESOLUTION"];
    resLabel.frame = CGRectMake(margin, y, width, labelHeight);
    [_scrollView addSubview:resLabel];
    y = CGRectGetMaxY(resLabel.frame) + 4;

    NSMutableArray* resSegments = [NSMutableArray arrayWithObjects:@"720p", @"1080p", nil];
    if (VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)) {
        [resSegments addObject:@"4K"];
    }
    _resolutionSelector = [[UISegmentedControl alloc] initWithItems:resSegments];
    _resolutionSelector.frame = CGRectMake(margin, y, width, 34);
    _resolutionSelector.tintColor = [UIColor systemBlueColor];
    [_scrollView addSubview:_resolutionSelector];
    y = CGRectGetMaxY(_resolutionSelector.frame) + spacing;

    // --- Frame Rate ---
    UILabel* fpsLabel = [self makeSectionLabel:@"FRAME RATE"];
    fpsLabel.frame = CGRectMake(margin, y, width, labelHeight);
    [_scrollView addSubview:fpsLabel];
    y = CGRectGetMaxY(fpsLabel.frame) + 4;

    NSMutableArray* fpsSegments = [NSMutableArray arrayWithObjects:@"30 FPS", @"60 FPS", nil];
    if (@available(iOS 10.3, *)) {
        if ([UIScreen mainScreen].maximumFramesPerSecond > 62) {
            [fpsSegments addObject:@"120 FPS"];
        }
    }
    _framerateSelector = [[UISegmentedControl alloc] initWithItems:fpsSegments];
    _framerateSelector.frame = CGRectMake(margin, y, width, 34);
    _framerateSelector.tintColor = [UIColor systemBlueColor];
    [_framerateSelector addTarget:self action:@selector(updateBitrate) forControlEvents:UIControlEventValueChanged];
    [_scrollView addSubview:_framerateSelector];
    y = CGRectGetMaxY(_framerateSelector.frame) + spacing;

    // --- Bitrate ---
    _bitrateLabel = [[UILabel alloc] initWithFrame:CGRectMake(margin, y, width, labelHeight)];
//    _bitrateLabel.textColor = [UIColor colorWithWhite:0.8 alpha:1.0];
    _bitrateLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    [_scrollView addSubview:_bitrateLabel];
    y = CGRectGetMaxY(_bitrateLabel.frame) + 4;

#if TARGET_OS_TV
    NSMutableArray* presetTitles = [NSMutableArray array];
    for (int i = 0; i < (int)(sizeof(bitratePresets) / sizeof(*bitratePresets)); i++) {
        [presetTitles addObject:[NSString stringWithFormat:@"%d", bitratePresets[i] / 1000]];
    }
    _bitratePresets = [[UISegmentedControl alloc] initWithItems:presetTitles];
    _bitratePresets.frame = CGRectMake(margin, y, width, 44);
    [_bitratePresets addTarget:self action:@selector(bitratePresetChanged) forControlEvents:UIControlEventValueChanged];
    [_scrollView addSubview:_bitratePresets];
    y = CGRectGetMaxY(_bitratePresets.frame) + spacing;
#else
    _bitrateSlider = [[UISlider alloc] initWithFrame:CGRectMake(margin, y, width, 34)];
    _bitrateSlider.minimumValue = 0;
    _bitrateSlider.maximumValue = (sizeof(bitrateTable) / sizeof(*bitrateTable)) - 1;
    [_bitrateSlider addTarget:self action:@selector(bitrateSliderMoved) forControlEvents:UIControlEventValueChanged];
    [_scrollView addSubview:_bitrateSlider];
    y = CGRectGetMaxY(_bitrateSlider.frame) + spacing;
#endif

    y += spacing;
    
    // --- Controller Mapping ---
    UILabel* controllerLabel = [self makeSectionLabel:@"CONTROLLER"];
    controllerLabel.frame = CGRectMake(margin, y, width, labelHeight);
    [_scrollView addSubview:controllerLabel];
    y = CGRectGetMaxY(controllerLabel.frame) + 4;

    UIButton* mappingButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [mappingButton setTitle:@"Button Mapping" forState:UIControlStateNormal];
    mappingButton.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightRegular];
    mappingButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
//    mappingButton.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
//    mappingButton.layer.cornerRadius = 8;
//    mappingButton.contentEdgeInsets = UIEdgeInsetsMake(0, 12, 0, 12);
    mappingButton.frame = CGRectMake(margin, y, width, fieldHeight);
    [mappingButton addTarget:self action:@selector(openControllerMapping) forControlEvents:UIControlEventPrimaryActionTriggered];
    [_scrollView addSubview:mappingButton];
    y = CGRectGetMaxY(mappingButton.frame) + spacing;
    
    y += spacing;
    _scrollView.contentSize = CGSizeMake(maxContentWidth, y);
}

- (void)openControllerMapping {
    GLControllerListViewController* vc = [[GLControllerListViewController alloc] init];
    [self.navigationController pushViewController:vc animated:YES];
}

- (UILabel*)makeSectionLabel:(NSString*)text {
    UILabel* label = [[UILabel alloc] init];
    label.text = text;
//    label.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
    label.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    return label;
}

- (UITextField*)makeTextField:(NSString*)placeholder {
    UITextField* field = [[UITextField alloc] init];
    field.placeholder = placeholder;
//    field.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
//    field.textColor = [UIColor whiteColor];
#if !TARGET_OS_TV
//    field.textColor = [UIColor labelColor];
//    field.backgroundColor = [UIColor systemBackgroundColor];
#endif
    field.borderStyle = UITextBorderStyleRoundedRect;
    field.attributedPlaceholder = [[NSAttributedString alloc]
        initWithString:placeholder
            attributes:@{NSForegroundColorAttributeName: [UIColor colorWithWhite:0.4 alpha:1.0]}];
    field.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 0)];
    field.leftViewMode = UITextFieldViewModeAlways;
//    field.layer.cornerRadius = 8;
//    field.returnKeyType = UIReturnKeyDone;
    field.delegate = self;
    return field;
}

- (void)populateWithSettings:(TemporarySettings*)settings hostAddress:(NSString*)hostAddress appName:(NSString*)appName {
    _hostField.text = hostAddress;
    _appNameField.text = appName;

    // Prefer values persisted in NSUserDefaults; fall back to Core Data, then defaults.
    NSUserDefaults* d = [NSUserDefaults standardUserDefaults];
    NSInteger height = [d integerForKey:kGLHeight] ?: [settings.height integerValue];
    NSInteger fps    = [d integerForKey:kGLFramerate] ?: [settings.framerate integerValue];
    NSInteger br     = [d integerForKey:kGLBitrate] ?: [settings.bitrate integerValue];
    if (height == 0) height = 1080;
    if (fps == 0)    fps = 60;

    // Resolution
    if (height >= 2160 && _resolutionSelector.numberOfSegments > 2) {
        [_resolutionSelector setSelectedSegmentIndex:2];
    } else if (height >= 1080) {
        [_resolutionSelector setSelectedSegmentIndex:1];
    } else {
        [_resolutionSelector setSelectedSegmentIndex:0];
    }

    // Frame rate
    if (fps >= 120 && _framerateSelector.numberOfSegments > 2) {
        [_framerateSelector setSelectedSegmentIndex:2];
    } else if (fps >= 60) {
        [_framerateSelector setSelectedSegmentIndex:1];
    } else {
        [_framerateSelector setSelectedSegmentIndex:0];
    }

    // Bitrate
    _bitrate = br;
    if (_bitrate == 0) {
        [self updateBitrate]; // derive a sensible default from resolution/fps
    } else {
        [self syncBitrateControlAnimated:NO];
        [self updateBitrateLabel];
    }
}

// Reflect the current _bitrate value in whichever bitrate control this platform uses.
- (void)syncBitrateControlAnimated:(BOOL)animated {
#if TARGET_OS_TV
    int count = (int)(sizeof(bitratePresets) / sizeof(*bitratePresets));
    int bestIndex = 0;
    for (int i = 0; i < count; i++) {
        if (_bitrate >= bitratePresets[i]) {
            bestIndex = i;
        }
    }
    _bitratePresets.selectedSegmentIndex = bestIndex;
#else
    [_bitrateSlider setValue:[self sliderIndexForBitrate:_bitrate] animated:animated];
#endif
}

#if TARGET_OS_TV
- (void)bitratePresetChanged {
    NSInteger idx = _bitratePresets.selectedSegmentIndex;
    int count = (int)(sizeof(bitratePresets) / sizeof(*bitratePresets));
    if (idx < 0 || idx >= count) {
        return;
    }
    _bitrate = bitratePresets[idx];
    [self updateBitrateLabel];
}
#endif

- (int)sliderIndexForBitrate:(NSInteger)bitrate {
    int count = (int)(sizeof(bitrateTable) / sizeof(*bitrateTable));
    for (int i = 0; i < count; i++) {
        if (bitrate <= bitrateTable[i]) return i;
    }
    return count - 1;
}

- (NSInteger)chosenFPS {
    switch (_framerateSelector.selectedSegmentIndex) {
        case 0: return 30;
        case 2: return 120;
        default: return 60;
    }
}

- (NSInteger)chosenWidth {
    switch (_resolutionSelector.selectedSegmentIndex) {
        case 0: return 1280;
        case 2: return 3840;
        default: return 1920;
    }
}

- (NSInteger)chosenHeight {
    switch (_resolutionSelector.selectedSegmentIndex) {
        case 0: return 720;
        case 2: return 2160;
        default: return 1080;
    }
}

- (void)updateBitrate {
    NSInteger fps = [self chosenFPS];
    NSInteger pixels = [self chosenWidth] * [self chosenHeight];

    struct { NSInteger pixels; int factor; } resTable[] = {
        { 1280*720, 5 }, { 1920*1080, 10 }, { 3840*2160, 40 }, { -1, -1 }
    };

    float resolutionFactor = 10;
    for (int i = 0; resTable[i].pixels != -1; i++) {
        if (pixels <= resTable[i].pixels) {
            resolutionFactor = resTable[i].factor;
            break;
        }
    }

    float frameRateFactor = (fps <= 60 ? fps : (sqrtf(fps / 60.f) * 60.f)) / 30.f;
    _bitrate = MIN((NSInteger)roundf(resolutionFactor * frameRateFactor) * 1000, 100000);
    [self syncBitrateControlAnimated:YES];
    [self updateBitrateLabel];
}

#if !TARGET_OS_TV
- (void)bitrateSliderMoved {
    int idx = (int)_bitrateSlider.value;
    int count = (int)(sizeof(bitrateTable) / sizeof(*bitrateTable));
    if (idx >= count) idx = count - 1;
    _bitrate = bitrateTable[idx];
    [self updateBitrateLabel];
}
#endif

- (void)updateBitrateLabel {
    _bitrateLabel.text = [NSString stringWithFormat:bitrateFormat, _bitrate / 1000.0];
}

- (void)saveAndDismiss {
    NSString* host = [_hostField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSString* appName = [_appNameField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

    if (host.length == 0 || appName.length == 0) {
        UIAlertController* alert = [UIAlertController
            alertControllerWithTitle:@"Missing Information"
            message:@"Please enter both a host address and an app name."
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:host forKey:kGLHostAddress];
    [defaults setObject:appName forKey:kGLAppName];
    [defaults setInteger:[self chosenWidth] forKey:kGLWidth];
    [defaults setInteger:[self chosenHeight] forKey:kGLHeight];
    [defaults setInteger:[self chosenFPS] forKey:kGLFramerate];
    [defaults setInteger:_bitrate forKey:kGLBitrate];
    [defaults synchronize];

    DataManager* dataMan = [[DataManager alloc] init];
    [dataMan saveSettingsWithBitrate:_bitrate
                           framerate:[self chosenFPS]
                              height:[self chosenHeight]
                               width:[self chosenWidth]
                         audioConfig:2
                    onscreenControls:0
                       optimizeGames:NO
                     multiController:YES
                     swapABXYButtons:NO
                           audioOnPC:NO
                      preferredCodec:CODEC_PREF_AUTO
                      useFramePacing:NO
                           enableHdr:NO
                      btMouseSupport:NO
                   absoluteTouchMode:NO
                        statsOverlay:NO];

    [self dismissViewControllerAnimated:YES completion:^{
        [self.delegate settingsDidSave];
    }];
}

- (void)cancel {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

@end
