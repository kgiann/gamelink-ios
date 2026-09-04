//
//  GLLaunchViewController.m
//  GameLink
//

@import ImageIO;

#import "GLLaunchViewController.h"
#import "GLSettingsViewController.h"
#import "StreamFrameViewController.h"
#import "CryptoManager.h"
#import "IdManager.h"
#import "DataManager.h"
#import "TemporarySettings.h"
#import "TemporaryHost.h"
#import "TemporaryApp.h"
#import "HttpManager.h"
#import "HttpRequest.h"
#import "HttpResponse.h"
#import "ServerInfoResponse.h"
#import "AppListResponse.h"
#import "ConnectionHelper.h"
#import "DiscoveryWorker.h"
#import "WakeOnLanManager.h"
#import "ControllerSupport.h"

#import <VideoToolbox/VideoToolbox.h>
#import <AVFoundation/AVFoundation.h>

extern NSString* const kGLHostAddress;
extern NSString* const kGLAppName;
extern NSString* const kGLWidth;
extern NSString* const kGLHeight;
extern NSString* const kGLFramerate;
extern NSString* const kGLBitrate;
extern NSString* const kGLAudioConfig;
extern NSString* const kGLOnscreenControls;
extern NSString* const kGLOptimizeGames;
extern NSString* const kGLMultiController;
extern NSString* const kGLSwapABXY;
extern NSString* const kGLPlayAudioOnPC;
extern NSString* const kGLPreferredCodec;
extern NSString* const kGLUseFramePacing;
extern NSString* const kGLEnableHdr;
extern NSString* const kGLBtMouse;
extern NSString* const kGLAbsoluteTouch;
extern NSString* const kGLStatsOverlay;

typedef NS_ENUM(NSInteger, GLConnectionState) {
    GLStateUnconfigured,
    GLStateConnecting,
    GLStateError,
    GLStateStreamEnded,
};

typedef NS_ENUM(NSInteger, GLStreamingState) {
    GLStreamingStateSuspended = 0,  ///< Needs reactivation on resume
    GLStreamingStateInactive,       ///< Should not auto reactivate
    GLStreamingStateActive,         ///< Is currently active
};

@implementation GLLaunchViewController {
    // UI elements (built in code)
    UIView*                   _overlayView;
    UIActivityIndicatorView*  _spinner;
    UILabel*                  _statusLabel;
    UILabel*                  _detailLabel;
    UIButton*                 _connectButton;
    UIButton*                 _cancelButton;
#if TARGET_OS_TV
    // Bridges focus from the top-right gear (nav bar) down to the centered action
    // button, which a straight-down swipe wouldn't otherwise reach.
    UIFocusGuide*             _actionFocusGuide;
#endif

    // Connection state
    TemporaryHost*            _selectedHost;
    NSOperationQueue*         _opQueue;
    BOOL                      _hasAppeared;
    StreamConfiguration*      _streamConfig;
    NSData*                   _clientCert;
    NSString*                 _uniqueId;
    UIAlertController*        _pairAlert;
    GLConnectionState         _state;
    GLStreamingState          _streamingState;

    // Cancellation: each connection attempt bumps the generation. In-flight
    // background work bails out if the generation changes underneath it.
    BOOL                      _connecting;
    NSInteger                 _connectGeneration;
    NSInteger                 _pendingPairGen;
}

#pragma mark - View Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
//    self.view.backgroundColor = [UIColor blackColor];

    [CryptoManager generateKeyPairUsingSSL];
    _uniqueId = [IdManager getUniqueId];
    _clientCert = [CryptoManager readCertFromFile];

    _opQueue = [[NSOperationQueue alloc] init];

    [self buildOverlayUI];
    [self.navigationController setNavigationBarHidden:NO animated:NO];

    // Configure a fully transparent navigation bar so only the button is visible.
    // tvOS doesn't support UINavigationBarAppearance (it throws at runtime), so it
    // must use the legacy background/shadow-image customization instead.
