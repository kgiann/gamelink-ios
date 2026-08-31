//
//  GLConnectionSettingsViewController.m
//  GameLink
//

#import "GLConnectionSettingsViewController.h"
#import "GLControllerListViewController.h"
#import "DataManager.h"
#import "TemporarySettings.h"

#import <VideoToolbox/VideoToolbox.h>
#import <AVFoundation/AVFoundation.h>

NSString* const kGLHostAddress = @"GLHostAddress";
NSString* const kGLAppName = @"GLAppName";

// All user-facing settings are persisted directly in NSUserDefaults (durable on
// both iOS and tvOS) in addition to the Core Data store.
NSString* const kGLWidth = @"GLWidth";
NSString* const kGLHeight = @"GLHeight";
NSString* const kGLFramerate = @"GLFramerate";
NSString* const kGLBitrate = @"GLBitrate";
NSString* const kGLAudioConfig = @"GLAudioConfig";
NSString* const kGLOnscreenControls = @"GLOnscreenControls";
NSString* const kGLOptimizeGames = @"GLOptimizeGames";
NSString* const kGLMultiController = @"GLMultiController";
NSString* const kGLSwapABXY = @"GLSwapABXY";
NSString* const kGLPlayAudioOnPC = @"GLPlayAudioOnPC";
NSString* const kGLPreferredCodec = @"GLPreferredCodec";
NSString* const kGLUseFramePacing = @"GLUseFramePacing";
NSString* const kGLEnableHdr = @"GLEnableHdr";
NSString* const kGLBtMouse = @"GLBtMouse";
NSString* const kGLAbsoluteTouch = @"GLAbsoluteTouch";
NSString* const kGLStatsOverlay = @"GLStatsOverlay";

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

@interface GLConnectionSettingsViewController () <UITextFieldDelegate>
@end

