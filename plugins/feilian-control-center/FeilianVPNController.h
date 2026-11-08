#import <Foundation/Foundation.h>

@interface FeilianVPNController : NSObject
@property (nonatomic, readonly) BOOL selected;
@property (nonatomic, readonly) BOOL busy;
@property (nonatomic, readonly) BOOL available;
@property (nonatomic, readonly) BOOL connected;
@property (nonatomic, copy) void (^stateChanged)(void);
@property (nonatomic, copy) void (^operationFailed)(NSString *message);
- (void)requestSelected:(BOOL)selected;
- (void)reload;
@end