#if TARGET_OS_TV
    [self.navigationController.navigationBar setBackgroundImage:[UIImage new] forBarMetrics:UIBarMetricsDefault];
    self.navigationController.navigationBar.shadowImage = [UIImage new];
    self.navigationController.navigationBar.translucent = YES;
    self.navigationController.navigationBar.backgroundColor = [UIColor clearColor];
#else
    UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
    [appearance configureWithTransparentBackground];
    appearance.backgroundColor = [UIColor clearColor];
    appearance.backgroundEffect = nil;
    appearance.shadowColor = [UIColor clearColor];
    self.navigationController.navigationBar.standardAppearance = appearance;
    self.navigationController.navigationBar.scrollEdgeAppearance = appearance;
#endif
    self.navigationController.navigationBar.tintColor = [UIColor whiteColor];

    // Add a gear button as the right bar button item. Sizing the glyph from a
    // system text style lets it inherit each platform's font metrics (larger on tvOS).
    UIImage *gear = [[UIImage systemImageNamed:@"gearshape"]
        imageByApplyingSymbolConfiguration:[UIImageSymbolConfiguration configurationWithTextStyle:UIFontTextStyleTitle2]];
    UIBarButtonItem *settingsItem = [[UIBarButtonItem alloc] initWithImage:gear style:UIBarButtonItemStylePlain target:self action:@selector(settingsTapped)];
    settingsItem.accessibilityLabel = @"Settings";
    self.navigationItem.rightBarButtonItem = settingsItem;

    // Connect to host when GameLink becomes active.
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(applicationDidBecomeActive:)
                                                 name: UIApplicationDidBecomeActiveNotification
                                               object: nil];
    
    // Quit the host app when GameLink is backgrounded or terminated during an active stream.
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(applicationDidEnterBackground:)
                                                 name: UIApplicationDidEnterBackgroundNotification
                                               object: nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillTerminate:)
                                                 name:UIApplicationWillTerminateNotification
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    Log(LOG_I, @"viewWillAppear");
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:NO animated:animated];

    // Returning from stream or settings is handled by viewWillAppear/settingsDidSave.
    if (_streamingState == GLStreamingStateActive) {
        _streamingState = GLStreamingStateInactive;
        [self quitHostAppAndWait:FALSE];
        [self showStreamEndedState];
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    // Ensure focus lands on the visible action button after the view appears.
    [self refreshPreferredFocus];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
}

#pragma mark - UI Construction

