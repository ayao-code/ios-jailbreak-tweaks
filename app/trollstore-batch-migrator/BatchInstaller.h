#import <Foundation/Foundation.h>

@class BatchInstaller;

@protocol BatchInstallerDelegate <NSObject>
- (void)batchInstaller:(BatchInstaller *)installer didUpdateProgress:(double)progress status:(NSString *)status;
- (void)batchInstaller:(BatchInstaller *)installer didFinishWithResults:(NSArray<NSString *> *)results success:(BOOL)success requiresRestart:(BOOL)requiresRestart;
@end

@interface BatchInstaller : NSObject
@property(nonatomic, weak) id<BatchInstallerDelegate> delegate;
@property(nonatomic, readonly, getter=isRunning) BOOL running;
- (void)start;
@end
