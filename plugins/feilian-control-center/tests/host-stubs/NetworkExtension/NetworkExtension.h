#import <Foundation/Foundation.h>
typedef NS_ENUM(NSInteger, NEVPNStatus) { NEVPNStatusInvalid, NEVPNStatusDisconnected, NEVPNStatusConnecting, NEVPNStatusConnected, NEVPNStatusReasserting, NEVPNStatusDisconnecting };
@interface NETunnelProviderSession : NSObject
@property NEVPNStatus status;
@property NSUInteger stopCount;
- (void)stopTunnel;
@end
@interface NETunnelProviderManager : NSObject
@property(strong) NETunnelProviderSession *connection;
+ (void)loadAllFromPreferencesWithCompletionHandler:(void (^)(NSArray *, NSError *))handler;
@end
FOUNDATION_EXPORT NSString *const NEVPNStatusDidChangeNotification;
