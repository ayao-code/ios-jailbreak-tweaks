#import "VPNController.h"
#import "VPNPrivate.h"
#import "Shared/VPNIPC.h"
#import <dlfcn.h>
#import <mach/mach.h>
#import <notify.h>

@interface NSObject (VPNSystemAPI)
+ (instancetype)sharedService;
- (void)openApplication:(NSString *)identifier options:(NSDictionary *)options withResult:(void (^)(NSError *))result;
- (id)configurations;
- (unsigned int)vpnServiceCountDirty;
@end

static NSString *const PreferenceDomain = @"ayao.feiliancontrolcenter";
static NSString *HelperFailure(NSString *provider) {
    int token=NOTIFY_TOKEN_INVALID;uint64_t stage=0;
    NSString *name=[NSString stringWithFormat:@"ayao.vpn.%@.server.diagnostic-stage.v1",provider];
    if(notify_register_check(name.UTF8String,&token)==NOTIFY_STATUS_OK){notify_get_state(token,&stage);notify_cancel(token);}
    // Diagnostic text only. This notification never authenticates or authorizes a request.
    return stage==401 ? @"App 沙盒禁止校验宿主身份，IPC 请求被安全拒绝" :
        @"连接辅助未响应，请检查 App List 和 App 版本";
}
NSString *VPNProviderName(NSString *provider) {
    if ([provider isEqualToString:@"easy"]) return @"Easy VPN";
    if ([provider isEqualToString:@"feilian"]) return @"飞连";
    if ([provider isEqualToString:@"hotspot"]) return @"Hotspot VPN";
    if ([provider isEqualToString:@"gofast"]) return @"GOFast VPN";
    if ([provider isEqualToString:@"jump"]) return @"Jump VPN";
    if ([provider isEqualToString:@"external"]) return @"其他 VPN";
    if ([provider isEqualToString:@"unknown"]) return @"状态未知";
    if ([provider isEqualToString:@"ambiguous"]) return @"多个活动 VPN";
    return @"未连接";
}
static BOOL Unlocked(void) {
    dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_NOW);
    mach_port_t (*port)(void) = dlsym(RTLD_DEFAULT, "SBSSpringBoardServerPort");
    void (*query)(mach_port_t, BOOL *, BOOL *) = dlsym(RTLD_DEFAULT, "SBGetScreenLockStatus");
    if (!port || !query || port() == MACH_PORT_NULL) return NO;
    BOOL locked = (BOOL)-1, passcode = (BOOL)-1;
    query(port(), &locked, &passcode); return locked == NO;
}

@interface AYAVPNController ()
@property (nonatomic, copy, readwrite) NSString *preferredProvider, *activeProvider, *message;
@property (nonatomic, readwrite) BOOL ready, busy, connected, failed;
@end

