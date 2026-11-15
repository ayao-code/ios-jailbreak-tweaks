// B-first acceptance against the installed controller. No implementation
// replacements, source-stop commands, touch injection or copied IPC client.
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import "../../VPNModuleViewController.h"
#import "../../VPNPrivate.h"
#import "RuntimeGuard.h"
@interface NSObject (BFirstHost)
- (id)contentViewController;
@end
static id Module;
static VPNModuleViewController *View;
static AYAVPNController *Controller;
static dispatch_source_t Timer;
static NSArray *Targets;
static NSUInteger Index;
static BOOL Issued, Observing, StopIssued, ProgressChecked;
#ifdef VPN_TEST_EACH_OFF
static BOOL IndividualStop;
#endif
static CFAbsoluteTime Started;
static NSDate *Deadline;
static NSString *Original;
static void Log(NSString *line) {
 NSString *path=@"/var/mobile/Library/Caches/ayao.vpn-bfirst-test.log";
 NSFileHandle *handle=[NSFileHandle fileHandleForWritingAtPath:path];
 NSData *bytes=[[NSString stringWithFormat:@"time=%.3f %@\n",NSDate.date.timeIntervalSince1970,line] dataUsingEncoding:NSUTF8StringEncoding];
 if(!handle){[bytes writeToFile:path atomically:YES];return;}
 [handle seekToEndOfFile];[handle writeData:bytes];[handle closeFile];
}
static void Stop(void){if(Timer){dispatch_source_cancel(Timer);Timer=nil;}}
static BOOL SoleTarget(NSString *provider) {
 NSString *bundle=@{@"easy":@"com.qdtiktok.easyvpn",@"feilian":@"com.volcengine.corplink",@"hotspot":@"co.hotspot.vpn.security"}[provider];
 id store=[NSClassFromString(@"VPNConnectionStore") sharedInstance];NSUInteger active=0;BOOL target=NO;
 for(NSUInteger grade=0;grade<4;grade++)for(id key in [store vpnServicesForCurrentSetWithGrade:grade]) {
  id connection=[store connectionWithServiceID:key withGrade:grade];
  if([connection notDisconnectedOrDisconnecting]){active++;target=[[connection bundleID] isEqual:bundle] && [connection connected];}
 }
 return active==1 && target;
}
static void Tick(void) {
 if(Deadline.timeIntervalSinceNow<=0){Log(@"TEST_TIMEOUT=1");Stop();return;}
 if(Controller.busy && !ProgressChecked) {
  [View.view setNeedsLayout];[View.view layoutIfNeeded];
  UIView *button=View.buttonView;
  for(UIView *child in button.subviews)if([child isKindOfClass:UIActivityIndicatorView.class]) {
   CGPoint center=CGPointMake(CGRectGetMidX(button.bounds),CGRectGetMidY(button.bounds));
   Log([NSString stringWithFormat:@"PROGRESS index=%lu centered=%d delta_x=%.3f delta_y=%.3f animating=%d",
    (unsigned long)Index,fabs(child.center.x-center.x)<0.5 && fabs(child.center.y-center.y)<0.5,
    child.center.x-center.x,child.center.y-center.y,[(UIActivityIndicatorView *)child isAnimating]]);
   ProgressChecked=YES;
  }
 }
 if(!Controller.ready || Controller.busy || Observing)return;
#ifdef VPN_TEST_EACH_OFF
 if(IndividualStop) {
  if(Controller.failed || ![Controller.activeProvider isEqual:@"none"]) {
   Log(@"INDIVIDUAL_OFF_FAILED=1");Stop();return;
  }
  Log([NSString stringWithFormat:@"INDIVIDUAL_OFF index=%lu target=%@ passed=1",(unsigned long)Index,Targets[Index]]);
  IndividualStop=NO;Index++;Issued=NO;
 }
#endif
 if(Index>=Targets.count) {
  if(![Controller.activeProvider isEqual:@"none"]){
   if(!StopIssued){StopIssued=YES;[Controller toggle];}
   else if(Controller.failed){Log(@"FINAL_STOP_FAILED=1");Stop();}
   return;
  }
  if(![Controller.preferredProvider isEqual:Original]){[Controller applySelection:[Controller selectionIntent:Original]];return;}
  Log(@"PREFERENCE_RESTORED=1\nBFIRST_TEST_DONE=1");Stop();return;
 }
 NSString *target=Targets[Index];
 if(!Issued) {
  if(Index==0 && ![Controller.activeProvider isEqual:@"none"]){Log(@"INITIAL_VPN_ACTIVE=1");Stop();return;}
  Started=CFAbsoluteTimeGetCurrent();Issued=YES;ProgressChecked=NO;
  NSString *source=Controller.activeProvider;
  Log([NSString stringWithFormat:@"BEGIN index=%lu source=%@ target=%@",(unsigned long)Index,source,target]);
  SEL select=NSSelectorFromString(@"select:");
  ((void(*)(id,SEL,id))[View methodForSelector:select])(View,select,target);
  NSUInteger issuedIndex=Index;
#ifdef VPN_TEST_EACH_OFF
  BOOL initialTap=YES;
#else
  BOOL initialTap=Index==0;
#endif
  if(initialTap)dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{
    if(Index==issuedIndex && [Controller.preferredProvider isEqual:target] && !Controller.busy)[View buttonTapped:nil forEvent:nil];
  });
  Deadline=[NSDate dateWithTimeIntervalSinceNow:100];return;
 }
 if(CFAbsoluteTimeGetCurrent()-Started<2)return;
 if(!Controller.failed && (!Controller.connected || ![Controller.activeProvider isEqual:target]))return;
 BOOL passed=Controller.connected && [Controller.activeProvider isEqual:target] && !Controller.failed && SoleTarget(target);
 Log([NSString stringWithFormat:@"RESULT index=%lu target=%@ elapsed=%.3f sole_target=%d failed=%d active=%@ message=%@",
   (unsigned long)Index,target,CFAbsoluteTimeGetCurrent()-Started,passed,Controller.failed,Controller.activeProvider,Controller.message]);
 if(!passed){Log(@"BFIRST_SWITCH_FAILED=1");Stop();return;}
 Observing=YES;NSUInteger index=Index;
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,6*NSEC_PER_SEC),dispatch_get_main_queue(),^{
  BOOL stable=SoleTarget(target);
  Log([NSString stringWithFormat:@"SETTLED index=%lu target=%@ sole_target=%d",(unsigned long)index,target,stable]);
  Observing=NO;
  if(!stable){Log(@"SOURCE_RECLAIMED_OR_TARGET_LOST=1");Stop();return;}
  NSURLSessionConfiguration *configuration=NSURLSessionConfiguration.ephemeralSessionConfiguration;
  configuration.timeoutIntervalForRequest=10;configuration.timeoutIntervalForResource=15;
  NSURLSession *session=[NSURLSession sessionWithConfiguration:configuration];
  Observing=YES;
  [[session dataTaskWithURL:[NSURL URLWithString:@"https://www.apple.com/library/test/success.html"]
      completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){
          dispatch_async(dispatch_get_main_queue(),^{
              NSString *body=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
              BOOL networkPassed=!error && ((NSHTTPURLResponse *)response).statusCode==200 && [body containsString:@"Success"];
              Log([NSString stringWithFormat:@"NETWORK index=%lu target=%@ https=%ld success=%d error=%ld",(unsigned long)index,target,
                  (long)((NSHTTPURLResponse *)response).statusCode,[body containsString:@"Success"],(long)error.code]);
              [session finishTasksAndInvalidate];Observing=NO;
              if(!networkPassed){Log(@"BFIRST_NETWORK_FAILED=1");Stop();return;}
#ifdef VPN_TEST_EACH_OFF
              IndividualStop=YES;[View buttonTapped:nil forEvent:nil];
#else
              Index++;Issued=NO;
#endif
          });
      }] resume];
 });
}
__attribute__((constructor)) static void Initialize(void) {
 if(![NSBundle.mainBundle.bundleIdentifier isEqual:@"com.apple.springboard"])return;
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC),dispatch_get_main_queue(),^{
  Dl_info info={0};if(!dladdr((void *)Initialize,&info)||!info.dli_fname)return;
  NSString *root=@(info.dli_fname);for(unsigned i=0;i<4;i++)root=root.stringByDeletingLastPathComponent;
  NSBundle *bundle=[NSBundle bundleWithPath:[root stringByAppendingPathComponent:@"Library/ControlCenter/Bundles/FeilianControlCenter.bundle"]];
  if(![bundle load]){Log(@"BUNDLE_LOAD_FAILED=1");return;}
  id module=[bundle.principalClass new];
  if(!VPNTestSignature(module,@selector(contentViewController),2,@encode(id))){Log(@"MODULE_CONTRACT_REJECTED=1");return;}
  id view=[module contentViewController];
  if(!VPNTestObjectMatches(view,@"VPNModuleViewController",bundle.executablePath) ||
     !VPNTestSignature(view,@selector(vpn),2,@encode(id)) ||
     !VPNTestSignature(view,NSSelectorFromString(@"select:"),3,"v") ||
     !VPNTestSignature(view,@selector(buttonTapped:forEvent:),4,"v")) {
      Log(@"VIEW_CONTRACT_REJECTED=1");return;
  }
  AYAVPNController *controller=[view vpn];
  if(!VPNTestObjectMatches(controller,@"AYAVPNController",bundle.executablePath)) {
      Log(@"CONTROLLER_ORIGIN_REJECTED=1");return;
  }
  for(NSString *name in @[@"ready",@"busy",@"connected",@"failed"]) {
      if(!VPNTestSignature(controller,NSSelectorFromString(name),2,@encode(BOOL))) {
          Log(@"CONTROLLER_BOOL_CONTRACT_REJECTED=1");return;
      }
  }
  for(NSString *name in @[@"activeProvider",@"preferredProvider",@"message"]) {
      if(!VPNTestSignature(controller,NSSelectorFromString(name),2,@encode(id))) {
          Log(@"CONTROLLER_OBJECT_CONTRACT_REJECTED=1");return;
      }
  }
  if(!VPNTestSignature(controller,@selector(reload),2,"v") ||
     !VPNTestSignature(controller,@selector(toggle),2,"v") ||
     !VPNTestSignature(controller,@selector(selectionIntent:),3,@encode(id)) ||
     !VPNTestSignature(controller,@selector(applySelection:),3,"v")) {
      Log(@"CONTROLLER_OPERATION_CONTRACT_REJECTED=1");return;
  }
  Module=module;View=view;Controller=controller;[View loadViewIfNeeded];
  Original=Controller.preferredProvider;
#ifdef VPN_TEST_EACH_OFF
  Targets=@[@"easy",@"feilian",@"hotspot"];
#elif defined(VPN_TEST_FEILIAN_EASY)
  Targets=@[@"feilian",@"easy"];
#else
  Targets=@[@"easy",@"feilian",@"hotspot",@"easy",@"hotspot",@"feilian",@"easy"];
#endif
  Log([NSString stringWithFormat:@"INITIAL_PREFERENCE=%@",Original]);
  Log([NSString stringWithFormat:@"TEST_LOADED=1 version=%@",[bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"]]);
  Deadline=[NSDate dateWithTimeIntervalSinceNow:100];Timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
  dispatch_source_set_timer(Timer,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),NSEC_PER_SEC,NSEC_PER_MSEC*100);
  dispatch_source_set_event_handler(Timer,^{@try {[Controller reload];Tick();} @catch(NSException *exception){(void)exception;Log(@"HOST_RUNTIME_CONTRACT_FAILED=1");Stop();}});dispatch_resume(Timer);
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,600*NSEC_PER_SEC),dispatch_get_main_queue(),^{Stop();});
 });
}
