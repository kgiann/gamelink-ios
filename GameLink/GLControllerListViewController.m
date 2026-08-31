//
//  GLControllerListViewController.m
//  GameLink
//

#import "GLControllerListViewController.h"
#import "GLControllerRemapViewController.h"
#import "GLControllerNavigator.h"
#import "ControllerButtonRemap.h"

@import GameController;

@interface GLControllerListViewController () <GLControllerNavigatorDelegate>
@end

@implementation GLControllerListViewController {
    // Each entry: @{ @"key": NSString, @"name": NSString, @"connected": NSNumber(BOOL) }
    NSArray<NSDictionary *>* _items;

    GLControllerNavigator* _navigator;
    NSInteger _highlightedRow;
}

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Controllers";

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reload)
                                                 name:GCControllerDidConnectNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reload)
                                                 name:GCControllerDidDisconnectNotification
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // Reload so newly-saved custom mappings show up when coming back.
    [self reload];

    _navigator = [[GLControllerNavigator alloc] initWithControllerKey:nil];
    _navigator.delegate = self;
    [_navigator attach];
    if (_navigator.hasController && _items.count > 0) {
        [self highlightRow:_highlightedRow];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [_navigator detach];
    _navigator = nil;
}

#pragma mark - Controller navigation

- (void)highlightRow:(NSInteger)row {
    if (_items.count == 0) {
        return;
    }
    if (row < 0) row = 0;
    if (row >= (NSInteger)_items.count) row = _items.count - 1;
    _highlightedRow = row;
    [self.tableView selectRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:0]
                                animated:NO
                          scrollPosition:UITableViewScrollPositionMiddle];
}

- (void)openItemAtRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_items.count) {
        return;
    }
    NSDictionary* item = _items[row];
    GLControllerRemapViewController* vc =
        [[GLControllerRemapViewController alloc] initWithControllerKey:item[@"key"]
                                                          displayName:item[@"name"]];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)navigatorMove:(int)delta {
    [self highlightRow:_highlightedRow + delta];
}

- (void)navigatorConfirm {
    [self openItemAtRow:_highlightedRow];
}

- (void)navigatorCancel {
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)navigatorCapturedFlag:(int)flag {
    // Not used on this screen.
}

- (void)reload {
    NSMutableArray<NSDictionary *>* items = [NSMutableArray array];
    NSMutableSet<NSString *>* seen = [NSMutableSet set];

    // Currently-connected supported controllers
    for (GCController* controller in [GCController controllers]) {
        if (controller.extendedGamepad == nil) {
            continue;
        }
        NSString* key = [ControllerButtonRemap keyForGamepad:controller];
        if ([seen containsObject:key]) {
            continue;
        }
        [seen addObject:key];
        [items addObject:@{
            @"key": key,
            @"name": (controller.vendorName ?: key),
            @"connected": @YES,
        }];
    }

    // Controllers that have a saved mapping but aren't connected right now
    for (NSString* key in [ControllerButtonRemap savedControllerKeys]) {
        if ([seen containsObject:key]) {
            continue;
        }
        [seen addObject:key];
        NSString* name = [[key componentsSeparatedByString:@"|"] firstObject] ?: key;
        [items addObject:@{
            @"key": key,
            @"name": name,
            @"connected": @NO,
        }];
    }

    _items = items;
    [self.tableView reloadData];
}

#pragma mark - Table view

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _items.count == 0 ? 1 : _items.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @"Mappings are saved per controller model and reused whenever that "
            "controller is connected.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString* identifier = @"controllerCell";
    UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                      reuseIdentifier:identifier];
    }

    if (_items.count == 0) {
        cell.textLabel.text = @"No controllers connected";
        cell.detailTextLabel.text = @"Connect a controller to configure it.";
        cell.textLabel.textColor = [UIColor secondaryLabelColor];
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    NSDictionary* item = _items[indexPath.row];
    cell.textLabel.text = item[@"name"];
    cell.textLabel.textColor = [UIColor labelColor];
    cell.detailTextLabel.text = [item[@"connected"] boolValue] ? @"Connected" : @"Not connected";
    cell.detailTextLabel.textColor = [item[@"connected"] boolValue]
        ? [UIColor systemGreenColor]
        : [UIColor secondaryLabelColor];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (_items.count == 0) {
        return;
    }

    NSDictionary* item = _items[indexPath.row];
    GLControllerRemapViewController* vc =
        [[GLControllerRemapViewController alloc] initWithControllerKey:item[@"key"]
                                                          displayName:item[@"name"]];
    [self.navigationController pushViewController:vc animated:YES];
}

@end