- (void)buildOverlayUI {
    _overlayView = [[UIView alloc] initWithFrame:self.view.bounds];
    _overlayView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_overlayView];

    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    _spinner.color = [UIColor whiteColor];
    _spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [_overlayView addSubview:_spinner];

    _statusLabel = [[UILabel alloc] init];
    _statusLabel.textColor = [UIColor whiteColor];
    {
        UIFont *base = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle1];
        UIFontDescriptor *desc = [base.fontDescriptor fontDescriptorByAddingAttributes:@{UIFontDescriptorTraitsAttribute: @{UIFontWeightTrait: @(UIFontWeightMedium)}}];
        _statusLabel.font = [UIFont fontWithDescriptor:desc size:0.0];
    }
    _statusLabel.textAlignment = NSTextAlignmentCenter;
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_overlayView addSubview:_statusLabel];

    _detailLabel = [[UILabel alloc] init];
    _detailLabel.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
    _detailLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    _detailLabel.textAlignment = NSTextAlignmentCenter;
    _detailLabel.numberOfLines = 3;
    _detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_overlayView addSubview:_detailLabel];

    _connectButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_connectButton setTitle:@"Connect" forState:UIControlStateNormal];
    {
        UIFont *base = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle3];
        UIFontDescriptor *desc = [base.fontDescriptor fontDescriptorByAddingAttributes:@{UIFontDescriptorTraitsAttribute: @{UIFontWeightTrait: @(UIFontWeightSemibold)}}];
        _connectButton.titleLabel.font = [UIFont fontWithDescriptor:desc size:0.0];
    }
    [_connectButton addTarget:self action:@selector(connectTapped) forControlEvents:UIControlEventPrimaryActionTriggered];
    _connectButton.translatesAutoresizingMaskIntoConstraints = NO;
    _connectButton.hidden = YES;
    [_overlayView addSubview:_connectButton];

    // Shown only while connecting; lets the user abort the connect stage.
    _cancelButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_cancelButton setTitle:@"Cancel" forState:UIControlStateNormal];
    {
        UIFont *base = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle3];
        UIFontDescriptor *desc = [base.fontDescriptor fontDescriptorByAddingAttributes:@{UIFontDescriptorTraitsAttribute: @{UIFontWeightTrait: @(UIFontWeightSemibold)}}];
        _cancelButton.titleLabel.font = [UIFont fontWithDescriptor:desc size:0.0];
    }
    [_cancelButton addTarget:self action:@selector(cancelTapped) forControlEvents:UIControlEventPrimaryActionTriggered];
    _cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    _cancelButton.hidden = YES;
    [_overlayView addSubview:_cancelButton];

    // Spacing scales with the body font's line height, which is far larger on
    // tvOS than iOS — so the layout breathes on TV without any per-idiom constants.
    // (On iOS the unit is ~20pt, matching the values these replace.)
    CGFloat unit = _detailLabel.font.lineHeight;
    CGFloat spinnerOffset = unit * 2.5; // vertical centering bias for the whole stack
    CGFloat statusTopGap  = unit;
    CGFloat detailTopGap  = unit * 0.4;
    CGFloat buttonTopGap  = unit * 1.2;
    CGFloat sideMargin    = unit;

    [NSLayoutConstraint activateConstraints:@[
        [_spinner.centerXAnchor constraintEqualToAnchor:_overlayView.centerXAnchor],
        [_spinner.centerYAnchor constraintEqualToAnchor:_overlayView.centerYAnchor constant:-spinnerOffset],

        [_statusLabel.topAnchor constraintEqualToAnchor:_spinner.bottomAnchor constant:statusTopGap],
        [_statusLabel.centerXAnchor constraintEqualToAnchor:_overlayView.centerXAnchor],
        [_statusLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:_overlayView.leadingAnchor constant:sideMargin],
        [_statusLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_overlayView.trailingAnchor constant:-sideMargin],

        [_detailLabel.topAnchor constraintEqualToAnchor:_statusLabel.bottomAnchor constant:detailTopGap],
        [_detailLabel.centerXAnchor constraintEqualToAnchor:_overlayView.centerXAnchor],
        [_detailLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:_overlayView.leadingAnchor constant:sideMargin],
        [_detailLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_overlayView.trailingAnchor constant:-sideMargin],

        [_connectButton.topAnchor constraintEqualToAnchor:_detailLabel.bottomAnchor constant:buttonTopGap],
        [_connectButton.centerXAnchor constraintEqualToAnchor:_overlayView.centerXAnchor],

        // Cancel occupies the same slot as Retry (only one is visible at a time).
        [_cancelButton.topAnchor constraintEqualToAnchor:_detailLabel.bottomAnchor constant:buttonTopGap],
        [_cancelButton.centerXAnchor constraintEqualToAnchor:_overlayView.centerXAnchor],
    ]];

#if TARGET_OS_TV
    // Bridge focus from the top-right gear down to the centered action button.
    // Critically, the guide's frame must NOT overlap the gear: a focus guide is
    // disabled by the system while its frame overlaps the currently focused view,
    // so anchoring the top to the safe area (below the nav bar) is what lets a
    // downward move from the gear actually land in the guide.
    // It also occupies only the column to the *right* of the button, so an upward
    // move from the centered button travels the center column, never touches the
    // guide, and reaches the gear natively. Target/enabled synced in updateUI:.
    _actionFocusGuide = [[UIFocusGuide alloc] init];
    _actionFocusGuide.enabled = NO;
    [self.view addLayoutGuide:_actionFocusGuide];
    [NSLayoutConstraint activateConstraints:@[
        [_actionFocusGuide.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_actionFocusGuide.leadingAnchor constraintEqualToAnchor:_connectButton.trailingAnchor],
        [_actionFocusGuide.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_actionFocusGuide.bottomAnchor constraintEqualToAnchor:_connectButton.topAnchor],
    ]];