@implementation AYAVPNController {
    dispatch_queue_t _queue, _ipcQueue;
    id _store, _stateObserver, _configurationObserver;
    NSDictionary *_snapshot;
    NSUInteger _revision;
    uint64_t _generation;
    uint64_t _timeoutRevision;
    BOOL _pending, _primed, _helperConfirmed, _sourceStopped, _stopConfirmed, _receivedStateEvent, _stateReady, _failed;
    NSDictionary *_initialState;
    NSUInteger _stableInitialReads;
    NSString *_targetProvider, *_saveOnSuccess, *_sourceProvider;
    NSString *_phase;
    NSDictionary *_profiles;
    NSDictionary *_operationProfiles;
    NSString *_preferred, *_lastMessage;
    VPNIPCClient *_client;
    dispatch_source_t _timer;
    CFAbsoluteTime _startedAt, _targetStableAt;
    BOOL _settleScheduled, _replyTimedOut;
    NSDictionary *_lastLoggedState;
}
- (instancetype)init {
    if (!(self = [super init])) return nil;
    _preferredProvider = @"easy"; _activeProvider = @"unknown"; _message = @"正在读取 VPN 状态";
    CFPropertyListRef value = CFPreferencesCopyAppValue(CFSTR("preferredProvider"), (__bridge CFStringRef)PreferenceDomain);
    if (value) {
        id object = CFBridgingRelease(value);
        if ([VPNProviders() containsObject:object]) _preferredProvider = object;
    }
    _preferred = _preferredProvider; _lastMessage = _message;
    _queue = dispatch_queue_create("ayao.vpn.controller", DISPATCH_QUEUE_SERIAL);
    _ipcQueue = dispatch_queue_create("ayao.vpn.ipc", DISPATCH_QUEUE_SERIAL);
    __weak typeof(self) weakSelf = self;
    _stateObserver = [NSNotificationCenter.defaultCenter addObserverForName:@"VPNConnectionStatusChanged"
        object:nil queue:nil usingBlock:^(NSNotification *note) {
            (void)note;
            typeof(self) strongSelf = weakSelf;
            if (strongSelf) dispatch_async(strongSelf->_queue, ^{ strongSelf->_receivedStateEvent = YES; [strongSelf update]; });
        }];
    _configurationObserver = [NSNotificationCenter.defaultCenter addObserverForName:@"VPNNEConfigurationChangedNotification"
        object:nil queue:nil usingBlock:^(NSNotification *note) { (void)note; [weakSelf reload]; }];
    dispatch_async(_queue, ^{
        NSBundle *bundle = [NSBundle bundleWithPath:@"/System/Library/PreferenceBundles/VPNPreferences.bundle"];
        if ([bundle load]) {
            Class cls = NSClassFromString(@"VPNConnectionStore");
            if ([cls respondsToSelector:@selector(sharedInstance)]) self->_store = [cls sharedInstance];
        }
        [self update];
        // Bounded initialization retry; a timer alone never establishes readiness.
        for (NSUInteger delay = 1; delay <= 3; delay++) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, delay * NSEC_PER_SEC), self->_queue, ^{ [self update]; });
    });
    return self;
}
- (NSArray *)connections {
    if (![_store respondsToSelector:@selector(vpnServicesForCurrentSetWithGrade:)] ||
        ![_store respondsToSelector:@selector(connectionWithServiceID:withGrade:)]) return nil;
    NSMutableArray *result = [NSMutableArray array];
    NSMutableDictionary *profiles = [NSMutableDictionary dictionary];
    for (NSUInteger grade = 0; grade < 4; grade++) {
        id services = [_store vpnServicesForCurrentSetWithGrade:grade];
        if (![services isKindOfClass:NSArray.class]) return nil;
        for (id identifier in services) {
            id connection = [_store connectionWithServiceID:identifier withGrade:grade];
            for (NSString *method in @[@"bundleID", @"connected", @"notDisconnectedOrDisconnecting", @"status", @"isProviderAvailable"])
                if (![connection respondsToSelector:NSSelectorFromString(method)]) return nil;
            NSString *key = [NSString stringWithFormat:@"%lu:%@", (unsigned long)grade, identifier];
            profiles[key] = connection;
            [result addObject:@{@"key": key, @"connection": connection}];
        }
    }
    _profiles = profiles; return result;
}
- (NSString *)providerFor:(id)connection {
    for (NSString *provider in VPNProviders())
        if ([[connection bundleID] isEqualToString:VPNBundle(provider)]) return provider;
    return @"external";
}
- (NSDictionary *)profileFor:(NSString *)provider {
    NSMutableArray *matches = [NSMutableArray array];
    [_profiles enumerateKeysAndObjectsUsingBlock:^(NSString *key, id connection, BOOL *stop) {
        (void)stop;
        if ([[self providerFor:connection] isEqualToString:provider]) [matches addObject:@{@"key":key, @"connection":connection}];
    }];
    return matches.count == 1 ? matches.firstObject : nil;
}
- (void)publish:(NSDictionary *)snapshot {
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self->_snapshot isEqual:snapshot]) return;
        self->_revision++;
        self->_snapshot = snapshot;
        self.ready = [snapshot[@"ready"] boolValue]; self.busy = [snapshot[@"busy"] boolValue];
        self.connected = [snapshot[@"connected"] boolValue]; self.activeProvider = snapshot[@"active"];
        self.failed = [snapshot[@"failed"] boolValue];
        self.message = snapshot[@"message"]; self.preferredProvider = snapshot[@"preferred"];
        if (self.stateChanged) self.stateChanged();
    });
}
- (void)update {
    NSArray *connections = [self connections];
    BOOL configured = connections != nil && [_store respondsToSelector:@selector(configurations)] && [_store configurations] != nil;
    NSMutableDictionary *initialState = [NSMutableDictionary dictionary];
    for (NSDictionary *entry in connections) initialState[entry[@"key"]] = @([entry[@"connection"] status]);
    // SpringBoard may already own a loaded store and send no new init event.
    // Require a nonempty loaded configuration set and bounded stable snapshots.
    if (configured && initialState.count && [_initialState isEqual:initialState]) _stableInitialReads++;
    else _stableInitialReads = 0;
    _initialState = initialState;
    BOOL loaded = _primed && configured && (_receivedStateEvent || _stableInitialReads >= 2);
    _primed = YES;
    _stateReady = loaded;
    if (!loaded && !_pending) _lastMessage = _store ? @"正在读取 VPN 配置和连接状态" : @"系统 VPN 状态接口不可用";
    else if (loaded && [_lastMessage hasPrefix:@"正在读取"]) _lastMessage = @"就绪";
    NSMutableDictionary *states = [NSMutableDictionary dictionary];
    NSMutableDictionary *identities = [NSMutableDictionary dictionary];
    NSMutableArray *active = [NSMutableArray array];
    for (NSString *provider in VPNProviders()) {
        NSDictionary *profile = [self profileFor:provider]; id connection = profile[@"connection"];
        if (profile) identities[provider] = profile[@"key"];
        states[provider] = !profile ? @"配置不存在或不唯一" : (![connection isProviderAvailable] ? @"VPN 扩展不可用" :
            ([connection connected] ? @"已连接" : ([connection notDisconnectedOrDisconnecting] ? @"连接中" : @"未连接")));
    }
    for (NSDictionary *entry in connections) if ([entry[@"connection"] notDisconnectedOrDisconnecting]) [active addObject:entry];
    NSString *activeProvider = !loaded || !connections ? @"unknown" : (active.count > 1 ? @"ambiguous" :
        (active.count == 1 ? [self providerFor:active.firstObject[@"connection"]] : @"none"));
    BOOL connected = active.count == 1 && [active.firstObject[@"connection"] connected] && loaded;
    if (_pending) [self progress:loaded active:active];
    NSString *preferred = _preferred ?: @"easy";
    [self publish:@{@"ready":@(loaded && connections != nil), @"busy":@(_pending), @"connected":@(connected),
        @"active":activeProvider, @"preferred":preferred, @"message":_lastMessage ?: @"", @"states":states,
        @"identities":identities, @"failed":@(_failed)}];
}
- (void)reload { dispatch_async(_queue, ^{ [self update]; }); }
- (NSString *)statusForProvider:(NSString *)provider { return _snapshot[@"states"][provider] ?: @"正在读取"; }
- (BOOL)canSelectProvider:(NSString *)provider {
    return self.ready && !self.busy && [@[@"未连接", @"连接中", @"已连接"] containsObject:[self statusForProvider:provider]];
}
- (NSDictionary *)selectionIntent:(NSString *)provider {
    if (![self canSelectProvider:provider]) return nil;
    return @{@"provider":provider, @"revision":@(_revision), @"active":self.activeProvider,
        @"profiles":_snapshot[@"identities"] ?: @{}};
}
- (void)savePreference:(NSString *)provider {
    CFPreferencesSetAppValue(CFSTR("preferredProvider"), (__bridge CFStringRef)provider, (__bridge CFStringRef)PreferenceDomain);
    CFPreferencesSetAppValue(CFSTR("schemaVersion"), (__bridge CFNumberRef)@1, (__bridge CFStringRef)PreferenceDomain);
    if (!CFPreferencesAppSynchronize((__bridge CFStringRef)PreferenceDomain)) { _lastMessage = @"连接状态已更新，但选择保存失败"; return; }
    _preferred = provider;
}
- (void)applySelection:(NSDictionary *)intent {
    // Called on main; the confirmation's revision must still match the displayed state.
    if (!intent || [intent[@"revision"] unsignedIntegerValue] != _revision || self.busy) return;
    NSString *provider = intent[@"provider"];
    dispatch_async(_queue, ^{
        [self update];
        if (self->_pending) return;
        if (!self->_stateReady) { [self reject:@"VPN 状态尚未就绪，请稍后重试"]; return; }
        NSDictionary *target = [self profileFor:provider];
        if (!target || !Unlocked()) { [self reject:@"请解锁手机并检查目标 VPN 配置"]; return; }
        if (![target[@"key"] isEqual:intent[@"profiles"][provider]]) { [self reject:@"目标配置已改变，请重新确认"]; return; }
        NSMutableArray *active = [NSMutableArray array];
        for (id connection in self->_profiles.allValues) if ([connection notDisconnectedOrDisconnecting]) [active addObject:connection];
        if (active.count > 1 || (active.count && [[self providerFor:active.firstObject] isEqualToString:@"external"])) { [self reject:@"其他 VPN 正在使用，请先手动关闭"]; return; }
        if (!active.count || [[self providerFor:active.firstObject] isEqualToString:provider]) { [self savePreference:provider]; [self update]; return; }
        if (![[self providerFor:active.firstObject] isEqualToString:intent[@"active"]]) { [self reject:@"VPN 状态已改变，请重新确认"]; return; }
        NSString *source = [self providerFor:active.firstObject];
        if (![[self profileFor:source][@"key"] isEqual:intent[@"profiles"][source]]) { [self reject:@"旧连接配置已改变，请重新确认"]; return; }
        [self beginConnect:provider source:[self providerFor:active.firstObject] save:YES];
    });
}
- (void)toggle {
    if (!self.ready || self.busy) return;
    NSDictionary *snapshot = _snapshot;
    dispatch_async(_queue, ^{
        [self update]; if (self->_pending) return;
        if (!self->_stateReady) { [self reject:@"VPN 状态尚未就绪，请稍后重试"]; return; }
        NSArray *active = [self->_profiles.allValues filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id connection, NSDictionary *bindings) { (void)bindings; return [connection notDisconnectedOrDisconnecting]; }]];
        if (!Unlocked()) { [self reject:@"请解锁手机后重试"]; return; }
        if (active.count > 1 || (active.count && [[self providerFor:active.firstObject] isEqualToString:@"external"])) { [self reject:@"其他 VPN 正在使用，请先手动关闭"]; return; }
        if (active.count) {
            NSString *provider = [self providerFor:active.firstObject];
            if (![provider isEqual:snapshot[@"active"]] || ![[self profileFor:provider][@"key"] isEqual:snapshot[@"identities"][provider]]) { [self reject:@"连接状态已改变，请再次点按"]; return; }
            [self beginDisconnect:provider];
        }
        else [self beginConnect:self->_preferred source:nil save:NO];
    });
}
- (void)reject:(NSString *)message { _lastMessage = message; _failed = YES; [self update]; }
- (void)logEvent:(NSString *)event code:(NSInteger)code {
    // One bounded, non-sensitive local log for actual user operations. No App
    // paths, profile IDs, peer tokens, endpoints or credentials are recorded.
    NSString *path=@"/var/mobile/Library/Caches/ayao.vpn-operations.log";
    NSFileManager *manager=NSFileManager.defaultManager;
    NSDictionary *attributes=[manager attributesOfItemAtPath:path error:nil];
    if([attributes[NSFileSize] unsignedLongLongValue]>131072) {
        [manager removeItemAtPath:[path stringByAppendingString:@".previous"] error:nil];
        [manager moveItemAtPath:path toPath:[path stringByAppendingString:@".previous"] error:nil];
    }
    NSString *line=[NSString stringWithFormat:@"time=%.3f operation=%llu elapsed=%.3f source=%@ target=%@ phase=%@ event=%@ code=%ld\n",
        NSDate.date.timeIntervalSince1970,_generation,_startedAt?CFAbsoluteTimeGetCurrent()-_startedAt:0,
        _sourceProvider?:@"none",_targetProvider?:@"none",_phase?:@"idle",event,(long)code];
    NSData *bytes=[line dataUsingEncoding:NSUTF8StringEncoding];
    if(![manager fileExistsAtPath:path]) {
        [manager createFileAtPath:path contents:bytes attributes:@{NSFilePosixPermissions:@0600}];return;
    }
    NSFileHandle *handle=[NSFileHandle fileHandleForWritingAtPath:path];
    if(!handle)return;
    @try {[handle seekToEndOfFile];[handle writeData:bytes];}
    @catch(NSException *exception){(void)exception;}
    @finally {[handle closeFile];}
}
- (void)armTimeout:(NSTimeInterval)seconds generation:(uint64_t)generation {
    uint64_t timeoutRevision=++_timeoutRevision;
    if (_timer) dispatch_source_cancel(_timer);
    _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _queue);
    dispatch_source_set_timer(_timer, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), DISPATCH_TIME_FOREVER, NSEC_PER_MSEC * 100);
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(_timer, ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf || !strongSelf->_pending || strongSelf->_generation != generation ||
            strongSelf->_timeoutRevision!=timeoutRevision) return;
        [strongSelf finish:@"请求超时；请检查 App 登录、权限和连接辅助"];
        [strongSelf update];
    }); dispatch_resume(_timer);
}
- (void)finish:(NSString *)message {
    _timeoutRevision++;
    [self logEvent:message code:[message isEqual:@"连接成功"]||[message isEqual:@"连接已断开"]?0:1];
    if(_sourceProvider)_sourceStopped=![[self profileFor:_sourceProvider][@"connection"] notDisconnectedOrDisconnecting];
    [_client close]; _client = nil;
    _pending = NO; _phase = nil; _operationProfiles = nil;
    _lastMessage = _sourceStopped && ![message isEqual:@"连接成功"] ? [@"旧连接已断开。" stringByAppendingString:message] : message;
    _failed = ![@[@"连接成功", @"连接已断开"] containsObject:message];
    if (_timer) { dispatch_source_cancel(_timer); _timer = nil; }
}
- (void)beginDisconnect:(NSString *)provider {
    NSDictionary *profile = [self profileFor:provider]; id target = profile[@"connection"];
    if (!profile || ![target respondsToSelector:@selector(disconnect)]) { [self reject:@"无法定位唯一目标 VPN"]; return; }
    _pending = YES; _failed = NO; _targetProvider = provider; _phase = @"disconnect";
    _operationProfiles = @{provider:profile[@"key"]}; _generation = (uint64_t)(NSDate.date.timeIntervalSince1970 * 1000000);
    _sourceStopped = NO; _stopConfirmed = !VPNUsesNativeStop(provider); _saveOnSuccess = nil;
    _sourceProvider=nil;
    _startedAt=CFAbsoluteTimeGetCurrent();_lastLoggedState=nil;
    [self logEvent:@"explicit-stop" code:0];
    _lastMessage = @"正在后台断开"; [self armTimeout:VPNTimeout(provider) + 25 generation:_generation];
    if(VPNUsesNativeStop(provider)) [self nativeDisconnect:provider generation:_generation];
    else [target disconnect];
    [self update];
}
- (void)nativeDisconnect:(NSString *)provider generation:(uint64_t)generation {
    // This method is only used for the user's explicit off action. Provider
    // switching never dispatches any command to the previously active App.
    dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices",RTLD_NOW);
    id service=[NSClassFromString(@"FBSSystemService") sharedService];
    NSString *const *key=(NSString *const *)dlsym(RTLD_DEFAULT,"FBSOpenApplicationOptionKeyActivateSuspended");
    if(!key || !*key || ![service respondsToSelector:@selector(openApplication:options:withResult:)]) {
        [self finish:@"原生停止入口不可用"];[self update];return;
    }
    [service openApplication:VPNBundle(provider) options:@{*key:@YES} withResult:^(NSError *error){
        dispatch_async(self->_ipcQueue,^{
            VPNIPCClient *client=[[VPNIPCClient alloc] initWithProvider:provider];
            dispatch_async(self->_queue,^{
                if(self->_pending && self->_generation==generation)self->_client=client;
                else [client close];
            });
            BOOL available=NO;
            CFAbsoluteTime prepareDeadline=CFAbsoluteTimeGetCurrent()+8;
            if(!error)while(!available && CFAbsoluteTimeGetCurrent()<prepareDeadline) {
                __block BOOL current=NO;
                dispatch_sync(self->_queue,^{current=self->_pending && self->_generation==generation;});
                if(!current){[client close];return;}
                available=[client open] && [client probe];
                if(!available){[client close];[NSThread sleepForTimeInterval:0.2];}
            }
            __block BOOL current=NO;
            dispatch_sync(self->_queue,^{current=self->_pending && self->_generation==generation;});
            if(!current){[client close];return;}
            NSInteger result=available?[client requestConnect:NO generation:generation]:VPNReplyUnavailable;
            dispatch_async(self->_queue,^{
                if(!self->_pending || self->_generation!=generation){[client close];return;}
                self->_stopConfirmed=result==VPNReplyDisconnected;
                [self logEvent:@"stop-reply" code:result];
                if(!self->_stopConfirmed)[self finish:@"后台停止未完成；本次未跳转 App"];
                [self update];
            });
        });
    }];
}
- (void)beginConnect:(NSString *)provider source:(NSString *)source save:(BOOL)save {
    NSDictionary *target = [self profileFor:provider];
    if (!target || ![target[@"connection"] isProviderAvailable]) { [self reject:@"目标 VPN 配置或扩展不可用"]; return; }
    _pending = YES; _failed = NO; _targetProvider = provider; _phase = @"launch"; _helperConfirmed = NO; _sourceStopped = NO;
    _saveOnSuccess = save ? provider : nil; _sourceProvider=source;
    _startedAt=CFAbsoluteTimeGetCurrent();_targetStableAt=0;_settleScheduled=NO;_replyTimedOut=NO;_lastLoggedState=nil;
    NSMutableDictionary *ids = [NSMutableDictionary dictionaryWithObject:target[@"key"] forKey:provider];
    if (source) ids[source] = [self profileFor:source][@"key"];
    _operationProfiles = ids; _generation = (uint64_t)(NSDate.date.timeIntervalSince1970 * 1000000);
    uint64_t generation = _generation;
    [self logEvent:source?@"switch-b-first":@"connect-b-first" code:0];
    _lastMessage = @"正在后台准备 VPN"; [self armTimeout:VPNTimeout(provider) + 25 generation:generation];
    dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices", RTLD_NOW);
    id service = [NSClassFromString(@"FBSSystemService") sharedService];
    NSString *const *key = (NSString *const *)dlsym(RTLD_DEFAULT, "FBSOpenApplicationOptionKeyActivateSuspended");
    if (!key || !*key || ![service respondsToSelector:@selector(openApplication:options:withResult:)]) { [self finish:@"后台启动入口不可用，本次未打开 App"]; [self update]; return; }
    // No foreground fallback: only an explicit footer action may open an App.
    [service openApplication:VPNBundle(provider) options:@{*key:@YES} withResult:^(NSError *error) {
        dispatch_async(self->_ipcQueue, ^{
            VPNIPCClient *client = [[VPNIPCClient alloc] initWithProvider:provider];
            __block BOOL current=NO;
            dispatch_sync(self->_queue,^{
                current=self->_pending && self->_generation==generation;
                if(current)self->_client=client;
            });
            if(!current){[client close];return;}
            BOOL available = NO;
            // A successful background-launch callback is not a ready socket.
            // Cold App startup can outlive ten immediate 200 ms retries.
            // Return as soon as the local v2 App socket is ready.
            CFAbsoluteTime prepareDeadline=CFAbsoluteTimeGetCurrent()+8;
            if (!error) while (!available && CFAbsoluteTimeGetCurrent()<prepareDeadline) {
                __block BOOL current=NO;
                dispatch_sync(self->_queue,^{current=self->_pending && self->_generation==generation;});
                if(!current){[client close];return;}
                available = [client open] && [client probe];
                if (!available) { [client close]; [NSThread sleepForTimeInterval:0.2]; }
            }
            dispatch_async(self->_queue, ^{
                if (!self->_pending || self->_generation != generation) { [client close]; return; }
                if (!available) { [self finish:HelperFailure(provider)]; [self update]; return; }
                self->_client = client;
                // B-first: never stop, launch or asynchronously toggle A.
                // Its exact identity is retained only for arbitration/readback.
                [self logEvent:@"target-ready" code:VPNReplyReady];
                [self sendConnect:generation];
            });
        });
    }];
    [self update];
}
- (void)sendConnect:(uint64_t)generation {
    if(!_pending || _generation!=generation || [_phase isEqual:@"connect"])return;
    NSDictionary *target = [self profileFor:_targetProvider];
    BOOL other = NO;
    for (id connection in _profiles.allValues) if ([connection notDisconnectedOrDisconnecting] && connection != target[@"connection"] &&
        !([self providerFor:connection] && [[self providerFor:connection] isEqual:_sourceProvider] &&
          [[self profileFor:_sourceProvider][@"key"] isEqual:_operationProfiles[_sourceProvider]])) other = YES;
    if (!target || ![target[@"key"] isEqual:_operationProfiles[_targetProvider]] || other || !Unlocked()) { [self finish:@"VPN 状态已改变，未启动新连接"]; [self update]; return; }
    _phase = @"connect"; _lastMessage = @"正在连接"; [self armTimeout:VPNTimeout(_targetProvider) + 1 generation:generation];
    VPNIPCClient *client = _client;
    dispatch_async(_ipcQueue, ^{
        __block BOOL current=NO;
        dispatch_sync(self->_queue,^{
            current=self->_pending && self->_generation==generation;
            if(current)[self logEvent:@"connect-dispatch" code:0];
        });
        if(!current){[client close];return;}
        if(!Unlocked()) {
            [client close];
            dispatch_async(self->_queue,^{
                if(self->_pending && self->_generation==generation){[self finish:@"手机已锁定，未派发新连接"];[self update];}
            });return;
        }
        // The immediately preceding probe checked B's target identity; no A wait and no
        // duplicate handshake consume B's finite execution allowance.
        NSInteger result=[client requestConnect:YES generation:generation];
        dispatch_async(self->_queue, ^{
            if (!self->_pending || self->_generation != generation) return;
            self->_helperConfirmed = result == VPNReplyConnected;
            [self logEvent:@"connect-reply" code:result];
            if(result==VPNReplyTimeout) {
                [client close];
                // The timeout is a transport result, not proof that the VPN is
                // disconnected. Observe the exact target independently after
                // cancellation before reporting the system's resulting state.
                self->_replyTimedOut=YES;
                self->_lastMessage=@"正在核对系统切换结果";
                [self armTimeout:4 generation:generation];
                for(NSUInteger delay=1;delay<=3;delay++)
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,delay*NSEC_PER_SEC),self->_queue,^{
                        if(self->_pending && self->_generation==generation)[self update];
                    });
            } else if (!self->_helperConfirmed) [self finish:result == VPNReplyInteraction ? @"需要登录或权限；本次未跳转，请主动打开 App" : @"后台连接未完成；本次未跳转 App"];
            [self update];
        });
    });
}
- (void)progress:(BOOL)loaded active:(NSArray *)active {
    if (!loaded) return;
    NSMutableDictionary *observed=[NSMutableDictionary dictionary];
    for(NSString *provider in VPNProviders()) {
        id connection=[self profileFor:provider][@"connection"];
        if(connection)observed[provider]=@([connection status]);
    }
    if(![_lastLoggedState isEqual:observed]) {
        _lastLoggedState=observed;
        NSString *event=[NSString stringWithFormat:@"state easy=%@ feilian=%@ hotspot=%@ gofast=%@ jump=%@",
            observed[@"easy"]?:@-1,observed[@"feilian"]?:@-1,observed[@"hotspot"]?:@-1,
            observed[@"gofast"]?:@-1,observed[@"jump"]?:@-1];
        [self logEvent:event code:0];
    }
    for (NSString *provider in _operationProfiles) if (![[self profileFor:provider][@"key"] isEqual:_operationProfiles[provider]]) { [self finish:@"VPN 配置发生变化，请重试"]; return; }
    if ([_phase isEqualToString:@"disconnect"] && _stopConfirmed && ![[self profileFor:_targetProvider][@"connection"] notDisconnectedOrDisconnecting]) { [self finish:@"连接已断开"]; return; }
    if ([_phase isEqualToString:@"connect"] && (_helperConfirmed || _replyTimedOut) && active.count == 1 &&
        [[self providerFor:active.firstObject[@"connection"]] isEqualToString:_targetProvider] && [active.firstObject[@"connection"] connected]) {
        if(!_targetStableAt)_targetStableAt=CFAbsoluteTimeGetCurrent();
        if(CFAbsoluteTimeGetCurrent()-_targetStableAt<0.75) {
            if(!_settleScheduled) {
                _settleScheduled=YES;uint64_t generation=_generation;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,750*NSEC_PER_MSEC),_queue,^{
                    if(self->_pending && self->_generation==generation){self->_settleScheduled=NO;[self update];}
                });
            }
            return;
        }
        if(_replyTimedOut)[self logEvent:@"transport-timeout-but-system-target-stable" code:0];
        NSString *save = _saveOnSuccess; [self finish:@"连接成功"]; if (save) [self savePreference:save];
        return;
    }
    _targetStableAt=0;
    if ([_phase isEqualToString:@"connect"]) for (NSDictionary *entry in active) {
        NSString *provider=[self providerFor:entry[@"connection"]];
        if (![provider isEqual:_targetProvider] && ![provider isEqual:_sourceProvider]) { [self finish:@"其他 VPN 已启动，停止本次请求"]; return; }
    }
}
- (void)openPreferredApp {
    if (self.busy) return;
    NSString *bundle = VPNBundle(self.preferredProvider);
    dispatch_async(_ipcQueue, ^{
        if (!Unlocked()) return;
        dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices", RTLD_NOW);
        id service = [NSClassFromString(@"FBSSystemService") sharedService];
        if ([service respondsToSelector:@selector(openApplication:options:withResult:)]) [service openApplication:bundle options:@{} withResult:^(NSError *error) { (void)error; }];
    });
}
- (void)dealloc {
    if (_stateObserver) [NSNotificationCenter.defaultCenter removeObserver:_stateObserver];
    if (_configurationObserver) [NSNotificationCenter.defaultCenter removeObserver:_configurationObserver];
    if (_timer) dispatch_source_cancel(_timer); [_client close];
}
@end
