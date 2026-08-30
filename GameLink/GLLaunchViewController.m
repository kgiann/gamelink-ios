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

typedef NS_ENUM(NSInteger, GLConnectionState) {
    GLStateUnconfigured,
    GLStateConnecting,
    GLStateError,
    GLStateStreamEnded,
};

@implementation GLLaunchViewController {
    // UI elements (built in code)
    UIView*                   _overlayView;
    UIActivityIndicatorView*  _spinner;
    UILabel*                  _statusLabel;
    UILabel*                  _detailLabel;
    UIButton*                 _retryButton;
    UIButton*                 _settingsButton;

    // Connection state
    TemporaryHost*            _selectedHost;
    NSOperationQueue*         _opQueue;
    BOOL                      _hasAppeared;
    StreamConfiguration*      _streamConfig;
    NSData*                   _clientCert;
    NSString*                 _uniqueId;
    UIAlertController*        _pairAlert;
    GLConnectionState         _state;
    BOOL                      _streamingActive;
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
    [self.navigationController setNavigationBarHidden:YES animated:NO];

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
    Log(LOG_I, @"viewWillAppear -- ");
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:animated];

    if (_streamingActive) {
        _streamingActive = NO;
        [self showStreamEndedState];
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

//    if (!_hasAppeared) {
//        // First appearance: kick off the initial connection attempt.
//        _hasAppeared = YES;
//        [self startConnection];
//    }
    // Returning from stream or settings is handled by viewWillAppear/settingsDidSave.
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
    _statusLabel.font = [UIFont systemFontOfSize:28 weight:UIFontWeightMedium];
    _statusLabel.textAlignment = NSTextAlignmentCenter;
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_overlayView addSubview:_statusLabel];

    _detailLabel = [[UILabel alloc] init];
    _detailLabel.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
    _detailLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
    _detailLabel.textAlignment = NSTextAlignmentCenter;
    _detailLabel.numberOfLines = 3;
    _detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_overlayView addSubview:_detailLabel];

    _retryButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_retryButton setTitle:@"Retry" forState:UIControlStateNormal];
    _retryButton.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    [_retryButton addTarget:self action:@selector(retryTapped) forControlEvents:UIControlEventTouchUpInside];
    _retryButton.translatesAutoresizingMaskIntoConstraints = NO;
    _retryButton.hidden = YES;
    [_overlayView addSubview:_retryButton];

    _settingsButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_settingsButton setTitle:@"Settings" forState:UIControlStateNormal];
    _settingsButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
    [_settingsButton addTarget:self action:@selector(settingsTapped) forControlEvents:UIControlEventTouchUpInside];
    _settingsButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_overlayView addSubview:_settingsButton];

    [NSLayoutConstraint activateConstraints:@[
        [_spinner.centerXAnchor constraintEqualToAnchor:_overlayView.centerXAnchor],
        [_spinner.centerYAnchor constraintEqualToAnchor:_overlayView.centerYAnchor constant:-50],

        [_statusLabel.topAnchor constraintEqualToAnchor:_spinner.bottomAnchor constant:20],
        [_statusLabel.centerXAnchor constraintEqualToAnchor:_overlayView.centerXAnchor],
        [_statusLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:_overlayView.leadingAnchor constant:20],
        [_statusLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_overlayView.trailingAnchor constant:-20],

        [_detailLabel.topAnchor constraintEqualToAnchor:_statusLabel.bottomAnchor constant:8],
        [_detailLabel.centerXAnchor constraintEqualToAnchor:_overlayView.centerXAnchor],
        [_detailLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:_overlayView.leadingAnchor constant:20],
        [_detailLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_overlayView.trailingAnchor constant:-20],

        [_retryButton.topAnchor constraintEqualToAnchor:_detailLabel.bottomAnchor constant:24],
        [_retryButton.centerXAnchor constraintEqualToAnchor:_overlayView.centerXAnchor],

        [_settingsButton.bottomAnchor constraintEqualToAnchor:_overlayView.safeAreaLayoutGuide.bottomAnchor constant:-20],
        [_settingsButton.trailingAnchor constraintEqualToAnchor:_overlayView.safeAreaLayoutGuide.trailingAnchor constant:-20],
    ]];
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

        self->_retryButton.hidden = !(isError || isStreamEnded);
        self->_settingsButton.hidden = isConnecting;
    });
}

