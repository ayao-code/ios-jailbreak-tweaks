#import "ASGCache.h"
#import "ASGPolicy.h"

static BOOL ASGString(id value, NSUInteger limit) {
    return [value isKindOfClass:NSString.class] && [value length] > 0 && [value length] <= limit;
}

static BOOL ASGRecordValid(NSDictionary *r) {
    if (![r isKindOfClass:NSDictionary.class] || r.count != 8) return NO;
    if (!ASGString(r[@"environment"], 512) || !ASGString(r[@"contextClass"], 160)
        || !ASGString(r[@"controlClass"], 160) || !ASGString(r[@"semantic"], 16)
        || ![r[@"identifier"] isKindOfClass:NSString.class] || [r[@"identifier"] length] > 160) return NO;
    NSArray *path = r[@"path"], *rect = r[@"rect"];
    if (![path isKindOfClass:NSArray.class] || path.count > 16 || path.count == 0
        || ![rect isKindOfClass:NSArray.class] || rect.count != 4) return NO;
    for (id value in path) {
        if (![value isKindOfClass:NSNumber.class] || [value doubleValue] != [value integerValue]
            || [value integerValue] < 0 || [value integerValue] > 199) return NO;
    }
    for (id value in rect) if (![value isKindOfClass:NSNumber.class]) return NO;
    if (!ASGRectValid([rect[0] doubleValue], [rect[1] doubleValue], [rect[2] doubleValue], [rect[3] doubleValue])) return NO;
    id confirmed = r[@"confirmedAt"];
    if (![confirmed isKindOfClass:NSNumber.class] || !isfinite([confirmed doubleValue]) || [confirmed doubleValue] <= 0) return NO;
    return [r[@"semantic"] isEqual:@"skip"] || [r[@"semantic"] isEqual:@"close_ad"];
}

@implementation ASGCache {
    NSURL *_url;
    dispatch_queue_t _io;
    NSMutableArray<NSDictionary *> *_records;
    NSMutableDictionary<NSString *, NSNumber *> *_confirmations;
    uint64_t _revision;
    BOOL _loaded;
    BOOL _dirty;
    unsigned _writeFailures;
}

- (instancetype)initWithFileURL:(NSURL *)url {
    if ((self = [super init])) {
        _url = url;
        static dispatch_queue_t sharedIO;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            sharedIO = dispatch_queue_create("ayao.autoskipguard.cache", DISPATCH_QUEUE_SERIAL);
            dispatch_set_target_queue(sharedIO, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
        });
        _io = sharedIO;
        _records = [NSMutableArray array];
        _confirmations = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)load {
    NSAssert(NSThread.isMainThread, @"Cache ownership must be main-thread");
    if (_loaded) return;
    _loaded = YES;
    uint64_t revision = _revision;
    NSURL *url = _url;
    __weak ASGCache *weakSelf = self;
    dispatch_async(_io, ^{
        @autoreleasepool {
            NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:url.path error:NULL];
            NSData *data = [attrs[NSFileSize] unsignedLongLongValue] <= 16384 ? [NSData dataWithContentsOfURL:url] : nil;
            id plist = data.length <= 16384 && data.length > 0 ? [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:NULL] : nil;
            NSMutableArray *valid = [NSMutableArray array];
            if ([plist isKindOfClass:NSDictionary.class] && [plist[@"schema"] isEqual:@1]
                && [plist[@"records"] isKindOfClass:NSArray.class] && [plist[@"records"] count] <= 4) {
                for (id r in plist[@"records"]) if (ASGRecordValid(r)) [valid addObject:r];
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                ASGCache *owner = weakSelf;
                if (!owner || owner->_revision != revision) return; // Do not apply an old disk snapshot.
                owner->_records = valid;
            });
        }
    });
}

- (NSArray<NSDictionary *> *)recordsForEnvironment:(NSString *)environment {
    NSAssert(NSThread.isMainThread, @"Cache ownership must be main-thread");
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    NSMutableArray *result = [NSMutableArray array];
    for (NSDictionary *r in _records) {
        NSTimeInterval age = now - [r[@"confirmedAt"] doubleValue];
        if ([r[@"environment"] isEqual:environment] && age >= 0 && age <= 7 * 86400) [result addObject:r];
    }
    return result;
}

