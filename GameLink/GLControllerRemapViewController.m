//
//  GLControllerRemapViewController.m
//  GameLink
//

#import "GLControllerRemapViewController.h"
#import "GLControllerNavigator.h"
#import "ControllerButtonRemap.h"

#pragma mark - Physical button picker

// Pushed selection list of physical buttons (+ None). Reports the picked flag
// through its completion block.
@interface GLButtonPickerViewController : UITableViewController
@property (nonatomic, copy) void (^onPick)(int flag);
- (instancetype)initWithCurrentFlag:(int)currentFlag;
@end

@implementation GLButtonPickerViewController {
    NSArray<NSDictionary *>* _options;
    int _currentFlag;
}

- (instancetype)initWithCurrentFlag:(int)currentFlag {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _options = [ControllerButtonRemap targetButtons];
        _currentFlag = currentFlag;
        self.title = @"Physical Button";
    }
    return self;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _options.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString* identifier = @"targetCell";
    UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                      reuseIdentifier:identifier];
    }
    NSDictionary* option = _options[indexPath.row];
    cell.textLabel.text = option[@"name"];
    cell.accessoryType = ([option[@"flag"] intValue] == _currentFlag)
        ? UITableViewCellAccessoryCheckmark
        : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    int flag = [_options[indexPath.row][@"flag"] intValue];
    if (self.onPick) {
        self.onPick(flag);
    }
    [self.navigationController popViewControllerAnimated:YES];
}

@end

#pragma mark - Remap screen

@interface GLControllerRemapViewController () <GLControllerNavigatorDelegate>
@end

@implementation GLControllerRemapViewController {
    NSString* _key;
    NSString* _name;
    NSArray<NSDictionary *>* _outputs;                     // host output buttons (rows)
    NSMutableDictionary<NSNumber *, NSNumber *>* _mapping;  // physical(source) flag -> output(target) flag

    GLControllerNavigator* _navigator;
    NSInteger _highlightedRow;
    BOOL _capturing;
    UIView* _captureOverlay;
    UILabel* _captureLabel;
}

- (instancetype)initWithControllerKey:(NSString *)key displayName:(NSString *)name {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _key = [key copy];
        _name = [name copy];
        _outputs = [ControllerButtonRemap remappableButtons];
        _mapping = [[ControllerButtonRemap mappingForControllerKey:key] mutableCopy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = _name;
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Reset"
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(resetTapped)];
    _highlightedRow = 0;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    _navigator = [[GLControllerNavigator alloc] initWithControllerKey:_key];
    _navigator.delegate = self;
    [_navigator attach];

    if (_navigator.hasController) {
        [self highlightRow:_highlightedRow];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self endCapture];
    [_navigator detach];
    _navigator = nil;
}

#pragma mark - Mapping model (stored as physical -> output; displayed output -> physical)

// What output a physical button currently emits (identity if not remapped).
- (int)outputForPhysical:(int)physical {
    NSNumber* target = _mapping[@(physical)];
    return target != nil ? target.intValue : physical;
}

// Which physical button currently produces a given output, or 0 if none.
- (int)physicalForOutput:(int)output {
    for (NSDictionary* button in _outputs) {
        int physical = [button[@"flag"] intValue];
        if ([self outputForPhysical:physical] == output) {
            return physical;
        }
    }
    return 0;
}

- (void)setPhysical:(int)physical toOutput:(int)output {
    if (output == physical) {
        [_mapping removeObjectForKey:@(physical)];   // identity
    } else {
        _mapping[@(physical)] = @(output);
    }
}

// Make `physical` produce `output`. To keep each output driven by a distinct
// physical button, swap targets with whatever physical currently produces it.
- (void)assignOutput:(int)output physical:(int)physical {
    if (physical == 0) {
        // Disable: whatever produces this output is turned off.
        int current = [self physicalForOutput:output];
        if (current != 0) {
            _mapping[@(current)] = @(0);
        }
    } else {
        int currentProducer = [self physicalForOutput:output];   // may be 0
        if (currentProducer == physical) {
            return; // already mapped
        }
        int displacedOutput = [self outputForPhysical:physical];  // what P emitted before
        [self setPhysical:physical toOutput:output];
        if (currentProducer != 0) {
            // Give the old producer P's previous output so nothing is lost.
            [self setPhysical:currentProducer toOutput:displacedOutput];
        }
    }

    [ControllerButtonRemap saveMapping:_mapping forControllerKey:_key];
    [self.tableView reloadData];
    [self highlightRow:_highlightedRow];
}

#pragma mark - Controller highlight

- (void)highlightRow:(NSInteger)row {
    if (row < 0) row = 0;
    if (row >= (NSInteger)_outputs.count) row = _outputs.count - 1;
    _highlightedRow = row;

    NSIndexPath* indexPath = [NSIndexPath indexPathForRow:row inSection:0];
    [self.tableView selectRowAtIndexPath:indexPath
                                animated:NO
                          scrollPosition:UITableViewScrollPositionMiddle];
}

#pragma mark - Capture mode

