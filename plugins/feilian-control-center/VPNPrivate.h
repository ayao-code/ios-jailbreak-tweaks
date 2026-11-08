#import <Foundation/Foundation.h>

// Signatures verified against iOS 16.3 VPNPreferences on the target device.
@interface NSObject (FeilianVPNPrivate)
+ (instancetype)sharedInstance;
- (NSArray *)vpnServicesForCurrentSetWithGrade:(NSUInteger)grade;
- (id)connectionWithServiceID:(id)serviceID withGrade:(NSUInteger)grade;
- (NSString *)bundleID;
- (NSString *)displayName;
- (BOOL)connected;
- (BOOL)notDisconnectedOrDisconnecting;
- (BOOL)isProviderAvailable;
- (NSUInteger)status;
- (void)connect;
- (void)disconnect;
@end