@implementation GLConnectionSettingsViewController {
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

    // Additional DataManager settings
    UISegmentedControl* _audioSelector;
    UISegmentedControl* _codecSelector;
    UISegmentedControl* _hdrToggle;
    UISegmentedControl* _framePacingToggle;
    UISegmentedControl* _optimizeToggle;
    UISegmentedControl* _multiControllerToggle;
    UISegmentedControl* _swapABXYToggle;
    UISegmentedControl* _audioOnPCToggle;
    UISegmentedControl* _statsToggle;
#if !TARGET_OS_TV
    UISegmentedControl* _oscSelector;
    UISegmentedControl* _absoluteTouchToggle;
    UISegmentedControl* _btMouseToggle;
#endif

    UIScrollView* _scrollView;
    UIActivityIndicatorView* _loadingSpinner;

    // Layout metrics (set in buildUI)
    CGFloat _margin, _contentWidth, _fieldHeight, _labelHeight, _segHeight, _spacing, _y;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    // Spinner shown while Core Data loads
    _loadingSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
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

#pragma mark - UI Construction

- (void)buildUI {
    _scrollView = [[UIScrollView alloc] init];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_scrollView];
    [NSLayoutConstraint activateConstraints:@[
        [_scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_scrollView.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],
    ]];

    CGFloat safeWidth = self.view.bounds.size.width
        - self.view.safeAreaInsets.left
        - self.view.safeAreaInsets.right;
    _margin = 20;
    _contentWidth = safeWidth - _margin * 2;

    BOOL isTV = (self.traitCollection.userInterfaceIdiom == UIUserInterfaceIdiomTV);
    _fieldHeight = isTV ? 80.0 : 40.0;
    _labelHeight = isTV ? 44.0 : 22.0;
    _spacing = isTV ? 24.0 : 12.0;
    _segHeight = isTV ? 44.0 : 34.0;
    _y = 30;

    // --- Host ---
    UILabel* hostLabel = [self makeSectionLabel:@"HOST ADDRESS"];
    hostLabel.frame = CGRectMake(_margin, _y, _contentWidth, _labelHeight);
    [_scrollView addSubview:hostLabel];
    _y = CGRectGetMaxY(hostLabel.frame) + 4;

    _hostField = [self makeTextField:@"e.g. 192.168.1.100"];
    _hostField.frame = CGRectMake(_margin, _y, _contentWidth, _fieldHeight);
    _hostField.keyboardType = UIKeyboardTypeURL;
    _hostField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _hostField.autocorrectionType = UITextAutocorrectionTypeNo;
    _hostField.returnKeyType = UIReturnKeyNext;
    _hostField.tag = 1;
    [_scrollView addSubview:_hostField];
    _y = CGRectGetMaxY(_hostField.frame) + _spacing;

    // --- App Name ---
    UILabel* appLabel = [self makeSectionLabel:@"APP / GAME NAME"];
    appLabel.frame = CGRectMake(_margin, _y, _contentWidth, _labelHeight);
    [_scrollView addSubview:appLabel];
    _y = CGRectGetMaxY(appLabel.frame) + 4;

    _appNameField = [self makeTextField:@"e.g. Desktop or Steam"];
    _appNameField.frame = CGRectMake(_margin, _y, _contentWidth, _fieldHeight);
    _appNameField.tag = 2;
    [_scrollView addSubview:_appNameField];
    _y = CGRectGetMaxY(_appNameField.frame) + _spacing * 2;

    // --- Resolution ---
    NSMutableArray* resSegments = [NSMutableArray arrayWithObjects:@"720p", @"1080p", nil];
    if (VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)) {
        [resSegments addObject:@"4K"];
    }
    _resolutionSelector = [self appendRow:@"RESOLUTION" items:resSegments];

    // --- Frame Rate ---
    NSMutableArray* fpsSegments = [NSMutableArray arrayWithObjects:@"30 FPS", @"60 FPS", nil];
    if ([UIScreen mainScreen].maximumFramesPerSecond > 62) {
        [fpsSegments addObject:@"120 FPS"];
    }
    _framerateSelector = [self appendRow:@"FRAME RATE" items:fpsSegments];
    [_framerateSelector addTarget:self action:@selector(updateBitrate) forControlEvents:UIControlEventValueChanged];

    // --- Bitrate ---
    _bitrateLabel = [[UILabel alloc] initWithFrame:CGRectMake(_margin, _y, _contentWidth, _labelHeight)];
    _bitrateLabel.font = [UIFont systemFontOfSize:(isTV ? 20.0 : 12.0) weight:UIFontWeightMedium];
    [_scrollView addSubview:_bitrateLabel];
    _y = CGRectGetMaxY(_bitrateLabel.frame) + 4;

#if TARGET_OS_TV
    NSMutableArray* presetTitles = [NSMutableArray array];
    for (int i = 0; i < (int)(sizeof(bitratePresets) / sizeof(*bitratePresets)); i++) {
        [presetTitles addObject:[NSString stringWithFormat:@"%d", bitratePresets[i] / 1000]];
    }
    _bitratePresets = [[UISegmentedControl alloc] initWithItems:presetTitles];
    _bitratePresets.frame = CGRectMake(_margin, _y, _contentWidth, _segHeight);
    [_bitratePresets addTarget:self action:@selector(bitratePresetChanged) forControlEvents:UIControlEventValueChanged];
    [_scrollView addSubview:_bitratePresets];
    _y = CGRectGetMaxY(_bitratePresets.frame) + _spacing;
#else
    _bitrateSlider = [[UISlider alloc] initWithFrame:CGRectMake(_margin, _y, _contentWidth, _segHeight)];
    _bitrateSlider.minimumValue = 0;
    _bitrateSlider.maximumValue = (sizeof(bitrateTable) / sizeof(*bitrateTable)) - 1;
    [_bitrateSlider addTarget:self action:@selector(bitrateSliderMoved) forControlEvents:UIControlEventValueChanged];
    [_scrollView addSubview:_bitrateSlider];
    _y = CGRectGetMaxY(_bitrateSlider.frame) + _spacing;
