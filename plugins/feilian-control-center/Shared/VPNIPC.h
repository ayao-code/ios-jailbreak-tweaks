#import <Foundation/Foundation.h>

// User-selected local-open protocol: no caller-origin authentication or broker.
// App sandbox/socket permissions still apply. No network listener or shell commands.
FOUNDATION_EXPORT NSString *VPNBundle(NSString *provider);
FOUNDATION_EXPORT NSArray<NSString *> *VPNProviders(void);
FOUNDATION_EXPORT BOOL VPNUsesNativeStop(NSString *provider);
FOUNDATION_EXPORT NSTimeInterval VPNTimeout(NSString *provider);
FOUNDATION_EXPORT NSString *VPNIPCSocketPath(NSString *provider);
typedef void (^VPNIPCReply)(NSInteger code);
typedef void (^VPNIPCCommand)(uint64_t generation, BOOL connect, VPNIPCReply reply);
FOUNDATION_EXPORT void VPNIPCRecordStage(NSString *provider, uint64_t stage);

@interface VPNIPCServer : NSObject
- (instancetype)initWithProvider:(NSString *)provider command:(VPNIPCCommand)command
                         cancel:(void (^)(uint64_t generation))cancel;
@end

@interface VPNIPCClient : NSObject
// All methods except close are blocking and must run off the UI thread.
- (instancetype)initWithProvider:(NSString *)provider;
- (BOOL)open;
- (BOOL)probe;
- (NSInteger)requestConnect:(BOOL)connect generation:(uint64_t)generation;
- (void)close;
@end

typedef NS_ENUM(NSInteger, VPNReply) {
    VPNReplyReady = 0, VPNReplyConnected = 1, VPNReplyDisconnected = 2,
    VPNReplyUnavailable = 3, VPNReplyLocked = 4, VPNReplyInteraction = 5,
    VPNReplyFailed = 6, VPNReplyTimeout = 7, VPNReplyUnauthorized = 8
};