#endif
}

- (void)updateUI:(GLConnectionState)state status:(NSString*)status detail:(NSString*)detail {
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_state = state;
        self->_statusLabel.text = status;
        self->_detailLabel.text = detail ?: @"";

        BOOL isConnecting = (state == GLStateConnecting);
        BOOL isError = (state == GLStateError);
        BOOL isUnconfigured = (state == GLStateUnconfigured);
        BOOL isStreamEnded = (state == GLStateStreamEnded);

        if (isConnecting) {
            [self->_spinner startAnimating];
        } else {
            [self->_spinner stopAnimating];
        }

        self->_cancelButton.hidden = !isConnecting;
        self->_connectButton.hidden = !(isError || isStreamEnded);

#if TARGET_OS_TV
        // Redirect a downward move from the gear to whichever action button is showing.
        UIButton* actionButton = !self->_connectButton.hidden ? self->_connectButton
                               : (!self->_cancelButton.hidden ? self->_cancelButton : nil);
        self->_actionFocusGuide.preferredFocusEnvironments = actionButton ? @[ actionButton ] : @[];
        self->_actionFocusGuide.enabled = (actionButton != nil);
#endif

        [self refreshPreferredFocus];
    });
}

// Request the focus update from the navigation controller rather than self:
// -setNeedsFocusUpdate only works from the environment that currently holds focus,
// and the gear lives in the nav bar (outside self.view). The nav controller
// contains both the bar and our content, so it can always redirect to the button.
- (void)refreshPreferredFocus {
    UIViewController* env = self.navigationController ?: self;
    [env setNeedsFocusUpdate];
    [env updateFocusIfNeeded];
}

- (NSArray<id<UIFocusEnvironment>> *)preferredFocusEnvironments {
    // Prefer the visible action button: Connect (error/ended) or Cancel (connecting),
    // falling back to the gear so focus is never left on nothing.
    if (!_connectButton.hidden) return @[ _connectButton ];
    if (!_cancelButton.hidden)  return @[ _cancelButton ];
    return self.navigationController.navigationBar ? @[ self.navigationController.navigationBar ] : @[];
}

- (void)showStreamEndedState {
    [self updateUI:GLStateStreamEnded status:@"Stream Ended" detail:@"Tap Connect to reconnect"];
}

#pragma mark - Connection Entry Point

- (void)startConnection {
    // Invalidate any in-flight attempt and start a fresh generation.
    _connectGeneration++;
    NSInteger gen = _connectGeneration;

    NSString* hostAddress = [[NSUserDefaults standardUserDefaults] stringForKey:kGLHostAddress];
    NSString* appName = [[NSUserDefaults standardUserDefaults] stringForKey:kGLAppName];

    if (hostAddress.length == 0 || appName.length == 0) {
        _connecting = NO;
        [self updateUI:GLStateUnconfigured status:@"Not Configured" detail:@"Tap Settings to set your host and app."];
        return;
    }

    _connecting = YES;
    [self updateUI:GLStateConnecting status:@"Connecting…" detail:hostAddress];

    // Find an existing saved host so we can reuse its certificate/MAC, or create a fresh one
    DataManager* dataMan = [[DataManager alloc] init];
    NSArray* savedHosts = [dataMan getHosts];
    TemporaryHost* host = nil;

    for (TemporaryHost* h in savedHosts) {
        if ([h.address isEqualToString:hostAddress] ||
            [h.localAddress isEqualToString:hostAddress] ||
            [h.externalAddress isEqualToString:hostAddress]) {
            host = h;
            break;
        }
    }

    if (host == nil) {
        host = [[TemporaryHost alloc] init];
        host.address = hostAddress;
    }

    host.activeAddress = hostAddress;
    _selectedHost = host;

    [self performConnectionSequence:host generation:gen];
}

