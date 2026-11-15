#import <UIKit/UIKit.h>
#import <NetworkExtension/NetworkExtension.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <ptrauth.h>
#import "Shared/VPNIPC.h"

@interface NSObject (MultiVPNNative)
- (void)startBtnClick;
- (void)stopBtnClick;
- (UIControl *)connectButton;
+ (id)shared;
- (id)adsourceData;
- (void)theVersionOpinionatedChanged;
- (UIControl *)closeButton;
@end
static VPNIPCServer *Server;
static NSString *Provider;
static uint64_t Generation;
static BOOL Connecting, Invoked, Loading, LoggedRoot, PreparedAppearance;
static __weak UIViewController *DismissedPage;
static VPNIPCReply Reply;
static dispatch_source_t Timer;
static NSDate *Deadline;
static NETunnelProviderManager *Manager;

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
static UIViewController *Find(UIViewController *root, NSString *name) {
    if([NSStringFromClass(root.class) isEqual:name]) return root;
    for(UIViewController *child in root.childViewControllers) {
        UIViewController *found=Find(child,name);if(found)return found;
    }
    return nil;
}
static void LoadExistingViews(UIViewController *root,NSUInteger depth) {
    if(!root || depth>8)return;
    [root loadViewIfNeeded];
    for(UIViewController *child in root.childViewControllers)LoadExistingViews(child,depth+1);
}
static void DescribeControllers(UIViewController *root,NSMutableArray *out,NSUInteger depth) {
    if(!root || depth>6 || out.count>=20)return;
    [out addObject:[NSString stringWithFormat:@"%@ loaded=%d presented=%@",NSStringFromClass(root.class),root.isViewLoaded,
        root.presentedViewController?NSStringFromClass(root.presentedViewController.class):@"none"]];
    for(UIViewController *child in root.childViewControllers)DescribeControllers(child,out,depth+1);
    DescribeControllers(root.presentedViewController,out,depth+1);
}
static UIViewController *PresentedOnboarding(UIViewController *root) {
    if(root.presentedViewController) {
        UIViewController *found=PresentedOnboarding(root.presentedViewController);if(found)return found;
    }
    if([@[@"GOFast_VPN.PaywallOnboardViewController",@"GOFast_VPN.PaywallOpenAppViewController",
          @"GOFast_VPN.PaywallSaleOffPopupViewController",@"GOFast_VPN.NewPaywallViewController",
          @"GOFast_VPN.PaywallEndTimeViewController",@"GOFast_VPN.MainPaywallViewController",
          @"GOFast_VPN.PaywallChangeServerViewController"] containsObject:NSStringFromClass(root.class)])return root;
    for(UIViewController *child in root.childViewControllers) {
        UIViewController *found=PresentedOnboarding(child);if(found)return found;
    }
    return nil;
}
static BOOL CloseNativeOnboarding(UIWindow *window) {
    if(!Connecting)return NO;
    UIViewController *page=PresentedOnboarding(window.rootViewController);
    if(!page || !page.isViewLoaded)return NO;
    // Use only the App's existing available dismissal. Never manufacture a
    // home controller, accept consent, purchase, or alter entitlement state.
    if(page.presentedViewController){VPNIPCRecordStage([Provider stringByAppendingString:@".prepare"],204);return NO;}
    // Wait for an earlier native dismissal to finish instead of double tapping.
    if(DismissedPage==page)return NO;
    UIControl *button=[page respondsToSelector:@selector(closeButton)]?[(id)page closeButton]:nil;
    if(!button) {
        NSMutableArray *queue=[NSMutableArray arrayWithObject:page.view];
        for(NSUInteger index=0;index<queue.count && index<200;index++) {
            UIView *view=queue[index];
            if([view isKindOfClass:UIControl.class] && !view.hidden && view.alpha>=0.5) {
                UIControl *control=(UIControl *)view;
                for(id target in control.allTargets)
                    if(target==page && [[control actionsForTarget:target forControlEvent:UIControlEventTouchUpInside]
                        containsObject:@"onCloseAction:"])button=control;
                if(button)break;
            }
            if(!view.hidden)[queue addObjectsFromArray:view.subviews];
        }
    }
    if(![button isKindOfClass:UIControl.class] || !button.enabled || button.hidden || button.alpha<0.5)return NO;
    DismissedPage=page;
    [button sendActionsForControlEvents:UIControlEventTouchUpInside];
    VPNIPCRecordStage([Provider stringByAppendingString:@".prepare"],205);
    return YES;
}
static UIViewController *Controller(void) {
    NSString *name=[Provider isEqual:@"hotspot"] ? @"ViewController" :
        ([Provider isEqual:@"gofast"] ? @"GOFast_VPN.HomeScreenViewController" : @"ToPreapredListVC");
    for(UIWindow *window in UIApplication.sharedApplication.windows) {
        if([Provider isEqual:@"gofast"]) {
            LoadExistingViews(window.rootViewController,0);
            if(!PreparedAppearance && window.rootViewController) {
                PreparedAppearance=YES;
                [window.rootViewController beginAppearanceTransition:YES animated:NO];
                [window.rootViewController endAppearanceTransition];
            }
            CloseNativeOnboarding(window);
        }
        UIViewController *found=Find(window.rootViewController,name);if(found)return found;
    }
    for(UIScene *scene in UIApplication.sharedApplication.connectedScenes)
        if([scene isKindOfClass:UIWindowScene.class]) for(UIWindow *window in ((UIWindowScene *)scene).windows) {
            if([Provider isEqual:@"gofast"])LoadExistingViews(window.rootViewController,0);
            UIViewController *found=Find(window.rootViewController,name);if(found)return found;
        }
    id delegate=UIApplication.sharedApplication.delegate;
    if([delegate respondsToSelector:@selector(window)]) {
        UIWindow *window=[delegate window];
        UIViewController *found=Find(window.rootViewController,name);if(found)return found;
    }
    return nil;
}
static void StopNative(void) {
    UIViewController *controller=Controller();
    if([Provider isEqual:@"hotspot"] && [controller respondsToSelector:@selector(stopBtnClick)])
        [(id)controller stopBtnClick];
    else if([Provider isEqual:@"gofast"] && [controller respondsToSelector:@selector(connectButton)] &&
        (Manager.connection.status==NEVPNStatusConnecting || Manager.connection.status==NEVPNStatusConnected ||
         Manager.connection.status==NEVPNStatusReasserting)) {
        UIControl *button=[(id)controller connectButton];
        if([button isKindOfClass:UIControl.class] && button.enabled)
            [button sendActionsForControlEvents:UIControlEventTouchUpInside];
    }
    else if([Provider isEqual:@"jump"]) {
        Class cls=NSClassFromString(@"TradesService");id model=[cls respondsToSelector:@selector(shared)]?[cls shared]:nil;
        NSMethodSignature *signature=[model methodSignatureForSelector:@selector(theVersionOpinionatedChanged)];
        if(signature.numberOfArguments==2 && !strcmp(signature.methodReturnType,"v")) [model theVersionOpinionatedChanged];
    }
    // Stops only the manager loaded for this exact App. No global disconnect.
    [Manager.connection stopVPNTunnel];
}
static void Finish(NSInteger code, BOOL cancel) {
    if(!Generation)return;
    VPNIPCRecordStage([Provider stringByAppendingString:@".native"],100+(uint64_t)code);
    VPNIPCReply reply=Reply;
    Generation=0;Reply=nil;
    if(Timer){dispatch_source_cancel(Timer);Timer=nil;}
    if(cancel && Invoked) StopNative();
    Manager=nil;Invoked=NO;
    if(reply)reply(code);
}
static BOOL HasPresented(UIViewController *root) {
    if(root.presentedViewController)return YES;
    for(UIViewController *child in root.childViewControllers)if(HasPresented(child))return YES;
    return NO;
}
static UIViewController *DeepestPresented(UIViewController *root) {
    if(root.presentedViewController)return DeepestPresented(root.presentedViewController)?:root.presentedViewController;
    for(UIViewController *child in root.childViewControllers) {
        UIViewController *page=DeepestPresented(child);if(page)return page;
    }
    return nil;
}
static void Tick(void) {
    if(!Generation)return;
    if(!UIApplication.sharedApplication.protectedDataAvailable){Finish(VPNReplyLocked,YES);return;}
    if(Deadline.timeIntervalSinceNow<=0){Finish(VPNReplyTimeout,YES);return;}
    if(!Manager) {
        if(Loading)return;
        VPNIPCRecordStage([Provider stringByAppendingString:@".prepare"],200);
        Loading=YES;uint64_t generation=Generation;
        [NETunnelProviderManager loadAllFromPreferencesWithCompletionHandler:^(NSArray *managers,NSError *error){
            dispatch_async(dispatch_get_main_queue(),^{
                if(Generation!=generation)return;
                Loading=NO;
                VPNIPCRecordStage([Provider stringByAppendingString:@".prepare"],201);
                if(error || managers.count!=1){Finish(VPNReplyUnavailable,NO);return;}
                Manager=managers.firstObject;
            });
        }];return;
    }
    // Stopping is a manager operation, not a navigation operation. Never let
    // a new promotional page prevent cancellation of the exact active tunnel.
    if(!Connecting) {
        if(!Invoked){StopNative();Invoked=YES;}
        if(Manager.connection.status==NEVPNStatusDisconnected || Manager.connection.status==NEVPNStatusInvalid)
            Finish(VPNReplyDisconnected,NO);
        else if(Manager.connection.status!=NEVPNStatusDisconnecting)[Manager.connection stopVPNTunnel];
        return;
    }
    if(Connecting && Manager.connection.status==NEVPNStatusConnected){Finish(VPNReplyConnected,NO);return;}
    UIViewController *controller=Controller();
    // The App already created this exact native controller during launch.
    // Load its normal view initialization without activating a foreground scene
    // or manufacturing a replacement controller to skip onboarding.
    if(controller && !controller.isViewLoaded)[controller loadViewIfNeeded];
    if(!controller || !controller.isViewLoaded){
        VPNIPCRecordStage([Provider stringByAppendingString:@".prepare"],202);
        if(!LoggedRoot) {
            NSMutableArray *roots=[NSMutableArray array];
            for(UIWindow *window in UIApplication.sharedApplication.windows)
                DescribeControllers(window.rootViewController,roots,0);
            NSLog(@"VPNCC_NATIVE_ROOT provider=%@ controller=%@ loaded=%d windows=%@ scenes=%lu",Provider,
                NSStringFromClass(controller.class)?:@"nil",controller.isViewLoaded,roots,
                (unsigned long)UIApplication.sharedApplication.connectedScenes.count);
            LoggedRoot=YES;
        }
        return;
    }
    if(HasPresented(controller.navigationController ?: controller)){
        NSMutableArray *tree=[NSMutableArray array];DescribeControllers(controller.navigationController ?: controller,tree,0);
        NSLog(@"VPNCC_NATIVE_PRESENTED provider=%@ controllers=%@",Provider,[tree componentsJoinedByString:@" | "]);
        UIViewController *page=DeepestPresented(controller.navigationController ?: controller);
        if([Provider isEqual:@"gofast"]) {
            NSMutableArray *bindings=[NSMutableArray array];
            for(UIView *v in page.view.subviews)if([v isKindOfClass:UIControl.class]) {
                for(id target in ((UIControl *)v).allTargets)
                    for(NSString *selector in [(UIControl *)v actionsForTarget:target forControlEvent:UIControlEventTouchUpInside])
                        [bindings addObject:@{@"target":NSStringFromClass([target class]),@"selector":selector,
                            @"hidden":@(v.hidden),@"enabled":@(((UIControl *)v).enabled)}];
            }
            NSDictionary *diagnostic=@{@"class":NSStringFromClass(page.class)?:@"nil",@"bindings":bindings};
            [[NSJSONSerialization dataWithJSONObject:diagnostic options:0 error:nil]
                writeToFile:[NSTemporaryDirectory() stringByAppendingPathComponent:@"vpncc-onboarding-diagnostic.json"] atomically:YES];
        }
        NSArray *known=@[@"GOFast_VPN.PaywallOnboardViewController",@"GOFast_VPN.PaywallOpenAppViewController",
            @"GOFast_VPN.PaywallSaleOffPopupViewController",@"GOFast_VPN.NewPaywallViewController",
            @"GOFast_VPN.PaywallEndTimeViewController",@"UMPConsentViewController"];
        NSUInteger index=[known indexOfObject:NSStringFromClass(page.class)?:@""];
        VPNIPCRecordStage([Provider stringByAppendingString:@".popup"],index==NSNotFound?299:220+index);
        VPNIPCRecordStage([Provider stringByAppendingString:@".native"],202);Finish(VPNReplyInteraction,YES);return;
    }
    if(!Invoked) {
        @try {
            if(Connecting) {
                if([Provider isEqual:@"hotspot"] && [controller respondsToSelector:@selector(startBtnClick)])
                    [(id)controller startBtnClick];
                else if([Provider isEqual:@"gofast"] && [controller respondsToSelector:@selector(connectButton)]) {
                    UIControl *button=[(id)controller connectButton];
                    if(!button || !button.enabled || button.hidden)return;
                    [button sendActionsForControlEvents:UIControlEventTouchUpInside];
                } else if([Provider isEqual:@"jump"]) {
                    Class cls=NSClassFromString(@"TradesService");id model=[cls respondsToSelector:@selector(shared)]?[cls shared]:nil;
                    if(![model respondsToSelector:@selector(adsourceData)] || ![model adsourceData]){VPNIPCRecordStage([Provider stringByAppendingString:@".prepare"],203);return;}
                    UIControl *button=JumpConnectionControl(controller.view,0);if(!button)return;
                    [button sendActionsForControlEvents:UIControlEventTouchUpInside];
                } else {Finish(VPNReplyUnavailable,NO);return;}
            } else StopNative();
            Invoked=YES;
            VPNIPCRecordStage([Provider stringByAppendingString:@".native"],210);
            VPNIPCRecordStage([Provider stringByAppendingString:@".prepare"],210);
        } @catch(NSException *exception){(void)exception;Finish(VPNReplyFailed,YES);return;}
    }
    uint64_t generation=Generation;
    [NETunnelProviderManager loadAllFromPreferencesWithCompletionHandler:^(NSArray *managers,NSError *error){
        dispatch_async(dispatch_get_main_queue(),^{
            if(Generation!=generation)return;
            if(error || managers.count!=1){Finish(VPNReplyUnavailable,YES);return;}
            Manager=managers.firstObject;
            VPNIPCRecordStage([Provider stringByAppendingString:@".manager"],(uint64_t)Manager.connection.status);
            if(Connecting && Manager.connection.status==NEVPNStatusConnected)Finish(VPNReplyConnected,NO);
            else if(!Connecting && (Manager.connection.status==NEVPNStatusDisconnected || Manager.connection.status==NEVPNStatusInvalid))
                Finish(VPNReplyDisconnected,NO);
        });
    }];
}
__attribute__((constructor)) static void Initialize(void) {
    @autoreleasepool {
        NSString *bundle=NSBundle.mainBundle.bundleIdentifier;
        for(NSString *provider in @[@"hotspot",@"gofast",@"jump"])if([VPNBundle(provider) isEqual:bundle])Provider=provider;
        if(!Provider)return;
        NSString *version=@{@"hotspot":@"2.0.2",@"gofast":@"1.4.0",@"jump":@"1.1.0"}[Provider];
        if(![[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] isEqual:version])return;
        Server=[[VPNIPCServer alloc] initWithProvider:Provider command:^(uint64_t generation,BOOL connect,VPNIPCReply reply){
            if(Generation){reply(VPNReplyUnavailable);return;}
            if(!UIApplication.sharedApplication.protectedDataAvailable){reply(VPNReplyLocked);return;}
            Generation=generation;Connecting=connect;Reply=reply;Invoked=NO;Loading=NO;LoggedRoot=NO;DismissedPage=nil;Manager=nil;
            Deadline=[NSDate dateWithTimeIntervalSinceNow:connect?([Provider isEqual:@"gofast"]?65:40):20];
            // The authenticated SpringBoard IPC client already owns a finite
            // FinishTask assertion. A second UIKit background task can expire
            // at its shared per-App budget and falsely cancel a live request.
            // Socket closure/deadline cancels the exact native request instead.
            Timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
            dispatch_source_set_timer(Timer,dispatch_time(DISPATCH_TIME_NOW,0),NSEC_PER_SEC/2,NSEC_PER_MSEC*50);
            dispatch_source_set_event_handler(Timer,^{Tick();});dispatch_resume(Timer);
        } cancel:^(uint64_t generation){if(Generation==generation)Finish(VPNReplyTimeout,YES);}];
    }
}