- (void)saveSnapshot {
    _revision++;
    _dirty = YES;
    uint64_t revision = _revision;
    NSArray *snapshot = [_records copy];
    NSURL *url = _url;
    __weak ASGCache *weakSelf = self;
    dispatch_async(_io, ^{
        @autoreleasepool {
            NSData *data = [NSPropertyListSerialization dataWithPropertyList:@{@"schema": @1, @"records": snapshot}
                                                                     format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
            BOOL valid = data && data.length <= 16384;
            BOOL directory = valid && [NSFileManager.defaultManager createDirectoryAtURL:url.URLByDeletingLastPathComponent
                                  withIntermediateDirectories:YES attributes:nil error:NULL];
            // FIFO writes guarantee that an earlier revision cannot overwrite a later one.
#if TARGET_OS_IPHONE
            BOOL saved = directory && [data writeToURL:url options:NSDataWritingAtomic | NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication error:NULL];
#else
            BOOL saved = directory && [data writeToURL:url options:NSDataWritingAtomic error:NULL];
#endif
            dispatch_async(dispatch_get_main_queue(), ^{
                ASGCache *owner = weakSelf;
                if (!owner || owner->_revision != revision) return;
                if (saved) { owner->_dirty = NO; owner->_writeFailures = 0; return; }
                // Two recovery writes maximum per burst; subsequent confirmed use may retry.
                if (++owner->_writeFailures > 2) return;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, owner->_writeFailures * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                    ASGCache *current = weakSelf;
                    if (current && current->_dirty && current->_revision == revision) [current saveSnapshot];
                });
            });
        }
    });
}

- (void)invalidateEnvironment:(NSString *)environment {
    NSAssert(NSThread.isMainThread, @"Cache ownership must be main-thread");
    NSMutableArray *remove = [NSMutableArray array];
    for (NSDictionary *r in _records) if ([r[@"environment"] isEqual:environment]) [remove addObject:r];
    [_records removeObjectsInArray:remove];
    _revision++; // Also invalidate a disk load that has not returned yet.
    for (NSString *key in [_confirmations.allKeys copy]) if ([key hasPrefix:[environment stringByAppendingString:@"|"]]) [_confirmations removeObjectForKey:key];
    if (remove.count) [self saveSnapshot];
}

- (void)confirmRecord:(NSDictionary *)record environment:(NSString *)environment {
    NSAssert(NSThread.isMainThread, @"Cache ownership must be main-thread");
    NSMutableDictionary *r = [record mutableCopy];
    r[@"environment"] = environment;
    r[@"confirmedAt"] = @(NSDate.date.timeIntervalSince1970);
    if (!ASGRecordValid(r)) return;
    NSString *identity = [NSString stringWithFormat:@"%@|%@|%@|%@|%@|%@|%@", environment, r[@"contextClass"],
                          r[@"controlClass"], r[@"identifier"], r[@"path"], r[@"rect"], r[@"semantic"]];
    unsigned count = MIN(2, [_confirmations[identity] unsignedIntValue] + 1);
    if (_confirmations.count >= 16 && !_confirmations[identity]) [_confirmations removeAllObjects];
    _confirmations[identity] = @(count);
    if (!ASGMayPromote(count, true, false)) return; // Never persist an unconfirmed candidate.
    NSDictionary *existing = nil;
    for (NSDictionary *old in _records) {
        if ([old[@"environment"] isEqual:environment] && [old[@"semantic"] isEqual:r[@"semantic"]]
            && [old[@"contextClass"] isEqual:r[@"contextClass"]]) { existing = old; break; }
    }
    NSMutableDictionary *oldContent = [existing mutableCopy], *newContent = [r mutableCopy];
    [oldContent removeObjectForKey:@"confirmedAt"]; [newContent removeObjectForKey:@"confirmedAt"];
    if (existing && [oldContent isEqual:newContent]
        && NSDate.date.timeIntervalSince1970 - [existing[@"confirmedAt"] doubleValue] < 7 * 86400) {
        if (_dirty) { _writeFailures = 0; [self saveSnapshot]; }
        return; // Valid, persisted cache hits need no timestamp write.
    }
    if (existing) [_records removeObject:existing];
    while (_records.count >= 4) [_records removeObjectAtIndex:0];
    // A caller-provided mutable array must not mutate a confirmed locator later.
    r[@"rect"] = [r[@"rect"] copy];
    r[@"path"] = [r[@"path"] copy];
    [_records addObject:[r copy]];
    [self saveSnapshot];
}
@end