#endif

    // --- Audio ---
    _audioSelector = [self appendRow:@"AUDIO" items:@[@"Stereo", @"5.1", @"7.1"]];

    // --- Codec ---
    _codecSelector = [self appendRow:@"VIDEO CODEC" items:@[@"Auto", @"H.264", @"HEVC", @"AV1"]];

    // --- Toggles (common) ---
    _hdrToggle = [self appendToggleRow:@"HDR"];
    _framePacingToggle = [self appendToggleRow:@"FRAME PACING"];
    _optimizeToggle = [self appendToggleRow:@"OPTIMIZE GAME SETTINGS"];
    _multiControllerToggle = [self appendToggleRow:@"MULTIPLE CONTROLLERS"];
    _swapABXYToggle = [self appendToggleRow:@"SWAP A/B AND X/Y BUTTONS"];
    _audioOnPCToggle = [self appendToggleRow:@"PLAY AUDIO ON HOST PC"];
    _statsToggle = [self appendToggleRow:@"STATS OVERLAY"];

#if !TARGET_OS_TV
    // --- Touch/mouse options (iOS only) ---
    _oscSelector = [self appendRow:@"ON-SCREEN CONTROLS" items:@[@"Off", @"Auto", @"Simple", @"Full"]];
    _absoluteTouchToggle = [self appendToggleRow:@"TOUCHSCREEN AS TRACKPAD"]; // NO = absolute
    _btMouseToggle = [self appendToggleRow:@"BLUETOOTH MOUSE SUPPORT"];
#endif

    _y += _spacing;
    _scrollView.contentSize = CGSizeMake(_contentWidth + _margin * 2, _y);
}

// Append a section label + segmented control at the current _y and return the control.
- (UISegmentedControl*)appendRow:(NSString*)title items:(NSArray<NSString*>*)items {
    UILabel* label = [self makeSectionLabel:title];
    label.frame = CGRectMake(_margin, _y, _contentWidth, _labelHeight);
    [_scrollView addSubview:label];
    _y = CGRectGetMaxY(label.frame) + 4;

    UISegmentedControl* seg = [[UISegmentedControl alloc] initWithItems:items];
    seg.frame = CGRectMake(_margin, _y, _contentWidth, _segHeight);
    [_scrollView addSubview:seg];
    _y = CGRectGetMaxY(seg.frame) + _spacing;
    return seg;
}

- (UISegmentedControl*)appendToggleRow:(NSString*)title {
    return [self appendRow:title items:@[@"Off", @"On"]];
}

- (void)openControllerMapping {
    if (self.tabBarController) {
        self.tabBarController.selectedIndex = 1; // Switch to Button Mapping tab
    } else {
        GLControllerListViewController* vc = [[GLControllerListViewController alloc] init];
        [self.navigationController pushViewController:vc animated:YES];
    }
}

- (UILabel*)makeSectionLabel:(NSString*)text {
    UILabel* label = [[UILabel alloc] init];
    label.text = text;
#if TARGET_OS_TV
    label.textColor = [UIColor lightGrayColor];
#else
    label.textColor = [UIColor secondaryLabelColor];
#endif
    BOOL isTV = (self.traitCollection.userInterfaceIdiom == UIUserInterfaceIdiomTV);
    label.font = [UIFont systemFontOfSize:(isTV ? 20.0 : 11.0) weight:UIFontWeightSemibold];
    return label;
}

- (UITextField*)makeTextField:(NSString*)placeholder {
    UITextField* field = [[UITextField alloc] init];
    field.placeholder = placeholder;
    field.keyboardAppearance = UIKeyboardAppearanceDark;
    field.borderStyle = UITextBorderStyleRoundedRect;
    field.delegate = self;
    return field;
}

#pragma mark - Load

