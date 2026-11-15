#import <UIKit/UIKit.h>
#import <NetworkExtension/NetworkExtension.h>
#import <objc/runtime.h>
#import <stdatomic.h>
#import "Shared/VPNIPC.h"

extern void MSHookMessageEx(Class, SEL, IMP, IMP *);
@interface NSObject (VPNNative)
- (void)startButtonClick:(id)sender;
- (UIButton *)startButton;
- (void)stopButtonClick:(id)sender;
- (UIButton *)stopButton;
- (void)prepareManager:(void (^)(void))completion;
@end

static VPNIPCServer *Server;
static __weak UIViewController *Controller;
static NSNumber *Request;
static VPNIPCReply Reply;
static NETunnelProviderSession *Session;
static BOOL Started, Invoked, Disconnecting;
static NSUInteger NativeStartsInFlight;
static NSMutableSet<NETunnelProviderSession *> *DrainingSessions;
static UIBackgroundTaskIdentifier Task;
static NSString *const ContextKey = @"ayao.vpn.native.generation";
static atomic_uint_fast64_t ActiveGeneration;
static void (*OldLoad)(id, SEL);
static void (*OldPrepare)(id, SEL, void (^)(void));
static void (*OldBackground)(id, SEL, SEL, id);
static void (*OldMain)(id, SEL, SEL, id, BOOL);
static void (*OldPresent)(id, SEL, UIViewController *, BOOL, void (^)(void));
static BOOL (*OldStart)(id, SEL, NSDictionary *, NSError **);
static BOOL (*OldProviderMessage)(id, SEL, NSData *, NSError **, void (^)(NSData *));
static void (*OldDownload)(id, SEL, id, id, void (^)(id));

