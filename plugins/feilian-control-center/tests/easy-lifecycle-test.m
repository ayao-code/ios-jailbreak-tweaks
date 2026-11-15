// Compile the actual helper with host-only UIKit/NetworkExtension stubs.
// These tests verify bookkeeping, not private iOS API or real tunnel behavior.
#import "../EasyVPNConnectionHelper.m"
NSString *const UIApplicationDidBecomeActiveNotification=@"active";
NSString *const NEVPNStatusDidChangeNotification=@"status";
@implementation UIViewController @end
@implementation UIButton @end
@implementation UIWindow @end
@implementation UIScene @end
@implementation UIWindowScene @end
@implementation UIApplication
+ (instancetype)sharedApplication { static id app; if(!app)app=[self new];return app; }
- (UIBackgroundTaskIdentifier)beginBackgroundTaskWithName:(NSString *)name expirationHandler:(void (^)(void))handler {(void)name;(void)handler;return 1;}
- (void)endBackgroundTask:(UIBackgroundTaskIdentifier)task {(void)task;}
@end
@implementation NETunnelProviderSession
- (void)stopTunnel { NSCAssert(NSThread.isMainThread,@"stop must publish on main");self.stopCount++; }
@end
@implementation NETunnelProviderManager
+ (void)loadAllFromPreferencesWithCompletionHandler:(void (^)(NSArray *, NSError *))handler {handler(@[],nil);}
@end
@implementation VPNIPCServer
- (instancetype)initWithProvider:(NSString *)provider command:(VPNIPCCommand)command cancel:(void (^)(uint64_t))cancel {(void)provider;(void)command;(void)cancel;return [super init];}
@end
void VPNIPCRecordStage(NSString *provider,uint64_t stage) {(void)provider;(void)stage;}
void MSHookMessageEx(Class cls,SEL sel,IMP imp,IMP *old) {(void)cls;(void)sel;(void)imp;(void)old;}
static dispatch_semaphore_t Entered, Resume;
static BOOL NativeResult;
static BOOL NativeStart(id session,SEL selector,NSDictionary *options,NSError **error) {
    (void)session;(void)selector;(void)options;(void)error;
    dispatch_semaphore_signal(Entered);
    dispatch_semaphore_wait(Resume,DISPATCH_TIME_FOREVER);
    return NativeResult;
}
static void PumpUntil(BOOL (^condition)(void)) {
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:3];
    while(!condition() && deadline.timeIntervalSinceNow>0)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
    NSCAssert(condition(),@"asynchronous operation did not settle");
}
static unsigned Checks;
#define CHECK(value) do { if(!(value)){fprintf(stderr,"FAILED=%s\n",#value);return 1;} Checks++; } while(0)
int main(void) {
 @autoreleasepool {
  Task=UIBackgroundTaskInvalid;atomic_init(&ActiveGeneration,0);
  __block unsigned replies=0;
  Request=@1;Reply=^(NSInteger code){(void)code;replies++;};Disconnecting=YES;Session=nil;
  Check();CHECK(replies==0 && [Request isEqual:@1]);
  Session=[NETunnelProviderSession new];Session.status=NEVPNStatusDisconnecting;
  Check();CHECK(replies==0);
  Session.status=NEVPNStatusDisconnected;Check();CHECK(replies==1 && !Request);
  OldStart=NativeStart;
  for(unsigned attempt=0;attempt<2;attempt++) {
   Request=@(attempt+10);atomic_store(&ActiveGeneration,Request.unsignedLongLongValue);
   Reply=^(NSInteger code){(void)code;replies++;};Started=NO;Session=nil;NativeResult=attempt==1;
   Entered=dispatch_semaphore_create(0);Resume=dispatch_semaphore_create(0);
   NETunnelProviderSession *native=[NETunnelProviderSession new];NSNumber *generation=Request;
   native.status=NEVPNStatusConnecting;
   __block BOOL returned=NO;
   dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
    Run(generation,^{Start(native,@selector(startTunnelWithOptions:andReturnError:),nil,NULL);});
    dispatch_async(dispatch_get_main_queue(),^{returned=YES;});
   });
   __block BOOL entered=NO;
   PumpUntil(^BOOL{if(!dispatch_semaphore_wait(Entered,DISPATCH_TIME_NOW))entered=YES;return entered;});
   CHECK(NativeStartsInFlight==1);
   Finish(VPNReplyTimeout,YES);unsigned afterCancel=replies;
   CHECK(!Request && NativeStartsInFlight==1); // admission must remain closed
   dispatch_semaphore_signal(Resume);PumpUntil(^BOOL{return returned;});
   CHECK(NativeStartsInFlight==0 && replies==afterCancel && !Session && !Started);
   CHECK(native.stopCount==(attempt==1?1u:0u));
   if(attempt==1) {
    Check();CHECK(DrainingSessions.count==1);
    native.status=NEVPNStatusDisconnected;Check();CHECK(DrainingSessions.count==0);
   }
  }
  // Already-started cancellation also blocks admission until real termination.
  Request=@30;atomic_store(&ActiveGeneration,30);Started=YES;
  Session=[NETunnelProviderSession new];Session.status=NEVPNStatusConnected;
  NETunnelProviderSession *cancelSession=Session;
  Reply=^(NSInteger code){(void)code;replies++;};
  Finish(VPNReplyTimeout,YES);Check();
  CHECK(DrainingSessions.count==1 && cancelSession.stopCount==1);
  cancelSession.status=NEVPNStatusDisconnected;Check();CHECK(!DrainingSessions.count);
  printf("EASY_LIFECYCLE_CHECKS=%u PASS=1\n",Checks);
 }
 return 0;
}