- (void)populateWithSettings:(TemporarySettings*)settings hostAddress:(NSString*)hostAddress appName:(NSString*)appName {
    _hostField.text = hostAddress;
    _appNameField.text = appName;

    NSUserDefaults* d = [NSUserDefaults standardUserDefaults];

    // Resolution / frame rate / bitrate
    NSInteger height = [d integerForKey:kGLHeight] ?: [settings.height integerValue];
    NSInteger fps    = [d integerForKey:kGLFramerate] ?: [settings.framerate integerValue];
    NSInteger br     = [d integerForKey:kGLBitrate] ?: [settings.bitrate integerValue];
    if (height == 0) height = 1080;
    if (fps == 0)    fps = 60;

    if (height >= 2160 && _resolutionSelector.numberOfSegments > 2) {
        _resolutionSelector.selectedSegmentIndex = 2;
    } else if (height >= 1080) {
        _resolutionSelector.selectedSegmentIndex = 1;
    } else {
        _resolutionSelector.selectedSegmentIndex = 0;
    }

    if (fps >= 120 && _framerateSelector.numberOfSegments > 2) {
        _framerateSelector.selectedSegmentIndex = 2;
    } else if (fps >= 60) {
        _framerateSelector.selectedSegmentIndex = 1;
    } else {
        _framerateSelector.selectedSegmentIndex = 0;
    }

    _bitrate = br;
    if (_bitrate == 0) {
        [self updateBitrate];
    } else {
        [self syncBitrateControlAnimated:NO];
        [self updateBitrateLabel];
    }

    // Audio channels: 2 = Stereo, 6 = 5.1, 8 = 7.1
    NSInteger audio = [d objectForKey:kGLAudioConfig] ? [d integerForKey:kGLAudioConfig] : [settings.audioConfig integerValue];
    if (audio == 0) audio = 2;
    _audioSelector.selectedSegmentIndex = (audio >= 8) ? 2 : (audio >= 6 ? 1 : 0);

    // Codec
    NSInteger codec = [d objectForKey:kGLPreferredCodec] ? [d integerForKey:kGLPreferredCodec] : settings.preferredCodec;
    if (codec < 0 || codec > 3) codec = 0;
    _codecSelector.selectedSegmentIndex = codec;

    // Common toggles
    _hdrToggle.selectedSegmentIndex             = [self boolPref:kGLEnableHdr fallback:settings.enableHdr] ? 1 : 0;
    _framePacingToggle.selectedSegmentIndex     = [self boolPref:kGLUseFramePacing fallback:settings.useFramePacing] ? 1 : 0;
    _optimizeToggle.selectedSegmentIndex        = [self boolPref:kGLOptimizeGames fallback:settings.optimizeGames] ? 1 : 0;
    // Multiple controllers defaults ON when nothing has been saved yet.
    _multiControllerToggle.selectedSegmentIndex = [self boolPref:kGLMultiController fallback:YES] ? 1 : 0;
    _swapABXYToggle.selectedSegmentIndex        = [self boolPref:kGLSwapABXY fallback:settings.swapABXYButtons] ? 1 : 0;
    _audioOnPCToggle.selectedSegmentIndex       = [self boolPref:kGLPlayAudioOnPC fallback:settings.playAudioOnPC] ? 1 : 0;
    _statsToggle.selectedSegmentIndex           = [self boolPref:kGLStatsOverlay fallback:settings.statsOverlay] ? 1 : 0;

#if !TARGET_OS_TV
    NSInteger osc = [d objectForKey:kGLOnscreenControls] ? [d integerForKey:kGLOnscreenControls] : [settings.onscreenControls integerValue];
    if (osc < 0 || osc > 3) osc = 0;
    _oscSelector.selectedSegmentIndex = osc;
    _absoluteTouchToggle.selectedSegmentIndex = [self boolPref:kGLAbsoluteTouch fallback:settings.absoluteTouchMode] ? 0 : 1; // On = trackpad(relative)
    _btMouseToggle.selectedSegmentIndex = [self boolPref:kGLBtMouse fallback:settings.btMouseSupport] ? 1 : 0;
#endif
}

- (BOOL)boolPref:(NSString*)key fallback:(BOOL)fallback {
    NSUserDefaults* d = [NSUserDefaults standardUserDefaults];
    if ([d objectForKey:key] != nil) {
        return [d boolForKey:key];
    }
    return fallback;
}

#pragma mark - Save

