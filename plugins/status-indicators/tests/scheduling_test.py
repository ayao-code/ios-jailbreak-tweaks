#!/usr/bin/env python3
"""Exercise real one-shot layout methods with a deterministic callback queue."""
from pathlib import Path
import subprocess
import sys


def extract(source, name):
    start = source.index(name)
    brace = source.index('{', start)
    depth, end = 1, brace + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


def main():
    root = Path(__file__).resolve().parents[1]
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    source = (root / 'SIController.m').read_text()
    methods = '\n'.join(extract(source, name) for name in
                        ['- (void)requestLayout', '- (void)requestStabilityCheck'])
    harness = r'''
#import <Foundation/Foundation.h>
#include <assert.h>
static NSMutableArray *queue;
static void SIEnqueue(id unused, void (^callback)(void)) {
    (void)unused; [queue addObject:[callback copy]];
}
#define dispatch_async SIEnqueue
#define dispatch_get_main_queue() nil
@interface SIController : NSObject {
 @public
    BOOL _layoutPending, _stabilityCheckPending, _stabilityCheckAttempted;
    unsigned refreshes;
}
- (void)requestLayout;
- (void)requestStabilityCheck;
- (void)refreshVisibility;
@end
@implementation SIController
- (void)refreshVisibility { refreshes++; [self requestStabilityCheck]; }
METHODS
@end
static void Drain(void) {
    unsigned steps=0;
    while (queue.count) {
        assert(++steps<=3); void (^callback)(void)=queue.firstObject;
        [queue removeObjectAtIndex:0]; callback();
    }
}
int main(void) {
 @autoreleasepool {
    queue=[NSMutableArray array]; SIController *owner=[SIController new];
    [owner requestLayout]; [owner requestLayout]; assert(queue.count==1);
    Drain(); assert(owner->refreshes==2 && !owner->_stabilityCheckPending);
    [owner requestStabilityCheck]; assert(queue.count==0);
    [owner requestLayout]; Drain(); assert(owner->refreshes==4);
    puts("PASS scheduling: coalesced lifecycle event, one stability retry, no self-rearming hidden-state queue loop");
 }
 return 0;
}
'''.replace('METHODS', methods)
    path = out / 'scheduling-harness.m'
    path.write_text(harness)
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-Wall', '-Wextra', '-Werror',
                    '-fsanitize=address,undefined', '-framework', 'Foundation',
                    str(path), '-o', str(out / 'scheduling-test')], check=True)
    subprocess.run([str(out / 'scheduling-test')], check=True)


if __name__ == '__main__':
    main()