- (void)showStreamEndedState {
    [self updateUI:GLStateStreamEnded status:@"Stream Ended" detail:@"Tap Retry to reconnect"];
}

#pragma mark - Connection Entry Point

- (void)startConnection {
    NSString* hostAddress = [[NSUserDefaults standardUserDefaults] stringForKey:kGLHostAddress];
    NSString* appName = [[NSUserDefaults standardUserDefaults] stringForKey:kGLAppName];

    if (hostAddress.length == 0 || appName.length == 0) {
        [self updateUI:GLStateUnconfigured status:@"Not Configured" detail:@"Tap Settings to set your host and app."];
        return;
    }

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

    [self performConnectionSequence:host];
}

- (void)performConnectionSequence:(TemporaryHost*)host {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_statusLabel.text = @"Getting server info…";
        });
        
        BOOL didSendWOL = false;
        BOOL hostDiscovered = false;
        NSString* error = @"";
        DiscoveryWorker* worker = [[DiscoveryWorker alloc] initWithHost:host uniqueId:@"main"];
        
        if (host.mac != nil && ![host.mac isEqualToString:@"00:00:00:00:00:00"]) {
            [WakeOnLanManager wakeHost:host];
            didSendWOL = true;
        }
        
        for (int i = 0, count = didSendWOL ? 30 : 1;
             i < count && ![worker discoverHostWithError:&error]; i++) {
            sleep(1);
        }
        
        if (host.state != StateOnline) {
            [self showError:@"Connection Failed" detail:error];
            return;
        }

        if (host.pairState == PairStatePaired) {
            [self fetchAppListAndLaunch:host];
        } else {
            HttpManager* hMan = [[HttpManager alloc] initWithHost:host];
            dispatch_async(dispatch_get_main_queue(), ^{
                PairManager* pMan = [[PairManager alloc] initWithManager:hMan clientCert:self->_clientCert callback:self];
                [self->_opQueue addOperation:pMan];
            });
        }
    });
}

