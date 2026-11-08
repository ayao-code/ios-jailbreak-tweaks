#import "FeilianVPNController.h"
#import "VPNPrivate.h"
#import "FeilianRequest.h"
#import <dlfcn.h>

@interface NSObject (FeilianSystemLaunch)
+ (instancetype)sharedService;
- (void)openApplication:(NSString *)identifier options:(NSDictionary *)options withResult:(void (^)(NSError *))result;
@end

static NSString *const FeilianBundleID = @"com.volcengine.corplink";

@interface FeilianVPNController ()
@property (nonatomic, readwrite) BOOL selected;
@property (nonatomic, readwrite) BOOL busy;
@property (nonatomic, readwrite) BOOL available;
@property (nonatomic, readwrite) BOOL connected;
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, strong) id store;
@property (nonatomic, strong) id statusObserver;
@property (nonatomic, strong) id configurationObserver;
@property (nonatomic, strong) dispatch_source_t deadlineTimer;
@property (nonatomic, strong) id pendingConnection;
@property (nonatomic) BOOL pendingSelected;
@property (nonatomic) BOOL requestPending;
@property (nonatomic) int requestToken;
@property (nonatomic) int resultToken;
@property (nonatomic) uint64_t requestID;
@end

@implementation FeilianVPNController

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _requestToken = NOTIFY_TOKEN_INVALID;
    _resultToken = NOTIFY_TOKEN_INVALID;
    notify_register_check(FeilianRequestName, &_requestToken);
    _queue = dispatch_queue_create("ayao.feilian.vpn", DISPATCH_QUEUE_SERIAL);
    __weak typeof(self) weakSelf = self;
    notify_register_dispatch(FeilianResultName, &_resultToken, _queue, ^(int token) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf || !strongSelf.requestPending) return;
        uint64_t result = 0;
        if (notify_get_state(token, &result) != NOTIFY_STATUS_OK || result / 256 != strongSelf.requestID) return;
        FeilianResult code = (FeilianResult)(result % 256);
        if (code != FeilianResultStarted) {
            [strongSelf failOnQueue:code == FeilianResultInteractionRequired ?
                @"飞连需要登录或身份验证，请手动打开飞连处理。本次未跳转。" :
                @"飞连无法完成后台连接，请手动打开飞连检查。本次未跳转。"];
        }
        [strongSelf updateOnQueue];
    });
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    _statusObserver = [center addObserverForName:@"VPNConnectionStatusChanged" object:nil queue:nil usingBlock:^(NSNotification *note) {
        [weakSelf reload];
    }];
    _configurationObserver = [center addObserverForName:@"VPNNEConfigurationChangedNotification" object:nil queue:nil usingBlock:^(NSNotification *note) {
        [weakSelf reload];
    }];
    dispatch_async(_queue, ^{
        NSError *error = nil;
        NSBundle *bundle = [NSBundle bundleWithPath:@"/System/Library/PreferenceBundles/VPNPreferences.bundle"];
        if ([bundle loadAndReturnError:&error]) {
            Class storeClass = NSClassFromString(@"VPNConnectionStore");
            if ([storeClass respondsToSelector:@selector(sharedInstance)]) self.store = [storeClass sharedInstance];
        }
        if (!self.store) NSLog(@"[FeilianCC] VPNPreferences unavailable: %@", error.localizedDescription);
        [self updateOnQueue];
    });
    return self;
}

- (void)dealloc {
    if (_statusObserver) [NSNotificationCenter.defaultCenter removeObserver:_statusObserver];
    if (_configurationObserver) [NSNotificationCenter.defaultCenter removeObserver:_configurationObserver];
    if (_deadlineTimer) dispatch_source_cancel(_deadlineTimer);
    if (_requestToken != NOTIFY_TOKEN_INVALID) notify_cancel(_requestToken);
    if (_resultToken != NOTIFY_TOKEN_INVALID) notify_cancel(_resultToken);
}

- (NSArray *)connectionsOnQueue {
    if (![self.store respondsToSelector:@selector(vpnServicesForCurrentSetWithGrade:)] ||
        ![self.store respondsToSelector:@selector(connectionWithServiceID:withGrade:)]) return @[];
    NSMutableArray *connections = [NSMutableArray array];
    // Enumerate the four grades exposed by iOS 16 VPNConnectionStore.
    for (NSUInteger grade = 0; grade < 4; grade++) {
        id identifiers = [self.store vpnServicesForCurrentSetWithGrade:grade];
        if (![identifiers isKindOfClass:NSArray.class]) continue;
        for (id identifier in identifiers) {
            id connection = [self.store connectionWithServiceID:identifier withGrade:grade];
            if ([connection respondsToSelector:@selector(bundleID)] &&
                [connection respondsToSelector:@selector(connected)] &&
                [connection respondsToSelector:@selector(notDisconnectedOrDisconnecting)]) {
                [connections addObject:connection];
            }
        }
    }
    return connections;
}

- (void)publishSelected:(BOOL)selected available:(BOOL)available connected:(BOOL)connected {
    BOOL busy = self.requestPending;
    dispatch_async(dispatch_get_main_queue(), ^{
        self.selected = selected;
        self.available = available;
        self.connected = connected;
        self.busy = busy;
        if (self.stateChanged) self.stateChanged();
    });
}