- (void)save {
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

    NSInteger audioConfig = [self chosenAudioConfig];
    NSInteger osc = [self chosenOnscreenControls];
    BOOL optimize = [self toggleOn:_optimizeToggle];
    BOOL multiController = [self toggleOn:_multiControllerToggle];
    BOOL swapABXY = [self toggleOn:_swapABXYToggle];
    BOOL audioOnPC = [self toggleOn:_audioOnPCToggle];
    uint32_t codec = (uint32_t)_codecSelector.selectedSegmentIndex;
    BOOL framePacing = [self toggleOn:_framePacingToggle];
    BOOL hdr = [self toggleOn:_hdrToggle];
    BOOL btMouse = [self chosenBtMouse];
    BOOL absoluteTouch = [self chosenAbsoluteTouch];
    BOOL stats = [self toggleOn:_statsToggle];

    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:host forKey:kGLHostAddress];
    [defaults setObject:appName forKey:kGLAppName];
    [defaults setInteger:[self chosenWidth] forKey:kGLWidth];
    [defaults setInteger:[self chosenHeight] forKey:kGLHeight];
    [defaults setInteger:[self chosenFPS] forKey:kGLFramerate];
    [defaults setInteger:_bitrate forKey:kGLBitrate];
    [defaults setInteger:audioConfig forKey:kGLAudioConfig];
    [defaults setInteger:osc forKey:kGLOnscreenControls];
    [defaults setBool:optimize forKey:kGLOptimizeGames];
    [defaults setBool:multiController forKey:kGLMultiController];
    [defaults setBool:swapABXY forKey:kGLSwapABXY];
    [defaults setBool:audioOnPC forKey:kGLPlayAudioOnPC];
    [defaults setInteger:codec forKey:kGLPreferredCodec];
    [defaults setBool:framePacing forKey:kGLUseFramePacing];
    [defaults setBool:hdr forKey:kGLEnableHdr];
    [defaults setBool:btMouse forKey:kGLBtMouse];
    [defaults setBool:absoluteTouch forKey:kGLAbsoluteTouch];
    [defaults setBool:stats forKey:kGLStatsOverlay];
    [defaults synchronize];

    DataManager* dataMan = [[DataManager alloc] init];
    [dataMan saveSettingsWithBitrate:_bitrate
                           framerate:[self chosenFPS]
                              height:[self chosenHeight]
                               width:[self chosenWidth]
                         audioConfig:audioConfig
                    onscreenControls:osc
                       optimizeGames:optimize
                     multiController:multiController
                     swapABXYButtons:swapABXY
                           audioOnPC:audioOnPC
                      preferredCodec:codec
                      useFramePacing:framePacing
                           enableHdr:hdr
                      btMouseSupport:btMouse
                   absoluteTouchMode:absoluteTouch
                        statsOverlay:stats];
}

#pragma mark - Value helpers

- (BOOL)toggleOn:(UISegmentedControl*)toggle {
    return toggle != nil && toggle.selectedSegmentIndex == 1;
}

- (NSInteger)chosenAudioConfig {
    switch (_audioSelector.selectedSegmentIndex) {
        case 1: return 6;  // 5.1
        case 2: return 8;  // 7.1
        default: return 2; // Stereo
    }
}

- (NSInteger)chosenOnscreenControls {
#if TARGET_OS_TV
    return 0;
#else
    return _oscSelector ? _oscSelector.selectedSegmentIndex : 0;
#endif
}

- (BOOL)chosenAbsoluteTouch {
#if TARGET_OS_TV
    return NO;
#else
    // "Touchscreen as trackpad" ON == relative == absoluteTouchMode NO
    return _absoluteTouchToggle ? (_absoluteTouchToggle.selectedSegmentIndex == 0) : NO;
#endif
}

- (BOOL)chosenBtMouse {
#if TARGET_OS_TV
    return NO;
#else
    return [self toggleOn:_btMouseToggle];
#endif
}

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
#else
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

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField == _hostField) {
        [_appNameField becomeFirstResponder];
    } else {
        [textField resignFirstResponder];
    }
    return YES;
}

@end
