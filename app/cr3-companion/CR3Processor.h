#import <Foundation/Foundation.h>

@class CR3Processor;

@protocol CR3ProcessorDelegate <NSObject>
- (void)processor:(CR3Processor *)processor didUpdateSummary:(NSString *)summary canStart:(BOOL)canStart;
- (void)processor:(CR3Processor *)processor didUpdateProgress:(double)progress status:(NSString *)status;
- (void)processor:(CR3Processor *)processor didFinishWithMessage:(NSString *)message;
@end

@interface CR3Processor : NSObject

@property(nonatomic, weak) id<CR3ProcessorDelegate> delegate;
@property(nonatomic, readonly, getter=isRunning) BOOL running;

- (void)scan;
- (void)start;
- (void)pause;
- (void)verifyDecoder;

@end
