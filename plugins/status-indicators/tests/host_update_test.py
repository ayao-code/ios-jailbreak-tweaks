#!/usr/bin/env python3
"""Compile actual VPN update methods in a Foundation-only fake-host harness.

This tests the coalescing/controller state boundary, not UIKit visibility.
"""
from pathlib import Path
import subprocess
import sys


def method(source, name):
    start = source.index(name)
    brace = source.index("{", start)
    depth = 1
    end = brace + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


def main():
    root = Path(__file__).resolve().parents[1]
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    source = (root / "SIController.m").read_text()
    methods = "\n".join(method(source, name) for name in (
        "static NSNumber *SIEnabledEntry(",
        "- (void)readStateForHost:",
        "- (void)hostDidUpdateData:",
    ))
    helper, methods = methods.split("- (void)readStateForHost:", 1)
    methods = "- (void)readStateForHost:" + methods
    hide = method((root / "SIItemViews.m").read_text(), "- (void)hide")
    harness = r'''
#import <Foundation/Foundation.h>
#include <assert.h>
@interface UIView : NSObject
@property BOOL visible;
@property(strong) id currentData;
@end
@implementation UIView
@end
@interface TestItem : NSObject
@property BOOL hidden;
@end
@implementation TestItem
@end
@interface SIItemViews : NSObject {
@public
    TestItem *_vpn, *_mute, *_focus, *_focusText, *_vpnText, *_speed;
}
- (void)hide;
@end
@implementation SIItemViews
HIDE
@end
@interface TestVPNEntry : NSObject
@property BOOL enabled;
@end
@implementation TestVPNEntry
@end
@interface TestData : NSObject
@property(strong) TestVPNEntry *vpnEntry;
@end
@implementation TestData
@end
static BOOL SIHostVisible(UIView *host) { return host.visible; }
static id SICurrentData(UIView *host) { return host.currentData; }
HELPER
@interface SIController : NSObject {
@public
    BOOL _enabled, _deferredHostReadPending;
    NSHashTable<UIView *> *_knownHosts, *_dirtyHosts;
    NSMapTable *_hostStates;
    NSInteger _focusStyle;
    BOOL _muteEnabled;
    NSUInteger layouts;
}
- (void)readStateForHost:(UIView *)host;
- (void)hostDidUpdateData:(UIView *)host;
- (void)requestLayout;
@end
@implementation SIController
- (instancetype)init {
    if ((self = [super init])) {
        _knownHosts = [NSHashTable weakObjectsHashTable];
        _dirtyHosts = [NSHashTable weakObjectsHashTable];
        _hostStates = [NSMapTable weakToStrongObjectsMapTable];
        _enabled = YES; _focusStyle = 2; _muteEnabled = YES;
    }
    return self;
}
- (void)requestLayout { layouts++; }
METHODS
@end
static UIView *Host(BOOL enabled) {
    TestVPNEntry *vpn = [TestVPNEntry new]; vpn.enabled = enabled;
    TestData *data = [TestData new]; data.vpnEntry = vpn;
    UIView *host = [UIView new]; host.visible = YES; host.currentData = data;
    return host;
}
static void Flush(SIController *owner) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
    while (owner->_deferredHostReadPending && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.002]];
    assert(!owner->_deferredHostReadPending);
}
int main(void) {
    @autoreleasepool {
        SIItemViews *items = [SIItemViews new];
        items->_vpn = [TestItem new]; items->_mute = [TestItem new];
        items->_focus = [TestItem new]; items->_focusText = [TestItem new];
        items->_vpnText = [TestItem new]; items->_speed = [TestItem new];
        [items hide];
        for (TestItem *item in @[items->_vpn, items->_mute, items->_focus,
            items->_focusText, items->_vpnText, items->_speed]) assert(item.hidden);
        SIController *owner = [SIController new];
        UIView *a = Host(NO), *b = Host(NO);
        [owner readStateForHost:b]; // B has an existing disconnected cache.
        [owner hostDidUpdateData:a];
        ((TestData *)b.currentData).vpnEntry.enabled = YES;
        [owner hostDidUpdateData:b]; [owner hostDidUpdateData:b];
        Flush(owner);
        assert([[owner->_hostStates objectForKey:a] intValue] == 0);
        assert([[owner->_hostStates objectForKey:b] intValue] == 1);
        assert(owner->layouts == 1);
        assert(owner->_focusStyle == 2 && owner->_muteEnabled);
        ((TestData *)b.currentData).vpnEntry.enabled = NO;
        [owner hostDidUpdateData:b]; Flush(owner);
        assert([[owner->_hostStates objectForKey:b] intValue] == 0);
        assert(owner->_focusStyle == 2 && owner->_muteEnabled);
        [owner hostDidUpdateData:a]; owner->_enabled = NO;
        Flush(owner); assert(owner->_dirtyHosts.count == 0);
        assert(owner->layouts == 2);
        owner->_enabled = YES;
        b.visible = NO; [owner hostDidUpdateData:b]; Flush(owner);
        assert([[owner->_hostStates objectForKey:b] intValue] == 0);
        __weak UIView *released;
        @autoreleasepool {
            UIView *temporary = Host(YES); released = temporary;
            [owner hostDidUpdateData:temporary];
        }
        assert(released == nil); Flush(owner);
        assert(owner->_focusStyle == 2 && owner->_muteEnabled);
        puts("PASS VPN/views: actual methods, two-host coalescing, explicit disconnect, disabled/hidden/deallocated hosts, Focus/mute untouched, all six views hidden");
    }
}
'''.replace("HELPER", helper).replace("METHODS", methods).replace("HIDE", hide)
    path = out / "host_update_harness.m"
    path.write_text(harness)
    subprocess.run([
        "xcrun", "clang", "-fobjc-arc", "-fblocks", "-Wall", "-Wextra", "-Werror",
        "-fsanitize=address,undefined", "-g", "-framework", "Foundation", str(path),
        "-o", str(out / "host-update-test"),
    ], check=True)
    subprocess.run([str(out / "host-update-test")], check=True)


if __name__ == "__main__":
    main()