- (void)performConnectionSequence:(TemporaryHost*)host generation:(NSInteger)gen {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (gen != self->_connectGeneration) return; // cancelled

        dispatch_async(dispatch_get_main_queue(), ^{
            if (gen == self->_connectGeneration) {
                self->_statusLabel.text = @"Connecting to server…";
            }
        });

        BOOL didSendWOL = false;
        NSString* error = @"";
        DiscoveryWorker* worker = [[DiscoveryWorker alloc] initWithHost:host uniqueId:@"main"];

        if (host.mac != nil && ![host.mac isEqualToString:@"00:00:00:00:00:00"]) {
            [WakeOnLanManager wakeHost:host];
            didSendWOL = true;
        }

        for (int i = 0, count = didSendWOL ? 30 : 1; i < count; i++) {
            if (gen != self->_connectGeneration) return; // cancelled
            if ([worker discoverHostWithError:&error]) break;
            sleep(1);
        }

        if (gen != self->_connectGeneration) return; // cancelled

        if (host.state != StateOnline) {
            [self showError:@"Connection Failed" detail:error generation:gen];
            return;
        }

        if (host.pairState == PairStatePaired) {
            [self fetchAppListAndLaunch:host generation:gen];
        } else {
            HttpManager* hMan = [[HttpManager alloc] initWithHost:host];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (gen != self->_connectGeneration) return; // cancelled before pairing
                self->_pendingPairGen = gen;
                PairManager* pMan = [[PairManager alloc] initWithManager:hMan clientCert:self->_clientCert callback:self];
                [self->_opQueue addOperation:pMan];
            });
        }
    });
}

- (void)fetchAppListAndLaunch:(TemporaryHost*)host generation:(NSInteger)gen {
    if (gen != _connectGeneration) return; // cancelled

    dispatch_async(dispatch_get_main_queue(), ^{
        if (gen == self->_connectGeneration) {
            self->_statusLabel.text = @"Loading app list…";
        }
    });

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (gen != self->_connectGeneration) return; // cancelled

        AppListResponse* appListResp = [ConnectionHelper getAppListForHost:host];

        if (gen != self->_connectGeneration) return; // cancelled during fetch

        if (![appListResp isStatusOk] || [appListResp getAppList] == nil) {
            [self showError:@"App List Failed" detail:appListResp.statusMessage generation:gen];
            return;
        }

        NSString* targetName = [[NSUserDefaults standardUserDefaults] stringForKey:kGLAppName];
        TemporaryApp* targetApp = nil;
        TemporaryApp* runningApp = nil;

        for (TemporaryApp* app in [appListResp getAppList]) {
            app.host = host;
            if ([app.id isEqualToString:host.currentGame]) {
                runningApp = app;
            }
            if ([app.name caseInsensitiveCompare:targetName] == NSOrderedSame) {
                targetApp = app;
            }
        }

        if (targetApp == nil) {
            [self showError:@"App Not Found"
                     detail:[NSString stringWithFormat:@"Could not find \"%@\" on the host. Check the app name in Settings.", targetName]
                 generation:gen];
            return;
        }

        // Resume target app if it's running; otherwise launch fresh
        TemporaryApp* appToStream = (runningApp != nil && [runningApp.id isEqualToString:targetApp.id]) ? runningApp : targetApp;

        [self prepareStreamConfigForApp:appToStream];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (gen != self->_connectGeneration) return; // cancelled just before launch
            self->_connecting = NO;
            self->_streamingState = GLStreamingStateActive;
            [self performSegueWithIdentifier:@"createStreamFrame" sender:nil];
        });
    });
}

#pragma mark - Stream Configuration

