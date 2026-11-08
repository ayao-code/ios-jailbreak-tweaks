#import <Foundation/Foundation.h>

// Access this object only on the main queue. All disk operations use one FIFO queue.
@interface ASGCache : NSObject
- (instancetype)initWithFileURL:(NSURL *)url;
- (void)load;
- (NSArray<NSDictionary *> *)recordsForEnvironment:(NSString *)environment;
- (void)invalidateEnvironment:(NSString *)environment;
- (void)confirmRecord:(NSDictionary *)record environment:(NSString *)environment;
@end
