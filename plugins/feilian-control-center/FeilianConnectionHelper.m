#import <UIKit/UIKit.h>
#import <NetworkExtension/NetworkExtension.h>
#import "Shared/VPNIPC.h"

@interface NSObject (VPNFeilianNative)
+ (id)share;
- (BOOL)isLogin;
- (id)tunnel;
- (void)connect:(void (^)(NSError *))completion;
- (void)disconnect;
@end

static VPNIPCServer *Server;
static uint64_t Request;
static VPNIPCReply Reply;
static id Tunnel;
static dispatch_source_t ConnectionObserver;
static BOOL ReadingConnection;
static void Finish(NSInteger code, BOOL stop);
static void CheckConnected(uint64_t generation) {
    if(Request!=generation || ReadingConnection)return;
    ReadingConnection=YES;
    [NETunnelProviderManager loadAllFromPreferencesWithCompletionHandler:^(NSArray *managers,NSError *error){
        dispatch_async(dispatch_get_main_queue(),^{
            if(Request!=generation)return;
            ReadingConnection=NO;
            if(!error && managers.count==1 &&
                ((NETunnelProviderManager *)managers.firstObject).connection.status==NEVPNStatusConnected)
                Finish(VPNReplyConnected,NO);
        });
    }];
}
static void CheckStopped(uint64_t generation,NSUInteger attempts) {
    [NETunnelProviderManager loadAllFromPreferencesWithCompletionHandler:^(NSArray *managers,NSError *error){
        dispatch_async(dispatch_get_main_queue(),^{
            if(Request!=generation)return;
            if(error || managers.count!=1){Finish(VPNReplyUnavailable,NO);return;}
            NETunnelProviderManager *manager=managers.firstObject;
            if(manager.connection.status==NEVPNStatusDisconnected || manager.connection.status==NEVPNStatusInvalid){Finish(VPNReplyDisconnected,NO);return;}
            [manager.connection stopVPNTunnel];
            if(!attempts){Finish(VPNReplyFailed,NO);return;}
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{
                if(Request==generation)CheckStopped(generation,attempts-1);
            });
        });
    }];
}

static void Finish(NSInteger code, BOOL stop) {
    if (!Request) return;
    VPNIPCReply reply = Reply; id tunnel = Tunnel;
    if(ConnectionObserver){dispatch_source_cancel(ConnectionObserver);ConnectionObserver=nil;}
    ReadingConnection=NO;
    Request = 0; Reply = nil; Tunnel = nil;
    if (stop && [tunnel respondsToSelector:@selector(disconnect)]) [tunnel disconnect];
    if (reply) reply(code);
}
__attribute__((constructor)) static void Initialize(void) {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.volcengine.corplink"]) return;
        VPNIPCRecordStage(@"feilian", 100);
        Server = [[VPNIPCServer alloc] initWithProvider:@"feilian" command:^(uint64_t generation, BOOL connect, VPNIPCReply reply) {
            UIApplication *app = UIApplication.sharedApplication;
            if (Request) { reply(VPNReplyUnavailable); return; }
            if (!app.protectedDataAvailable) { reply(VPNReplyLocked); return; }
            Class cls = NSClassFromString(@"TopGoModel");
            id model = [cls respondsToSelector:@selector(share)] ? [cls share] : nil;
            if (![model respondsToSelector:@selector(isLogin)] || ![model isLogin]) { reply(VPNReplyInteraction); return; }
            id tunnel = [model respondsToSelector:@selector(tunnel)] ? [model tunnel] : nil;
            if (![NSStringFromClass([tunnel class]) isEqual:@"FLTunnelManager"] || ![tunnel respondsToSelector:@selector(connect:)]) { reply(VPNReplyUnavailable); return; }
            if(!connect) {
                if(![tunnel respondsToSelector:@selector(disconnect)]){reply(VPNReplyUnavailable);return;}
                Request=generation;Reply=reply;Tunnel=tunnel;
                [tunnel disconnect];CheckStopped(generation,8);return;
            }
            Request = generation; Reply = reply; Tunnel = tunnel;
            ReadingConnection=NO;
            ConnectionObserver=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
            dispatch_source_set_timer(ConnectionObserver,dispatch_time(DISPATCH_TIME_NOW,250*NSEC_PER_MSEC),
                500*NSEC_PER_MSEC,50*NSEC_PER_MSEC);
            dispatch_source_set_event_handler(ConnectionObserver,^{CheckConnected(generation);});
            dispatch_resume(ConnectionObserver);
            // The authenticated client owns a finite execution assertion.
            // A second UIKit task shares an already-consumed App background
            // budget and can cancel a valid system-arbitrated switch early.
            [tunnel connect:^(NSError *error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (Request != generation) return;
                    Finish(error ? VPNReplyFailed : VPNReplyConnected, error != nil);
                });
            }];
        } cancel:^(uint64_t generation) { if (Request == generation) Finish(VPNReplyTimeout, YES); }];
    }
}
