// Independent App-native validation. No Control Center instance or UI input.
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <notify.h>
#import "../../Shared/VPNIPC.h"
#import "../../VPNPrivate.h"
@interface NSObject (TwoNativeLaunch)
+ (id)sharedService;
- (void)openApplication:(NSString *)identifier options:(NSDictionary *)options withResult:(void (^)(NSError *))result;
@end
static void Log(NSString *line) {
 NSString *path=@"/var/mobile/Library/Caches/ayao.vpn-two-native.log";
 NSFileHandle *file=[NSFileHandle fileHandleForWritingAtPath:path];
 NSData *data=[[NSString stringWithFormat:@"%.3f %@\n",NSDate.date.timeIntervalSince1970,line] dataUsingEncoding:NSUTF8StringEncoding];
 if(!file){[data writeToFile:path atomically:YES];return;}
 [file seekToEndOfFile];[file writeData:data];[file closeFile];
}
static uint64_t Stage(NSString *provider,NSString *suffix) {
 NSString *name=[NSString stringWithFormat:@"ayao.vpn.%@.%@.diagnostic-stage.v1",provider,suffix];
 int token;uint64_t value=0;
 if(notify_register_check(name.UTF8String,&token)==NOTIFY_STATUS_OK){notify_get_state(token,&value);notify_cancel(token);}
 return value;
}
static NSString *TargetBundle(NSString *provider) {
 return [provider isEqual:@"jump"]?@"com.zenith.jump":@"com.bestapp.gofast.vpn";
}
static void SystemState(NSString *provider,unsigned round,NSString *phase) {
 NSBundle *bundle=[NSBundle bundleWithPath:@"/System/Library/PreferenceBundles/VPNPreferences.bundle"];
 if(![bundle load])return;
 id store=[NSClassFromString(@"VPNConnectionStore") sharedInstance];
 for(NSUInteger grade=0;grade<4;grade++)for(id key in [store vpnServicesForCurrentSetWithGrade:grade]) {
  id connection=[store connectionWithServiceID:key withGrade:grade];
  if([[connection bundleID] isEqual:TargetBundle(provider)])
   Log([NSString stringWithFormat:@"provider=%@ round=%u phase=%@ system_status=%lu system_connected=%d system_active=%d",
    provider,round,phase,(unsigned long)[connection status],[connection connected],[connection notDisconnectedOrDisconnecting]]);
 }
}
static void Validate(NSUInteger index) {
 if(index>=6){Log(@"TWO_APP_NATIVE_DONE=1");return;}
#ifdef VPN_TEST_GOFAST_ONLY
 NSString *provider=@"gofast";
 unsigned round=(unsigned)index+1;
#else
 NSString *provider=index%2?@"gofast":@"jump";
 unsigned round=(unsigned)(index/2+1);
#endif
 dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices",RTLD_NOW);
 NSString *const *key=(NSString *const *)dlsym(RTLD_DEFAULT,"FBSOpenApplicationOptionKeyActivateSuspended");
 id service=[NSClassFromString(@"FBSSystemService") sharedService];
 if(!key || !*key){Log(@"BACKGROUND_LAUNCH_UNAVAILABLE=1");return;}
 [service openApplication:TargetBundle(provider) options:@{*key:@YES} withResult:^(NSError *error){
  if(error){Log([NSString stringWithFormat:@"provider=%@ round=%u launch_error=%ld",provider,round,(long)error.code]);Validate(index+1);return;}
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
   Class clientClass=NSClassFromString(@"VPNIPCClient");
   VPNIPCClient *client=[[clientClass alloc] initWithProvider:provider];BOOL ready=NO;
   for(unsigned i=0;i<4 && !ready;i++){ready=[client open] && [client probe];if(!ready){[client close];[NSThread sleepForTimeInterval:0.5];}}
   Log([NSString stringWithFormat:@"provider=%@ round=%u authenticated=%d",provider,round,ready]);
   uint64_t generation=(uint64_t)(NSDate.date.timeIntervalSince1970*1000000);
   NSInteger result=ready?[client requestConnect:YES generation:generation]:VPNReplyUnavailable;
   Log([NSString stringWithFormat:@"provider=%@ round=%u connect_code=%ld native_stage=%llu prepare_stage=%llu manager_status=%llu transport=%llu execution=%llu popup=%llu",
       provider,round,(long)result,Stage(provider,@"native"),Stage(provider,@"prepare"),Stage(provider,@"manager"),Stage(provider,@"transport"),Stage(provider,@"execution"),Stage(provider,@"popup")]);
   dispatch_sync(dispatch_get_main_queue(),^{SystemState(provider,round,@"connect");});
   if(result==VPNReplyConnected) {
       NSURLSessionConfiguration *configuration=NSURLSessionConfiguration.ephemeralSessionConfiguration;
       configuration.timeoutIntervalForRequest=10;configuration.timeoutIntervalForResource=15;
       NSURLSession *session=[NSURLSession sessionWithConfiguration:configuration];
       dispatch_semaphore_t done=dispatch_semaphore_create(0);
       [[session dataTaskWithURL:[NSURL URLWithString:@"https://www.apple.com/library/test/success.html"]
           completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){
               NSString *body=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
               Log([NSString stringWithFormat:@"provider=%@ round=%u https=%ld success=%d error=%ld",provider,round,
                   (long)((NSHTTPURLResponse *)response).statusCode,[body containsString:@"Success"],(long)error.code]);
               dispatch_semaphore_signal(done);
           }] resume];
       dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,16*NSEC_PER_SEC));
       [session invalidateAndCancel];
   }
   // Stop native preparation even after a failed/timeout connect. The exact
   // App owns this manager; do not target any other configuration.
   VPNIPCClient *stop=client;
   BOOL stopReady=[stop probe];
   if(!stopReady) {
       [client close];stop=[[clientClass alloc] initWithProvider:provider];
       for(unsigned attempt=0;attempt<3 && !stopReady;attempt++) {
           if(attempt)[NSThread sleepForTimeInterval:0.25];
           stopReady=[stop open] && [stop probe];
       }
   }
   NSInteger stopped=stopReady?[stop requestConnect:NO generation:generation+1]:VPNReplyUnavailable;
   [stop close];
   Log([NSString stringWithFormat:@"provider=%@ round=%u stop_code=%ld native_stage=%llu manager_status=%llu transport=%llu execution=%llu",
      provider,round,(long)stopped,Stage(provider,@"native"),Stage(provider,@"manager"),Stage(provider,@"transport"),Stage(provider,@"execution")]);
   dispatch_sync(dispatch_get_main_queue(),^{SystemState(provider,round,@"stop");});
   dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{Validate(index+1);});
  });
 }];
}
__attribute__((constructor)) static void Initialize(void) {
 if(![NSBundle.mainBundle.bundleIdentifier isEqual:@"com.apple.springboard"])return;
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC),dispatch_get_main_queue(),^{
  Dl_info info={0};if(!dladdr((void *)Initialize,&info)||!info.dli_fname)return;
  NSString *root=@(info.dli_fname);for(unsigned i=0;i<4;i++)root=root.stringByDeletingLastPathComponent;
  NSBundle *bundle=[NSBundle bundleWithPath:[root stringByAppendingPathComponent:@"Library/ControlCenter/Bundles/FeilianControlCenter.bundle"]];
  if(![bundle load]){Log(@"BACKEND_LIBRARY_LOAD_FAILED=1");return;}
  Log(@"TWO_APP_NATIVE_STARTED=1 cc_module_used=0");Validate(0);
 });
}
