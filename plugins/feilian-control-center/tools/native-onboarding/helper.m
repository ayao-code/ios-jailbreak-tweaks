// Source-retained test helper: exact three-App Filter, no credentials or options.
// Only a kernel-authenticated, exact standalone tool path can request an action.
#import <UIKit/UIKit.h>
#import <NetworkExtension/NetworkExtension.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <ptrauth.h>
#import <sys/stat.h>
#import <fcntl.h>
#import "protocol.h"

@interface NSObject (AdapterProbeNative)
- (void)startBtnClick;
- (void)stopBtnClick;
- (UIControl *)connectButton;
- (UIControl *)closeButton;
+ (id)shared;
- (NSDictionary *)lines;
- (id)adsourceData;
- (id)actionBlock;
- (UIView *)auctionsV;
- (NSUInteger)clearSringStatus;
- (void)theVersionOpinionatedChanged;
- (void)selectLocation;
@end

static NSString *Bundle;
static dispatch_source_t Listener, Reader, Timeout;
static int ServerFD = -1, PeerFD = -1;
static NSMutableData *Input;
static BOOL Pending;
static BOOL Received;
static uint64_t PeerGeneration;
static UIBackgroundTaskIdentifier BackgroundTask;

static UIViewController *Find(UIViewController *root, NSString *className) {
    Class expected = NSClassFromString(className);
    if (expected && [root isKindOfClass:expected]) return root;
    for (UIViewController *child in root.childViewControllers) {
        UIViewController *found = Find(child, className); if (found) return found;
    }
    return nil;
}
static UIViewController *MainController(BOOL discovery) {
    NSString *name = [Bundle isEqual:ProbeBundles[1]] ? @"_TtC10GOFast_VPN24HomeScreenViewController" :
        ([Bundle isEqual:ProbeBundles[2]] ? @"ToPreapredListVC" : @"ViewController");
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            UIViewController *found = Find(window.rootViewController, name); if (found) return found;
            if (discovery && window.isKeyWindow && window.rootViewController) return window.rootViewController;
        }
    }
    // Legacy Apps may not have adopted scenes.
    for (UIWindow *window in UIApplication.sharedApplication.windows) {
        UIViewController *found = Find(window.rootViewController, name); if (found) return found;
        if (discovery && window.isKeyWindow && window.rootViewController) return window.rootViewController;
    }
    return nil;
}
static void ControllerTree(UIViewController *controller, NSMutableArray *result, NSUInteger depth) {
    if (!controller || depth > 12 || result.count >= 24) return;
    [result addObject:@{@"class":NSStringFromClass(controller.class), @"depth":@(depth),
        @"loaded":@(controller.isViewLoaded), @"presented":@(controller.presentedViewController != nil)}];
    for (UIViewController *child in controller.childViewControllers) ControllerTree(child, result, depth + 1);
    if(controller.presentedViewController)ControllerTree(controller.presentedViewController,result,depth+1);
}
static void ClosePeer(void) {
    Pending = NO; Received = NO;
    if (Timeout) { dispatch_source_cancel(Timeout); Timeout = nil; }
    if (Reader) { dispatch_source_cancel(Reader); Reader = nil; }
    if (PeerFD >= 0) { close(PeerFD); PeerFD = -1; }
    Input = nil;
    if (BackgroundTask != UIBackgroundTaskInvalid) {
        [UIApplication.sharedApplication endBackgroundTask:BackgroundTask];
        BackgroundTask = UIBackgroundTaskInvalid;
    }
}
static void Output(NSDictionary *result) {
    if (PeerFD < 0) return;
    NSData *data = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
    if(data.length>16384 && result[@"views"]) {
        NSMutableDictionary *compact=[result mutableCopy];
        compact[@"viewCount"]=@([result[@"views"] count]);
        [compact removeObjectForKey:@"views"];
        data=[NSJSONSerialization dataWithJSONObject:compact options:0 error:nil];
    }
    if (data.length > 16384) { ClosePeer(); return; }
    uint32_t size = (uint32_t)data.length;
    NSMutableData *frame = [NSMutableData dataWithBytes:&size length:sizeof(size)];
    [frame appendData:data];
    int descriptor=dup(PeerFD);
    ClosePeer();
    if(descriptor<0)return;
    // A bounded worker drains partial writes without blocking the App UI.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        int flags=fcntl(descriptor,F_GETFL,0);fcntl(descriptor,F_SETFL,flags&~O_NONBLOCK);
        struct timeval timeout={.tv_sec=2};setsockopt(descriptor,SOL_SOCKET,SO_SNDTIMEO,&timeout,sizeof(timeout));
        size_t offset=0;
        while(offset<frame.length){
            ssize_t n=send(descriptor,(const uint8_t *)frame.bytes+offset,frame.length-offset,0);
            if(n<0&&errno==EINTR)continue;
            if(n<=0)break;
            offset+=(size_t)n;
        }
        close(descriptor);
    });
}
static uintptr_t NativeBlockOffset(id block) {
    if(!block || ![NSStringFromClass([block class]) containsString:@"Block"]) return 0;
    struct { void *isa; int flags; int reserved; void *invoke; } *layout=(__bridge void *)block;
    void *invoke=ptrauth_strip(layout->invoke,ptrauth_key_function_pointer);
    Dl_info info={0};
    if(!dladdr(invoke,&info) || !info.dli_fbase || !info.dli_fname ||
        ![@(info.dli_fname).lastPathComponent isEqual:NSBundle.mainBundle.executablePath.lastPathComponent]) return 0;
    return (uintptr_t)invoke-(uintptr_t)info.dli_fbase;
}
static void SubscriberBindings(id object, NSMutableArray *result, NSUInteger depth) {
    if(!object || depth>3 || result.count>=16 ||
        ![NSStringFromClass([object class]) hasPrefix:@"RAC"]) return;
    for(Class cls=[object class];cls && cls!=NSObject.class;cls=class_getSuperclass(cls)) {
        unsigned count=0; Ivar *ivars=class_copyIvarList(cls,&count);
        for(unsigned i=0;i<count;i++) {
            const char *type=ivar_getTypeEncoding(ivars[i]);
            if(!type || type[0]!='@') continue;
            NSString *name=@(ivar_getName(ivars[i]));
            if(![@[@"_innerSubscriber",@"innerSubscriber",@"_subscriber",@"subscriber",
                   @"_next",@"next",@"_nextBlock",@"nextBlock"] containsObject:name]) continue;
            id value=object_getIvar(object,ivars[i]);
            uintptr_t offset=NativeBlockOffset(value);
            if(offset) [result addObject:@{@"field":name,@"offset":@(offset)}];
            else SubscriberBindings(value,result,depth+1);
        }
        free(ivars);
    }
}
static UIControl *JumpConnectionControl(UIView *view, NSUInteger depth) {
    if(!view || depth>16 || view.hidden || view.alpha<0.5 || !view.userInteractionEnabled) return nil;
    if([view isKindOfClass:UIButton.class] && ((UIButton *)view).enabled) {
        for(id target in ((UIControl *)view).allTargets) {
            if(![NSStringFromClass([target class]) isEqual:@"RACPassthroughSubscriber"]) continue;
            NSArray *actions=[(UIControl *)view actionsForTarget:target forControlEvent:UIControlEventTouchUpInside];
            if(![actions containsObject:@"sendNext:"]) continue;
            NSMutableArray *blocks=[NSMutableArray array];SubscriberBindings(target,blocks,0);
            for(NSDictionary *block in blocks)
                // Confirmed on the actual UIButton and by static native chain:
                // callback -> toolslRecording -> native preparation / validation.
                if([block[@"offset"] unsignedLongLongValue]==0x2d898) return (UIControl *)view;
        }
    }
    for(UIView *child in view.subviews) {
        UIControl *button=JumpConnectionControl(child,depth+1);
        if(button) return button;
    }
    return nil;
}
static UIControl *FastestLocationControl(UIView *view,NSUInteger depth) {
    if(!view || depth>16 || view.hidden || view.alpha<0.5 || !view.userInteractionEnabled) return nil;
    if([view isKindOfClass:UIControl.class] && ((UIControl *)view).enabled) {
        for(id target in ((UIControl *)view).allTargets)
            if([NSStringFromClass([target class]) isEqual:@"GOFast_VPN.FastestLocationView"] &&
                [[(UIControl *)view actionsForTarget:target forControlEvent:UIControlEventTouchUpInside]
                 containsObject:@"onSelectFastestLocation:"]) return (UIControl *)view;
    }
    for(UIView *child in view.subviews) {
        UIControl *button=FastestLocationControl(child,depth+1);
        if(button) return button;
    }
    return nil;
}
static void Controls(UIView *view, NSMutableArray *result, NSUInteger depth) {
    if (depth > 16 || result.count >= 50) return;
    if ([view isKindOfClass:UIControl.class]) {
        UIControl *control = (UIControl *)view;
        NSMutableArray *actions = [NSMutableArray array];
        for (id target in control.allTargets) {
            for (NSString *action in [control actionsForTarget:target forControlEvent:UIControlEventTouchUpInside]) {
                NSMutableDictionary *binding=[@{@"target":NSStringFromClass([target class]), @"selector":action} mutableCopy];
                if([Bundle isEqual:ProbeBundles[2]]) {
                    NSMutableArray *blocks=[NSMutableArray array];SubscriberBindings(target,blocks,0);
                    binding[@"nativeBlocks"]=blocks;
                }
                [actions addObject:binding];
            }
        }
        if (actions.count) [result addObject:@{@"class":NSStringFromClass(view.class),
            @"parent":NSStringFromClass(view.superview.class), @"actions":actions,
            @"title":[view isKindOfClass:UIButton.class] ? (((UIButton *)view).currentTitle ?: @"") : @""}];
    }
    for (UIView *child in view.subviews) Controls(child, result, depth + 1);
}
static uintptr_t NativeActionOffset(id object) {
    if(![object respondsToSelector:@selector(actionBlock)]) return 0;
    return NativeBlockOffset([object actionBlock]);
}
static void VisibleAlertLabels(UIView *view, NSMutableArray *result, NSUInteger depth) {
    if(!view || depth>8 || view.hidden || view.alpha<0.5 || result.count>=8) return;
    if([view isKindOfClass:UILabel.class]) {
        NSString *text=((UILabel *)view).text;
        if(text.length && text.length<=200) [result addObject:text];
    }
    // Only the already displayed alert, never text fields, node lists or model data.
    for(UIView *child in view.subviews) VisibleAlertLabels(child,result,depth+1);
}
static void Views(UIView *view, NSMutableArray *result, NSUInteger depth, NSString *path) {
    if (!view || depth > 16 || result.count >= 120) return;
    NSMutableArray *gestures=[NSMutableArray array];
    for(UIGestureRecognizer *gesture in view.gestureRecognizers) {
        NSMutableArray *actions=[NSMutableArray array];
        @try {
            NSArray *targets=[gesture valueForKey:@"_targets"];
            for(id binding in targets) {
                id target=[binding valueForKey:@"target"];
                NSValue *selectorValue=[binding valueForKey:@"action"];
                SEL selector=NULL;
                if([selectorValue isKindOfClass:NSValue.class] && !strcmp(selectorValue.objCType,@encode(SEL)))
                    [selectorValue getValue:&selector size:sizeof(selector)];
                if(target && selector)[actions addObject:@{@"target":NSStringFromClass([target class]),@"selector":NSStringFromSelector(selector)}];
            }
        } @catch(NSException *exception) { (void)exception; }
        [gestures addObject:@{@"class":NSStringFromClass(gesture.class),@"actions":actions}];
    }
    if(depth<3 || gestures.count || [view isKindOfClass:UIControl.class] ||
       ![NSStringFromClass(view.class) hasPrefix:@"UI"]) {
        NSMutableDictionary *entry=[@{@"class":NSStringFromClass(view.class),@"path":path,@"hidden":@(view.hidden),
            @"interaction":@(view.userInteractionEnabled),@"gestures":gestures} mutableCopy];
        if ([Bundle isEqual:ProbeBundles[2]] && [NSStringFromClass(view.class) isEqual:@"MultyJoinBtn"] &&
            [view respondsToSelector:@selector(actionBlock)]) {
            uintptr_t offset=NativeActionOffset(view);
            if(offset) entry[@"nativeActionOffset"]=@(offset);
        }
        if([view isKindOfClass:UITableView.class]) {
            UITableView *table=(UITableView *)view;
            NSMutableArray *counts=[NSMutableArray array];
            for(NSInteger section=0;section<MIN(table.numberOfSections,16);section++)
                [counts addObject:@([table numberOfRowsInSection:section])];
            entry[@"sectionRowCounts"]=counts;
        }
        [result addObject:entry];
    }
    NSUInteger index=0;
    for(UIView *child in view.subviews)Views(child,result,depth+1,[path stringByAppendingFormat:@"/%lu",(unsigned long)index++]);
}
static void Status(uint64_t generation) {
    [NETunnelProviderManager loadAllFromPreferencesWithCompletionHandler:^(NSArray *managers, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!Pending || PeerGeneration != generation) return;
            NSMutableArray *states = [NSMutableArray array];
            dispatch_group_t group = dispatch_group_create();
            for (NETunnelProviderManager *manager in managers) {
                NSMutableDictionary *state = [@{@"status":@(manager.connection.status)} mutableCopy];
                [states addObject:state];
                if ([manager.connection respondsToSelector:@selector(fetchLastDisconnectErrorWithCompletionHandler:)]) {
                    dispatch_group_enter(group);
                    [manager.connection fetchLastDisconnectErrorWithCompletionHandler:^(NSError *lastError) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            // Error metadata only: never expose userInfo, endpoints or credentials.
                            state[@"disconnectErrorDomain"] = lastError.domain ?: @"";
                            state[@"disconnectErrorCode"] = @(lastError.code);
                            dispatch_group_leave(group);
                        });
                    }];
                }
            }
            dispatch_group_notify(group, dispatch_get_main_queue(), ^{
                if (Pending && PeerGeneration == generation)
                    Output(@{@"errorCode":@(error.code), @"states":states});
            });
        });
    }];
}
static void Command(uint32_t action) {
    UIViewController *controller = MainController(action == 0 || action == 4);
    if (!controller || !controller.isViewLoaded) { Output(@{@"error":@"main_controller_unavailable"}); return; }
    if(action==0 && [Bundle isEqual:ProbeBundles[1]]) {
        UIViewController *visible=controller.navigationController.visibleViewController ?: controller;
        while(visible.presentedViewController) visible=visible.presentedViewController;
        if(visible.isViewLoaded) controller=visible;
    }
    if (action == 0) {
        NSMutableArray *controls = [NSMutableArray array]; Controls(controller.view, controls, 0);
        NSMutableArray *controllers = [NSMutableArray array]; ControllerTree(controller, controllers, 0);
        NSMutableArray *views=[NSMutableArray array];Views(controller.view,views,0,@"root");
        NSMutableDictionary *outlets=[NSMutableDictionary dictionary];
        NSMutableDictionary *nativeReadiness=[NSMutableDictionary dictionary];
        if([Bundle isEqual:ProbeBundles[2]]) {
            if([controller respondsToSelector:@selector(auctionsV)]) {
                NSMutableArray *labels=[NSMutableArray array];
                VisibleAlertLabels([(id)controller auctionsV],labels,0);
                nativeReadiness[@"visibleAlertLabels"]=labels;
            }
            Class service=NSClassFromString(@"TradesService");
            if([service respondsToSelector:@selector(shared)]) {
                id model=[service shared];
                if([model respondsToSelector:@selector(lines)]) {
                    id lines=[model lines];
                    nativeReadiness[@"nodeCollectionClass"]=lines ? NSStringFromClass([lines class]) : @"nil";
                    if([lines isKindOfClass:NSDictionary.class]||[lines isKindOfClass:NSArray.class])
                        nativeReadiness[@"nodeCount"]=@([lines count]);
                }
                if([model respondsToSelector:@selector(adsourceData)])
                    nativeReadiness[@"hasSelectedNode"]=@([model adsourceData]!=nil);
                if([model respondsToSelector:@selector(clearSringStatus)])
                    nativeReadiness[@"nativeConnectionState"]=@([model clearSringStatus]);
            }
            UIControl *connectionButton=JumpConnectionControl(controller.view,0);
            if(connectionButton) nativeReadiness[@"connectionButtonSelected"]=@(connectionButton.selected);
        }
        if([Bundle isEqual:ProbeBundles[2]])for(NSString *name in @[@"skewerBtn",@"falureV",@"dstlinkPushNOHideNav",@"pSpinlockV",@"sessionsV",@"auctionsV",@"flashUnamusedBtn"]){
            SEL selector=NSSelectorFromString(name);
            if([controller respondsToSelector:selector]){
                id object=((id (*)(id,SEL))[controller methodForSelector:selector])(controller,selector);
                if([object isKindOfClass:UIView.class])outlets[name]=NSStringFromClass([object class]);
            }
        }
        Output(@{@"controller":NSStringFromClass(controller.class), @"hasPresentedController":@(controller.presentedViewController != nil),
            @"controllers":controllers, @"controls":controls,@"views":views,@"outlets":outlets,
            @"nativeReadiness":nativeReadiness});
        return;
    }
    if (action == 2) { Status(PeerGeneration); return; }
    if(action==5 && [Bundle isEqual:ProbeBundles[1]]) {
        NSMethodSignature *signature=[controller methodSignatureForSelector:@selector(selectLocation)];
        if(!UIApplication.sharedApplication.protectedDataAvailable || controller.presentedViewController ||
            !signature || signature.numberOfArguments!=2 || strcmp(signature.methodReturnType,"v")) {
            Output(@{@"error":@"native_location_entry_unavailable"});return;
        }
        [controller selectLocation];
        Output(@{@"nativeLocationEntryDispatched":@YES});return;
    }
    if(action==6 && [Bundle isEqual:ProbeBundles[1]]) {
        UIViewController *visible=controller.navigationController.visibleViewController;
        if(!UIApplication.sharedApplication.protectedDataAvailable || controller.presentedViewController ||
            ![NSStringFromClass([visible class]) isEqual:@"GOFast_VPN.LocationSelectionViewController"]) {
            Output(@{@"error":@"native_location_page_unavailable"});return;
        }
        UIControl *button=FastestLocationControl(visible.view,0);
        if(!button) { Output(@{@"error":@"native_fastest_control_unavailable"});return; }
        [button sendActionsForControlEvents:UIControlEventTouchUpInside];
        Output(@{@"nativeFastestSelectionDispatched":@YES});return;
    }
    if (action == 4 && [Bundle isEqual:ProbeBundles[1]]) {
        UIViewController *presented = controller.presentedViewController;
        if (!presented) for (UIViewController *child in controller.childViewControllers)
            if (child.presentedViewController) { presented=child.presentedViewController; break; }
        Class paywall=NSClassFromString(@"_TtC10GOFast_VPN28PaywallOnboardViewController");
        if (!paywall || ![presented isKindOfClass:paywall] ||
            ![presented respondsToSelector:@selector(closeButton)]) { Output(@{@"error":@"no_known_paywall_close"});return; }
        if(presented.presentedViewController) { Output(@{@"error":@"native_consent_requires_user"});return; }
        UIControl *close=[(id)presented closeButton];
        if (![close isKindOfClass:UIControl.class] || !close.enabled || close.hidden || close.alpha < 0.5) {
            Output(@{@"error":@"native_close_not_available"});return;
        }
        [close sendActionsForControlEvents:UIControlEventTouchUpInside];
        Output(@{@"nativeCloseDispatched":@YES});return;
    }
    if (action == 3 && [Bundle isEqual:ProbeBundles[0]] &&
        UIApplication.sharedApplication.protectedDataAvailable &&
        !controller.presentedViewController && [controller respondsToSelector:@selector(stopBtnClick)]) {
        [(id)controller stopBtnClick];
        uint64_t generation=PeerGeneration;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10*NSEC_PER_SEC),dispatch_get_main_queue(),^{
            if(Pending&&PeerGeneration==generation)Status(generation);
        }); return;
    }
    if(action==3 && [Bundle isEqual:ProbeBundles[2]] &&
        UIApplication.sharedApplication.protectedDataAvailable && !controller.presentedViewController) {
        Class service=NSClassFromString(@"TradesService");
        id model=[service respondsToSelector:@selector(shared)] ? [service shared] : nil;
        SEL stop=@selector(theVersionOpinionatedChanged);
        NSMethodSignature *signature=[model methodSignatureForSelector:stop];
        if(!signature || signature.numberOfArguments!=2 || strcmp(signature.methodReturnType,"v")) {
            Output(@{@"error":@"verified_jump_stop_unavailable"});return;
        }
        uint64_t generation=PeerGeneration;
        [NETunnelProviderManager loadAllFromPreferencesWithCompletionHandler:^(NSArray *managers,NSError *error) {
            dispatch_async(dispatch_get_main_queue(),^{
                if(!Pending || PeerGeneration!=generation) return;
                if(error || managers.count!=1 ||
                    ![@[@(NEVPNStatusConnected),@(NEVPNStatusConnecting),@(NEVPNStatusReasserting)]
                      containsObject:@(((NETunnelProviderManager *)managers.firstObject).connection.status)]) {
                    Output(@{@"error":@"jump_stop_no_active_manager"});return;
                }
                // Native stop/cleanup verified statically. The connection button
                // routes through advertisement completion even while connected,
                // so sending that toggle is not a reliable stop operation.
                [model theVersionOpinionatedChanged];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC),dispatch_get_main_queue(),^{
                    if(Pending && PeerGeneration==generation) Status(generation);
                });
            });
        }];return;
    }
    if (action != 1 || !UIApplication.sharedApplication.protectedDataAvailable || controller.presentedViewController) {
        Output(@{@"error":@"interaction_or_locked"}); return;
    }
    BackgroundTask = [UIApplication.sharedApplication beginBackgroundTaskWithName:@"VPNAdapterProbe"
        expirationHandler:^{ Output(@{@"error":@"background_expired"}); }];
    if (BackgroundTask == UIBackgroundTaskInvalid) { Output(@{@"error":@"background_unavailable"}); return; }
    @try {
        if ([Bundle isEqual:ProbeBundles[0]] && [controller respondsToSelector:@selector(startBtnClick)])
        {
            NSMethodSignature *signature = [controller methodSignatureForSelector:@selector(startBtnClick)];
            if (signature.numberOfArguments != 2 || strcmp(signature.methodReturnType, "v")) {
                Output(@{@"error":@"entry_signature_changed"}); return;
            }
            [(id)controller startBtnClick];
        }
        else if([Bundle isEqual:ProbeBundles[2]]) {
            Class service=NSClassFromString(@"TradesService");
            id model=[service respondsToSelector:@selector(shared)] ? [service shared] : nil;
            if(!model || ![model respondsToSelector:@selector(adsourceData)] || ![model adsourceData]) {
                Output(@{@"error":@"jump_native_node_not_ready"});return;
            }
            UIControl *button=JumpConnectionControl(controller.view,0);
            if(!button) { Output(@{@"error":@"verified_jump_button_unavailable"});return; }
            // Send the original control event, retaining all native checks.
            [button sendActionsForControlEvents:UIControlEventTouchUpInside];
        }
        else if ([Bundle isEqual:ProbeBundles[1]] && [controller respondsToSelector:@selector(connectButton)]) {
            UIControl *button = [(id)controller connectButton];
            if (![button isKindOfClass:UIControl.class] || !button.enabled) { Output(@{@"error":@"connect_button_unavailable"}); return; }
            [button sendActionsForControlEvents:UIControlEventTouchUpInside];
        } else { Output(@{@"error":@"entry_unavailable"}); return; }
    } @catch (NSException *exception) { (void)exception; Output(@{@"error":@"native_exception"}); return; }
    uint64_t generation = PeerGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (Pending && PeerGeneration == generation) Status(generation);
    });
}
static void Accept(void) {
    int fd = accept(ServerFD, NULL, NULL); if (fd < 0) return;
    if (PeerFD >= 0 || !ProbePeer(fd, @"/var/tmp/vpn-adapter-native-probe")) { close(fd); return; }
    int yes=1; setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&yes,sizeof(yes));
    fcntl(fd, F_SETFL, O_NONBLOCK); PeerFD = fd; Input = [NSMutableData data]; Pending = YES; Received = NO;
    PeerGeneration++;
    ProbeStage(210);
    Reader = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, fd, 0, dispatch_get_main_queue());
    dispatch_source_set_event_handler(Reader, ^{
        AdapterProbeCommand command;
        uint8_t bytes[sizeof(command)]; ssize_t n = recv(PeerFD, bytes, sizeof(bytes), 0);
        if (n == 0) { ClosePeer(); return; }
        if (n < 0) return;
        if (Received) { ClosePeer(); return; }
        [Input appendBytes:bytes length:(NSUInteger)n];
        if (Input.length < sizeof(command)) return;
        if (Input.length != sizeof(command)) { ClosePeer(); return; }
        memcpy(&command, Input.bytes, sizeof(command));
        if (command.magic != AdapterProbeMagic || command.action > 6) { ClosePeer(); return; }
        [Input setLength:0];
        Received = YES;
        ProbeStage(220 + command.action);
        Command(command.action);
    }); dispatch_resume(Reader);
    Timeout = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(Timeout, dispatch_time(DISPATCH_TIME_NOW, 25 * NSEC_PER_SEC), DISPATCH_TIME_FOREVER, NSEC_PER_MSEC * 100);
    dispatch_source_set_event_handler(Timeout, ^{ ClosePeer(); }); dispatch_resume(Timeout);
}
__attribute__((constructor)) static void Initialize(void) {
    @autoreleasepool {
        Bundle = NSBundle.mainBundle.bundleIdentifier;
        ProbeStage(100);
        if (![@[ProbeBundles[0], ProbeBundles[1], ProbeBundles[2]] containsObject:Bundle]) return;
        NSString *expectedVersion = [Bundle isEqual:ProbeBundles[0]] ? @"2.0.2" :
            ([Bundle isEqual:ProbeBundles[1]] ? @"1.4.0" : @"1.1.0");
        if (![[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] isEqual:expectedVersion]) return;
        BackgroundTask = UIBackgroundTaskInvalid;
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@(AdapterProbeSocket)];
        if ([path hasPrefix:@"/private/var/"]) path = [path substringFromIndex:8];
        if (strlen(path.fileSystemRepresentation) >= sizeof(((struct sockaddr_un *)0)->sun_path)) return;
        struct stat st;
        if (!lstat(path.fileSystemRepresentation, &st)) {
            if (!S_ISSOCK(st.st_mode) || st.st_uid != 501) return;
            unlink(path.fileSystemRepresentation);
        }
        ServerFD = socket(AF_UNIX, SOCK_STREAM, 0); if (ServerFD < 0) return;
        struct sockaddr_un address = {.sun_family=AF_UNIX,.sun_len=sizeof(address)};
        strlcpy(address.sun_path,path.fileSystemRepresentation,sizeof(address.sun_path));
        mode_t mask = umask(077); int bound = bind(ServerFD,(void *)&address,sizeof(address)); umask(mask);
        if (bound || chmod(path.fileSystemRepresentation,0600) || listen(ServerFD,1)) { close(ServerFD); ServerFD=-1; return; }
        fcntl(ServerFD,F_SETFL,O_NONBLOCK);
        Listener=dispatch_source_create(DISPATCH_SOURCE_TYPE_READ,ServerFD,0,dispatch_get_main_queue());
        dispatch_source_set_event_handler(Listener,^{Accept();}); dispatch_resume(Listener);
        ProbeStage(200);
    }
}
