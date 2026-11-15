#import <Foundation/Foundation.h>

typedef struct {
    BOOL known;
    // -1 means explicitly inactive; 0..4 are DND/personal/work/game/other.
    NSInteger style;
} SIFocusSnapshot;

SIFocusSnapshot SIFocusSnapshotFromState(id state);

// Main-thread lifecycle and delivery; private service IPC runs on a utility queue.
@interface SIFocusMonitor : NSObject
- (instancetype)initWithHandler:(void (^)(SIFocusSnapshot snapshot))handler;
- (void)start;
- (void)stop;
@end

#if SI_FOCUS_TEST
@interface SIFocusMonitor (Testing)
- (instancetype)initWithHandler:(void (^)(SIFocusSnapshot snapshot))handler
                serviceFactory:(id (^)(void))factory;
@end
#endif