- (void)fetchAppListAndLaunch:(TemporaryHost*)host {
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_statusLabel.text = @"Loading apps…";
    });

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        AppListResponse* appListResp = [ConnectionHelper getAppListForHost:host];

        if (![appListResp isStatusOk] || [appListResp getAppList] == nil) {
            [self showError:@"App List Failed" detail:appListResp.statusMessage];
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
                     detail:[NSString stringWithFormat:@"Could not find \"%@\" on the host. Check the app name in Settings.", targetName]];
            return;
        }

        // Resume target app if it's running; otherwise launch fresh
        TemporaryApp* appToStream = (runningApp != nil && [runningApp.id isEqualToString:targetApp.id]) ? runningApp : targetApp;

        [self prepareStreamConfigForApp:appToStream];

        dispatch_async(dispatch_get_main_queue(), ^{
            self->_streamingActive = YES;
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

    _streamConfig.frameRate = [settings.framerate intValue];
    if (@available(iOS 10.3, *)) {
        if (_streamConfig.frameRate > (int)[UIScreen mainScreen].maximumFramesPerSecond) {
            _streamConfig.frameRate = (int)[UIScreen mainScreen].maximumFramesPerSecond;
        }
    }
    _streamConfig.height = [settings.height intValue];
    _streamConfig.width = [settings.width intValue];
    _streamConfig.bitRate = [settings.bitrate intValue];
    _streamConfig.optimizeGameSettings = settings.optimizeGames;
    _streamConfig.playAudioOnPC = settings.playAudioOnPC;
    _streamConfig.useFramePacing = settings.useFramePacing;
    _streamConfig.swapABXYButtons = settings.swapABXYButtons;
    _streamConfig.multiController = settings.multiController;
    _streamConfig.gamepadMask = [ControllerSupport getConnectedGamepadMask:_streamConfig];

    int physicalChannels = (int)[AVAudioSession sharedInstance].maximumOutputNumberOfChannels;
    int channels = MIN([settings.audioConfig intValue], physicalChannels);
    if (channels >= 8) {
        _streamConfig.audioConfiguration = AUDIO_CONFIGURATION_71_SURROUND;
    } else if (channels >= 6) {
        _streamConfig.audioConfiguration = AUDIO_CONFIGURATION_51_SURROUND;
    } else {
        _streamConfig.audioConfiguration = AUDIO_CONFIGURATION_STEREO;
    }

    _streamConfig.serverCodecModeSupport = app.host.serverCodecModeSupport;

    switch (settings.preferredCodec) {
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
        (_streamConfig.width > 4096 || _streamConfig.height > 4096 || settings.enableHdr)) {
        _streamConfig.supportedVideoFormats |= VIDEO_FORMAT_H265;
        if (settings.enableHdr && (AVPlayer.availableHDRModes & AVPlayerHDRModeHDR10)) {
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
    if (_streamingActive) return;
    
    Log(LOG_I, @"GameLink activating -- starting connection");
    [self startConnection];
}

// This fires when the home button is pressed. If we're actively streaming,
// tell the host to quit the running app so it doesn't stay occupied.
- (void)applicationDidEnterBackground:(NSNotification *)notification {
    if (!_streamingActive || _streamConfig == nil) {
        return;
    }

    Log(LOG_I, @"GameLink backgrounded -- quitting host app");
    // Block until the quit request finishes; otherwise iOS tears the app down
    // before the request is sent and the host is left occupied.
    [self quitHostAppAndWait:YES];
}

// NOTE: applicationDidEnterBackground is called before this one
- (void)applicationWillTerminate:(NSNotification *)notification {
    if (!_streamingActive || _streamConfig == nil) {
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

- (void)showError:(NSString*)title detail:(NSString*)detail {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateUI:GLStateError status:title detail:detail];
    });
}

#pragma mark - Button Actions

- (void)retryTapped {
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
    // Persist the server cert immediately (on background thread, before main queue dispatch).
    self->_selectedHost.serverCert = serverCert;
    DataManager* dataMan = [[DataManager alloc] init];
    [dataMan updateHost:self->_selectedHost];

    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController* alert = self->_pairAlert;
        self->_pairAlert = nil;
        // Wait for the alert dismiss animation to finish before pushing the stream view,
        // otherwise performSegueWithIdentifier: fails while a VC is still being presented.
        if (alert) {
            [alert dismissViewControllerAnimated:YES completion:^{
                [self fetchAppListAndLaunch:self->_selectedHost];
            }];
        } else {
            [self fetchAppListAndLaunch:self->_selectedHost];
        }
    });
}

- (void)pairFailed:(NSString*)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController* alert = self->_pairAlert;
        self->_pairAlert = nil;
        if (alert) {
            [alert dismissViewControllerAnimated:YES completion:^{
                [self showError:@"Pairing Failed" detail:message];
            }];
        } else {
            [self showError:@"Pairing Failed" detail:message];
        }
    });
}

- (void)alreadyPaired {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController* alert = self->_pairAlert;
        self->_pairAlert = nil;
        if (alert) {
            [alert dismissViewControllerAnimated:YES completion:^{
                [self fetchAppListAndLaunch:self->_selectedHost];
            }];
        } else {
            [self fetchAppListAndLaunch:self->_selectedHost];
        }
    });
}

@end