- (void)prepareStreamConfigForApp:(TemporaryApp*)app {
    _streamConfig = [[StreamConfiguration alloc] init];
    _streamConfig.host = app.host.activeAddress;
    _streamConfig.httpsPort = app.host.httpsPort;
    _streamConfig.appID = app.id;
    _streamConfig.appName = app.name;
    _streamConfig.serverCert = app.host.serverCert;

    DataManager* dataMan = [[DataManager alloc] init];
    TemporarySettings* settings = [dataMan getSettings];

    // User-facing values come from NSUserDefaults (durable on tvOS); the rest use
    // the Core Data defaults.
    NSUserDefaults* d = [NSUserDefaults standardUserDefaults];
    NSInteger width  = [d integerForKey:kGLWidth]     ?: [settings.width intValue];
    NSInteger height = [d integerForKey:kGLHeight]    ?: [settings.height intValue];
    NSInteger fps    = [d integerForKey:kGLFramerate] ?: [settings.framerate intValue];
    NSInteger bitrate = [d integerForKey:kGLBitrate]  ?: [settings.bitrate intValue];
    if (width == 0)   width = 1920;
    if (height == 0)  height = 1080;
    if (fps == 0)     fps = 60;
    if (bitrate == 0) bitrate = 10000;

    _streamConfig.frameRate = (int)fps;
    if (_streamConfig.frameRate > (int)[UIScreen mainScreen].maximumFramesPerSecond) {
        _streamConfig.frameRate = (int)[UIScreen mainScreen].maximumFramesPerSecond;
    }
    _streamConfig.height = (int)height;
    _streamConfig.width = (int)width;
    _streamConfig.bitRate = (int)bitrate;

    // Remaining settings come from NSUserDefaults (durable on tvOS), falling back
    // to the Core Data defaults.
    NSInteger audioConfig = [d objectForKey:kGLAudioConfig] ? [d integerForKey:kGLAudioConfig] : [settings.audioConfig integerValue];
    if (audioConfig == 0) audioConfig = 2;
    NSInteger preferredCodec = [d objectForKey:kGLPreferredCodec] ? [d integerForKey:kGLPreferredCodec] : settings.preferredCodec;
    BOOL enableHdr = [d objectForKey:kGLEnableHdr] ? [d boolForKey:kGLEnableHdr] : settings.enableHdr;

    _streamConfig.optimizeGameSettings = [d objectForKey:kGLOptimizeGames] ? [d boolForKey:kGLOptimizeGames] : settings.optimizeGames;
    _streamConfig.playAudioOnPC = [d objectForKey:kGLPlayAudioOnPC] ? [d boolForKey:kGLPlayAudioOnPC] : settings.playAudioOnPC;
    _streamConfig.useFramePacing = [d objectForKey:kGLUseFramePacing] ? [d boolForKey:kGLUseFramePacing] : settings.useFramePacing;
    _streamConfig.swapABXYButtons = [d objectForKey:kGLSwapABXY] ? [d boolForKey:kGLSwapABXY] : settings.swapABXYButtons;
    _streamConfig.multiController = [d objectForKey:kGLMultiController] ? [d boolForKey:kGLMultiController] : YES;
    _streamConfig.gamepadMask = [ControllerSupport getConnectedGamepadMask:_streamConfig];

    int physicalChannels = (int)[AVAudioSession sharedInstance].maximumOutputNumberOfChannels;
    int channels = MIN((int)audioConfig, physicalChannels);
    if (channels >= 8) {
        _streamConfig.audioConfiguration = AUDIO_CONFIGURATION_71_SURROUND;
    } else if (channels >= 6) {
        _streamConfig.audioConfiguration = AUDIO_CONFIGURATION_51_SURROUND;
    } else {
        _streamConfig.audioConfiguration = AUDIO_CONFIGURATION_STEREO;
    }

    _streamConfig.serverCodecModeSupport = app.host.serverCodecModeSupport;

    switch (preferredCodec) {
        case CODEC_PREF_AV1:
#if defined(__IPHONE_16_0)
            if (VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)) {
                _streamConfig.supportedVideoFormats |= VIDEO_FORMAT_AV1_MAIN8;
            }
#endif
            // Fall-through
        case CODEC_PREF_AUTO:
        case CODEC_PREF_HEVC:
            if (VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)) {
                _streamConfig.supportedVideoFormats |= VIDEO_FORMAT_H265;
            }
            // Fall-through
        case CODEC_PREF_H264:
            _streamConfig.supportedVideoFormats |= VIDEO_FORMAT_H264;
            break;
    }

    if (VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC) &&
        (_streamConfig.width > 4096 || _streamConfig.height > 4096 || enableHdr)) {
        _streamConfig.supportedVideoFormats |= VIDEO_FORMAT_H265;
        if (enableHdr && (AVPlayer.availableHDRModes & AVPlayerHDRModeHDR10)) {
            _streamConfig.supportedVideoFormats |= VIDEO_FORMAT_H265_MAIN10;
        }
    }
}