static NSNumber *Context(void) { return NSThread.currentThread.threadDictionary[ContextKey]; }
static BOOL Current(NSNumber *generation) { return !generation || atomic_load(&ActiveGeneration) == generation.unsignedLongLongValue; }
static void OnMain(void (^block)(void)) {
    if (NSThread.isMainThread) block();
    else dispatch_sync(dispatch_get_main_queue(), block);
}
static BOOL IsController(id object) {
    __block BOOL matches=NO;
    OnMain(^{ matches=object==Controller; });
    return matches;
}
static void Run(NSNumber *generation, void (^block)(void)) {
    if (!Current(generation)) return;
    NSMutableDictionary *dictionary = NSThread.currentThread.threadDictionary;
    NSNumber *previous = dictionary[ContextKey];
    if (generation) dictionary[ContextKey] = generation; else [dictionary removeObjectForKey:ContextKey];
    @try { block(); } @finally {
        if (previous) dictionary[ContextKey] = previous; else [dictionary removeObjectForKey:ContextKey];
    }
}
static void Finish(NSInteger code, BOOL stop) {
    if (!Request) return;
    VPNIPCReply reply = Reply;
    atomic_store(&ActiveGeneration, 0);
    Request = nil; Reply = nil; Invoked = NO;
    if (stop && Started && Session) {
        if(!DrainingSessions)DrainingSessions=[NSMutableSet set];
        [DrainingSessions addObject:Session];
        [Session stopTunnel];
    }
    Session = nil; Started = NO;
    if (Task != UIBackgroundTaskInvalid) {
        UIBackgroundTaskIdentifier task = Task; Task = UIBackgroundTaskInvalid;
        [UIApplication.sharedApplication endBackgroundTask:task];
    }
    if (reply) reply(code);
}
static void Check(void) {
    for(NETunnelProviderSession *session in DrainingSessions.copy)
        if(session.status==NEVPNStatusDisconnected || session.status==NEVPNStatusInvalid)
            [DrainingSessions removeObject:session];
    if(Request && Session && Disconnecting && (Session.status==NEVPNStatusDisconnected || Session.status==NEVPNStatusInvalid)) {
        Finish(VPNReplyDisconnected,NO);return;
    }
    if (Request && Started && Session.status == NEVPNStatusConnected) Finish(VPNReplyConnected, NO);
}
static UIViewController *Find(UIViewController *controller) {
    if ([NSStringFromClass(controller.class) isEqualToString:@"ViewController"]) return controller;
    for (UIViewController *child in controller.childViewControllers) { UIViewController *found = Find(child); if (found) return found; }
    return nil;
}
static void Invoke(void) {
    if (!Request || Invoked) return;
    UIApplication *app = UIApplication.sharedApplication;
    if (!app.protectedDataAvailable) { Finish(VPNReplyLocked, NO); return; }
    if (!Controller) for (UIScene *scene in app.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) { Controller = Find(window.rootViewController); if (Controller) break; }
        if (Controller) break;
    }
    if (!Controller || !Controller.isViewLoaded || app.applicationState == UIApplicationStateInactive) return;
    if (Controller.presentedViewController) { Finish(VPNReplyInteraction, NO); return; }
    Invoked = YES;
    if(Disconnecting) {
        [Controller stopButtonClick:[Controller stopButton]];
        uint64_t generation=Request.unsignedLongLongValue;
        [NETunnelProviderManager loadAllFromPreferencesWithCompletionHandler:^(NSArray *managers,NSError *error){
            dispatch_async(dispatch_get_main_queue(),^{
                if(Request.unsignedLongLongValue!=generation)return;
                if(error || managers.count!=1){Finish(VPNReplyUnavailable,NO);return;}
                Session=(id)((NETunnelProviderManager *)managers.firstObject).connection;Check();
            });
        }];return;
    }
    Run(Request, ^{ [Controller startButtonClick:[Controller startButton]]; });
}
static void Loaded(id self, SEL cmd) { OldLoad(self, cmd); OnMain(^{ Controller = self; Invoke(); }); }
static void Prepare(id self, SEL cmd, void (^completion)(void)) {
    NSNumber *generation = Context();
    if (!generation) { OldPrepare(self, cmd, completion); return; }
    OldPrepare(self, cmd, ^{ Run(generation, ^{ if (completion) completion(); }); });
}
static void Background(id self, SEL cmd, SEL selector, id object) {
    NSNumber *generation = Context();
    if (!generation || !IsController(self)) { OldBackground(self, cmd, selector, object); return; }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        Run(generation, ^{ ((void (*)(id, SEL, id))[self methodForSelector:selector])(self, selector, object); });
    });
}
static void Main(id self, SEL cmd, SEL selector, id object, BOOL wait) {
    NSNumber *generation = Context();
    if (!generation || !IsController(self)) { OldMain(self, cmd, selector, object, wait); return; }
    void (^block)(void) = ^{ Run(generation, ^{ ((void (*)(id, SEL, id))[self methodForSelector:selector])(self, selector, object); }); };
    if (NSThread.isMainThread) block();
    else if (wait) dispatch_sync(dispatch_get_main_queue(), block);
    else dispatch_async(dispatch_get_main_queue(), block);
}
static void Present(id self, SEL cmd, UIViewController *controller, BOOL animated, void (^completion)(void)) {
    NSNumber *generation=Context();
    OnMain(^{ if (generation && [Request isEqual:generation]) Finish(VPNReplyInteraction, YES); });
    // Original UI is never clicked, suppressed or continued by the helper.
    OldPresent(self, cmd, controller, animated, completion);
}
static BOOL Start(id self, SEL cmd, NSDictionary *options, NSError **error) {
    NSNumber *generation = Context();
    if (!generation) return OldStart(self, cmd, options, error);
    __block BOOL admitted=NO;
    OnMain(^{
        admitted=[Request isEqual:generation] && Current(generation);
        if(admitted) NativeStartsInFlight++;
    });
    if (!admitted) {
        if (error) *error = [NSError errorWithDomain:@"VPNControlCenter" code:VPNReplyTimeout userInfo:nil];
        return NO;
    }
    __block BOOL result=NO;
    @try { result = OldStart(self, cmd, options, error); }
    @finally {
        // Main owns request state. Keep new requests out until canceled native
        // starts have returned and their exact session has been drained.
        OnMain(^{
            if([Request isEqual:generation] && Current(generation)) {
                Session = self; Started = result;
                if (!result) Finish(VPNReplyFailed, NO); else Check();
            } else if(result) {
                if(!DrainingSessions)DrainingSessions=[NSMutableSet set];
                [DrainingSessions addObject:self];
                [(NETunnelProviderSession *)self stopTunnel];
            }
            NativeStartsInFlight--;
        });
    }
    return result;
}
static BOOL ProviderMessage(id self, SEL cmd, NSData *data, NSError **error, void (^completion)(NSData *)) {
    NSNumber *generation = Context();
    if (!generation) return OldProviderMessage(self, cmd, data, error, completion);
    return OldProviderMessage(self, cmd, data, error, ^(NSData *response) { Run(generation, ^{ if (completion) completion(response); }); });
}
static void Download(id self, SEL cmd, id tests, id source, void (^completion)(id)) {
    NSNumber *generation = Context();
    if (!generation) { OldDownload(self, cmd, tests, source, completion); return; }
    OldDownload(self, cmd, tests, source, ^(id result) { Run(generation, ^{ if (completion) completion(result); }); });
}
__attribute__((constructor)) static void Initialize(void) {
    @autoreleasepool {
        VPNIPCRecordStage(@"easy", 100);
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.qdtiktok.easyvpn"] ||
            ![[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] isEqual:@"2.1.0"]) { VPNIPCRecordStage(@"easy", 101); return; }
        Class cls = NSClassFromString(@"ViewController"), network = NSClassFromString(@"NetworkUtils");
        if (!class_getInstanceMethod(cls, @selector(startButtonClick:))) { VPNIPCRecordStage(@"easy", 102); return; }
        if (!class_getInstanceMethod(cls, @selector(prepareManager:))) { VPNIPCRecordStage(@"easy", 103); return; }
        if (!class_getClassMethod(network, NSSelectorFromString(@"downloadingTest:from:completion:"))) { VPNIPCRecordStage(@"easy", 104); return; }
        Task = UIBackgroundTaskInvalid;
        atomic_init(&ActiveGeneration, 0);
        MSHookMessageEx(cls, @selector(viewDidLoad), (IMP)Loaded, (IMP *)&OldLoad);
        MSHookMessageEx(cls, @selector(prepareManager:), (IMP)Prepare, (IMP *)&OldPrepare);
        MSHookMessageEx(cls, @selector(performSelectorInBackground:withObject:), (IMP)Background, (IMP *)&OldBackground);
        MSHookMessageEx(cls, @selector(performSelectorOnMainThread:withObject:waitUntilDone:), (IMP)Main, (IMP *)&OldMain);
        MSHookMessageEx(UIViewController.class, @selector(presentViewController:animated:completion:), (IMP)Present, (IMP *)&OldPresent);
        MSHookMessageEx(NETunnelProviderSession.class, @selector(startTunnelWithOptions:andReturnError:), (IMP)Start, (IMP *)&OldStart);
        MSHookMessageEx(NETunnelProviderSession.class, @selector(sendProviderMessage:returnError:responseHandler:), (IMP)ProviderMessage, (IMP *)&OldProviderMessage);
        MSHookMessageEx(object_getClass(network), NSSelectorFromString(@"downloadingTest:from:completion:"), (IMP)Download, (IMP *)&OldDownload);
        Server = [[VPNIPCServer alloc] initWithProvider:@"easy" command:^(uint64_t generation, BOOL connect, VPNIPCReply reply) {
            Check();
            if (Request || NativeStartsInFlight || DrainingSessions.count) { reply(VPNReplyUnavailable); return; }
            if (!UIApplication.sharedApplication.protectedDataAvailable) { reply(VPNReplyLocked); return; }
            Request = @(generation); atomic_store(&ActiveGeneration, generation);
            Reply = reply; Invoked = NO; Started = NO; Session=nil; Disconnecting=!connect;
            Task = [UIApplication.sharedApplication beginBackgroundTaskWithName:@"VPNCC.easy.request" expirationHandler:^{
                if([Request isEqual:@(generation)]) Finish(VPNReplyTimeout, YES);
            }];
            if (Task == UIBackgroundTaskInvalid) { Finish(VPNReplyUnavailable, NO); return; }
            Invoke();
        } cancel:^(uint64_t generation) { if ([Request isEqual:@(generation)]) Finish(VPNReplyTimeout, YES); }];
        [NSNotificationCenter.defaultCenter addObserverForName:NEVPNStatusDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { (void)note; Check(); }];
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { (void)note; Invoke(); }];
    }
}