- (void)finishRequestOnQueue {
    self.requestPending = NO;
    self.pendingConnection = nil;
    if (self.requestToken != NOTIFY_TOKEN_INVALID) notify_set_state(self.requestToken, 0);
    if (self.deadlineTimer) dispatch_source_cancel(self.deadlineTimer);
    self.deadlineTimer = nil;
}

- (void)failOnQueue:(NSString *)message {
    [self finishRequestOnQueue];
    dispatch_async(dispatch_get_main_queue(), ^{
        self.busy = NO;
        if (self.operationFailed) self.operationFailed(message);
    });
}

- (void)updateOnQueue {
    NSArray *connections = [self connectionsOnQueue];
    NSUInteger matches = 0;
    id target = nil;
    for (id connection in connections) {
        if ([[connection bundleID] isEqualToString:FeilianBundleID]) { matches++; target = connection; }
    }
    BOOL available = matches == 1 && [target respondsToSelector:@selector(isProviderAvailable)] && [target isProviderAvailable];
    BOOL selected = available && [target notDisconnectedOrDisconnecting];
    if (self.requestPending && matches == 1 && ((self.pendingSelected && [target connected]) ||
        (!self.pendingSelected && ![target notDisconnectedOrDisconnecting]))) {
        NSLog(@"[FeilianCC] request completed connected=%d", [target connected]);
        [self finishRequestOnQueue];
    }
    [self publishSelected:selected available:available connected:available && [target connected]];
}

- (void)reload {
    dispatch_async(self.queue, ^{ [self updateOnQueue]; });
}

- (void)requestSelected:(BOOL)selected {
    // The CC callback never waits for configuration loading or tunnel startup.
    dispatch_async(self.queue, ^{
        if (self.requestPending) return;
        NSArray *connections = [self connectionsOnQueue];
        NSMutableArray *matches = [NSMutableArray array];
        for (id connection in connections) {
            if ([[connection bundleID] isEqualToString:FeilianBundleID]) [matches addObject:connection];
            else if (selected && [connection notDisconnectedOrDisconnecting]) {
                [self failOnQueue:@"另一个 VPN 正在使用。请先关闭它，飞连按钮不会替换其他连接。"];
                return;
            }
        }
        if (matches.count != 1) {
            [self failOnQueue:@"未找到唯一的飞连 VPN 配置。请先在飞连中完成登录和 VPN 配置。"];
            return;
        }
        id target = matches.firstObject;
        SEL action = selected ? @selector(connect) : @selector(disconnect);
        if (![target respondsToSelector:action] || ![target respondsToSelector:@selector(isProviderAvailable)] || ![target isProviderAvailable]) {
            [self failOnQueue:@"飞连 VPN 扩展不可用，请打开飞连检查配置。"];
            return;
        }
        if ((selected && [target connected]) || (!selected && ![target notDisconnectedOrDisconnecting])) {
            [self updateOnQueue];
            return;
        }
        self.requestPending = YES;
        self.pendingSelected = selected;
        self.pendingConnection = target;
        // One timeout per user operation, not a repeating status poll.
        self.deadlineTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.queue);
        dispatch_source_set_timer(self.deadlineTimer, dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC), DISPATCH_TIME_FOREVER, NSEC_PER_SEC / 10);
        __weak typeof(self) weakSelf = self;
        dispatch_source_set_event_handler(self.deadlineTimer, ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf updateOnQueue];
            if (strongSelf.requestPending) {
                [strongSelf failOnQueue:@"飞连未完成连接切换。请打开飞连检查登录、身份验证和网络状态。"];
                [strongSelf updateOnQueue];
            }
        });
        dispatch_resume(self.deadlineTimer);
        NSLog(@"[FeilianCC] request connect=%d", selected);
        if (selected) {
            dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices", RTLD_NOW);
            Class serviceClass = NSClassFromString(@"FBSSystemService");
            id service = [serviceClass respondsToSelector:@selector(sharedService)] ? [serviceClass sharedService] : nil;
            NSString *const *backgroundKey = (NSString *const *)dlsym(RTLD_DEFAULT, "FBSOpenApplicationOptionKeyActivateSuspended");
            self.requestID = (uint64_t)((NSDate.date.timeIntervalSince1970 + FeilianRequestLifetime) * 1000);
            uint64_t requestID = self.requestID;
            if (![service respondsToSelector:@selector(openApplication:options:withResult:)] || !backgroundKey || !*backgroundKey ||
                self.requestToken == NOTIFY_TOKEN_INVALID ||
                notify_set_state(self.requestToken, self.requestID) != NOTIFY_STATUS_OK) {
                [self failOnQueue:@"飞连后台连接入口不可用。本次未跳转。"];
                [self updateOnQueue];
                return;
            }
            [service openApplication:FeilianBundleID
                options:@{*backgroundKey: @YES}
                withResult:^(NSError *error) {
                    dispatch_async(self.queue, ^{
                        if (!self.requestPending || self.requestID != requestID) return;
                        if (!error) { notify_post(FeilianRequestName); return; }
                        if (self.requestPending) {
                            [self failOnQueue:@"无法后台唤醒飞连，请解锁手机后重试。本次未跳转。"];
                            [self updateOnQueue];
                        }
                    });
                }];
        } else [target disconnect];
        [self updateOnQueue];
    });
}
@end