#pragma mark - Segue

- (void)prepareForSegue:(UIStoryboardSegue*)segue sender:(id)sender {
    if ([segue.destinationViewController isKindOfClass:[StreamFrameViewController class]]) {
        StreamFrameViewController* streamVC = segue.destinationViewController;
        streamVC.streamConfig = _streamConfig;
    }
}

#pragma mark - Backgrounding

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    if (_streamingState != GLStreamingStateSuspended) return;
    
    Log(LOG_I, @"GameLink activating -- starting connection");
    [self startConnection];
}

// This fires when the home button is pressed. If we're actively streaming,
// tell the host to quit the running app so it doesn't stay occupied.
- (void)applicationDidEnterBackground:(NSNotification *)notification {
    // If we're mid-connect (not yet streaming), cancel it and reconnect when we
    // come back to the foreground.
    if (_connecting) {
        Log(LOG_I, @"GameLink backgrounded while connecting -- cancelling");
        [self cancelInFlightConnection];
        _streamingState = GLStreamingStateSuspended; // applicationDidBecomeActive re-connects
        return;
    }

    if (_streamingState != GLStreamingStateActive || _streamConfig == nil) {
        return;
    }

    Log(LOG_I, @"GameLink backgrounded -- quitting host app");
    // Block until the quit request finishes; otherwise iOS tears the app down
    // before the request is sent and the host is left occupied.
    [self quitHostAppAndWait:YES];
    _streamingState = GLStreamingStateSuspended;
}

// NOTE: applicationDidEnterBackground is called before this one
- (void)applicationWillTerminate:(NSNotification *)notification {
    if (_streamingState != GLStreamingStateActive || _streamConfig == nil) {
        return;
    }

    Log(LOG_I, @"Application terminating -- quitting host app");
    // Block until the quit request finishes; otherwise iOS tears the app down
    // before the request is sent and the host is left occupied.
    [self quitHostAppAndWait:YES];
}

- (void)quitHostAppAndWait:(BOOL)wait {
    NSString* host = [_streamConfig.host copy];
    unsigned short httpsPort = _streamConfig.httpsPort;
    NSData* serverCert = [_streamConfig.serverCert copy];

    dispatch_semaphore_t sema = wait ? dispatch_semaphore_create(0) : NULL;

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        HttpManager* httpManager =
            [[HttpManager alloc] initWithAddress:host
                                       httpsPort:httpsPort
                                      serverCert:serverCert];

        HttpResponse* response = [[HttpResponse alloc] init];

        HttpRequest* request =
            [HttpRequest requestForResponse:response
                             withUrlRequest:[httpManager newQuitAppRequest]];

        [httpManager executeRequestSynchronously:request];

        Log(LOG_I, @"Quit host app response: %d", response.statusCode);

        if (sema != NULL) {
            dispatch_semaphore_signal(sema);
        }
    });

    if (wait) {
        // Bounded by the underlying URL request timeout, so this won't hang
        // indefinitely and keep iOS from terminating us.
        dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
    }
}

#pragma mark - Error Helpers

- (void)showError:(NSString*)title detail:(NSString*)detail generation:(NSInteger)gen {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (gen != self->_connectGeneration) return; // superseded/cancelled
        self->_connecting = NO;
        [self updateUI:GLStateError status:title detail:detail];
    });
}

#pragma mark - Cancellation