- (void)beginCaptureForRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_outputs.count) {
        return;
    }
    _highlightedRow = row;
    _capturing = YES;
    _navigator.captureMode = YES;

    NSString* outputName = _outputs[row][@"name"];
    [self showCaptureOverlayForOutput:outputName];
}

- (void)endCapture {
    _capturing = NO;
    if (_navigator) {
        _navigator.captureMode = NO;
    }
    [self hideCaptureOverlay];
}

- (void)showCaptureOverlayForOutput:(NSString*)outputName {
    UIView* host = self.navigationController.view ?: self.view;

    _captureOverlay = [[UIView alloc] initWithFrame:host.bounds];
    _captureOverlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _captureOverlay.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.75];

    _captureLabel = [[UILabel alloc] init];
    _captureLabel.numberOfLines = 0;
    _captureLabel.textAlignment = NSTextAlignmentCenter;
    _captureLabel.textColor = [UIColor whiteColor];
    _captureLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightSemibold];
    _captureLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _captureLabel.text = [NSString stringWithFormat:@"Press the physical button for\n\"%@\"", outputName];
    [_captureOverlay addSubview:_captureLabel];

    UIButton* cancelButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [cancelButton setTitle:@"Cancel" forState:UIControlStateNormal];
    [cancelButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    cancelButton.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightRegular];
    cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    [cancelButton addTarget:self action:@selector(captureCancelTapped) forControlEvents:UIControlEventTouchUpInside];
    [_captureOverlay addSubview:cancelButton];

    [host addSubview:_captureOverlay];

    [NSLayoutConstraint activateConstraints:@[
        [_captureLabel.centerXAnchor constraintEqualToAnchor:_captureOverlay.centerXAnchor],
        [_captureLabel.centerYAnchor constraintEqualToAnchor:_captureOverlay.centerYAnchor],
        [_captureLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:_captureOverlay.leadingAnchor constant:20],
        [_captureLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_captureOverlay.trailingAnchor constant:-20],

        [cancelButton.topAnchor constraintEqualToAnchor:_captureLabel.bottomAnchor constant:24],
        [cancelButton.centerXAnchor constraintEqualToAnchor:_captureOverlay.centerXAnchor],
    ]];
}

- (void)hideCaptureOverlay {
    [_captureOverlay removeFromSuperview];
    _captureOverlay = nil;
    _captureLabel = nil;
}

- (void)captureCancelTapped {
    [self endCapture];
}

#pragma mark - GLControllerNavigatorDelegate

- (void)navigatorMove:(int)delta {
    if (_capturing) {
        return;
    }
    [self highlightRow:_highlightedRow + delta];
}

- (void)navigatorConfirm {
    if (_capturing) {
        return;
    }
    [self beginCaptureForRow:_highlightedRow];
}

- (void)navigatorCancel {
    if (_capturing) {
        [self endCapture];
    } else {
        [self.navigationController popViewControllerAnimated:YES];
    }
}

- (void)navigatorCapturedFlag:(int)flag {
    if (!_capturing) {
        return;
    }

    int output = [_outputs[_highlightedRow][@"flag"] intValue];
    [self endCapture];
    // flag is the pressed physical button's natural flag.
    [self assignOutput:output physical:flag];
}

- (void)resetTapped {
    UIAlertController* confirm =
        [UIAlertController alertControllerWithTitle:@"Reset Mapping"
                                            message:@"Restore all buttons on this controller to their defaults?"
                                     preferredStyle:UIAlertControllerStyleAlert];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                style:UIAlertActionStyleCancel
                                              handler:nil]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Reset"
                                                style:UIAlertActionStyleDestructive
                                              handler:^(UIAlertAction* action) {
        [self->_mapping removeAllObjects];
        [ControllerButtonRemap clearMappingForControllerKey:self->_key];
        [self.tableView reloadData];
    }]];
    [self presentViewController:confirm animated:YES completion:nil];
}

#pragma mark - Table view

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _outputs.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @"Output  ◄  Physical Button";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @"Each row is a host output. With a controller: D-pad to move, A to "
            "select an output, then press the physical button that should trigger "
            "it. B cancels or goes back.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString* identifier = @"outputCell";
    UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
                                      reuseIdentifier:identifier];
    }

    NSDictionary* output = _outputs[indexPath.row];
    int outputFlag = [output[@"flag"] intValue];
    int physical = [self physicalForOutput:outputFlag];
    BOOL remapped = (physical != outputFlag);

    cell.textLabel.text = output[@"name"];   // left: desired output
    cell.detailTextLabel.text = [ControllerButtonRemap nameForFlag:physical]; // right: physical button
    cell.detailTextLabel.textColor = remapped ? [UIColor systemBlueColor] : [UIColor secondaryLabelColor];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    int output = [_outputs[indexPath.row][@"flag"] intValue];

    GLButtonPickerViewController* picker =
        [[GLButtonPickerViewController alloc] initWithCurrentFlag:[self physicalForOutput:output]];
    __weak GLControllerRemapViewController* weakSelf = self;
    picker.onPick = ^(int physical) {
        GLControllerRemapViewController* strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        [strongSelf assignOutput:output physical:physical];
    };
    [self.navigationController pushViewController:picker animated:YES];
}

@end
