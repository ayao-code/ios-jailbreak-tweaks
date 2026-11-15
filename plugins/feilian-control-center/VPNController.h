#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSString *VPNProviderName(NSString *provider);

@interface AYAVPNController : NSObject
@property (nonatomic, copy, readonly) NSString *preferredProvider;
@property (nonatomic, copy, readonly) NSString *activeProvider;
@property (nonatomic, copy, readonly) NSString *message;
@property (nonatomic, readonly) BOOL ready;
@property (nonatomic, readonly) BOOL busy;
@property (nonatomic, readonly) BOOL connected;
@property (nonatomic, readonly) BOOL failed;
@property (nonatomic, copy) void (^stateChanged)(void);
- (NSString *)statusForProvider:(NSString *)provider;
- (BOOL)canSelectProvider:(NSString *)provider;
- (NSDictionary *)selectionIntent:(NSString *)provider;
- (void)applySelection:(NSDictionary *)intent;
- (void)toggle;
- (void)reload;
- (void)openPreferredApp;
@end