// Stop any in-flight connection work. Bumping the generation makes the
// background stages bail; also cancel pairing and dismiss the pairing alert.
- (void)cancelInFlightConnection {
    _connectGeneration++;
    _connecting = NO;
    [_opQueue cancelAllOperations];
    if (_pairAlert) {
        [_pairAlert dismissViewControllerAnimated:NO completion:nil];
        _pairAlert = nil;
    }
}

- (void)cancelTapped {
    if (!_connecting) {
        return;
    }
    [self cancelInFlightConnection];
    [self updateUI:GLStateError status:@"Connection Cancelled" detail:@"Tap Connect to try again."];
}

#pragma mark - Button Actions

- (void)connectTapped {
    [self startConnection];
}

- (void)settingsTapped {
    GLSettingsViewController* settingsVC = [[GLSettingsViewController alloc] init];
    settingsVC.delegate = self;
    UINavigationController* navVC = [[UINavigationController alloc] initWithRootViewController:settingsVC];
    navVC.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:navVC animated:YES completion:nil];
}

#pragma mark - GLSettingsDelegate

- (void)settingsDidSave {
    [self startConnection];
}

#pragma mark - PairCallback

- (void)startPairing:(NSString*)PIN {
    dispatch_sync(dispatch_get_main_queue(), ^{
        if (_pendingPairGen != _connectGeneration) return; // cancelled
        _pairAlert = [UIAlertController
            alertControllerWithTitle:@"Pairing"
            message:[NSString stringWithFormat:
                @"Enter the following PIN on your host:\n\n%@\n\nFor Sunshine, use the web UI to enter the PIN.", PIN]
            preferredStyle:UIAlertControllerStyleAlert];
        [_pairAlert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleDestructive handler:^(UIAlertAction* action) {
            self->_pairAlert = nil;
            [self updateUI:GLStateUnconfigured status:@"Pairing Cancelled" detail:@""];
        }]];
        [self presentViewController:_pairAlert animated:YES completion:nil];
    });
}

- (void)pairSuccessful:(NSData*)serverCert {
    NSInteger gen = _pendingPairGen;
    if (gen != _connectGeneration) return; // cancelled

    // Persist the server cert immediately (on background thread, before main queue dispatch).
    self->_selectedHost.serverCert = serverCert;
    DataManager* dataMan = [[DataManager alloc] init];
    [dataMan updateHost:self->_selectedHost];

    dispatch_async(dispatch_get_main_queue(), ^{
        if (gen != self->_connectGeneration) return; // cancelled
        UIAlertController* alert = self->_pairAlert;
        self->_pairAlert = nil;
        // Wait for the alert dismiss animation to finish before pushing the stream view,
        // otherwise performSegueWithIdentifier: fails while a VC is still being presented.
        if (alert) {
            [alert dismissViewControllerAnimated:YES completion:^{
                [self fetchAppListAndLaunch:self->_selectedHost generation:gen];
            }];
        } else {
            [self fetchAppListAndLaunch:self->_selectedHost generation:gen];
        }
    });
}

- (void)pairFailed:(NSString*)message {
    NSInteger gen = _pendingPairGen;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (gen != self->_connectGeneration) return; // cancelled
        UIAlertController* alert = self->_pairAlert;
        self->_pairAlert = nil;
        if (alert) {
            [alert dismissViewControllerAnimated:YES completion:^{
                [self showError:@"Pairing Failed" detail:message generation:gen];
            }];
        } else {
            [self showError:@"Pairing Failed" detail:message generation:gen];
        }
    });
}

- (void)alreadyPaired {
    NSInteger gen = _pendingPairGen;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (gen != self->_connectGeneration) return; // cancelled
        UIAlertController* alert = self->_pairAlert;
        self->_pairAlert = nil;
        if (alert) {
            [alert dismissViewControllerAnimated:YES completion:^{
                [self fetchAppListAndLaunch:self->_selectedHost generation:gen];
            }];
        } else {
            [self fetchAppListAndLaunch:self->_selectedHost generation:gen];
        }
    });
}

@end

