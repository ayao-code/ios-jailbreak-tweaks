#import <Foundation/Foundation.h>

static NSArray<NSString *> *SDPStringArray(id value) {
    if (![value isKindOfClass:NSArray.class]) {
        return @[];
    }
    NSMutableArray *strings = [NSMutableArray array];
    for (id element in value) {
        if ([element isKindOfClass:NSString.class]) {
            [strings addObject:element];
        }
    }
    return strings;
}

int main(int argumentCount, char *arguments[]) {
    @autoreleasepool {
        if (argumentCount != 2) {
            fprintf(stderr, "usage: audit-filters <local-filter-directory>\n");
            return 2;
        }
        NSString *directory = @(arguments[1]);
        NSError *error = nil;
        NSArray *files = [NSFileManager.defaultManager contentsOfDirectoryAtPath:directory error:&error];
        if (!files) {
            fprintf(stderr, "filter_directory_unavailable\n");
            return 1;
        }
        NSArray *sharedExecutables = @[@"launchd", @"securityd", @"containermanagerd", @"cfprefsd",
                                       @"pkd", @"lsd", @"accountsd", @"apsd", @"backboardd"];
        NSArray *knownFrameworks = @[@"com.apple.Foundation", @"com.apple.UIKit",
                                    @"com.apple.CoreFoundation", @"com.apple.Security"];
        NSMutableArray *filters = [NSMutableArray array];
        NSMutableArray *unparsed = [NSMutableArray array];
        NSUInteger springBoardCount = 0;
        NSUInteger sharedServiceCount = 0;
        NSUInteger frameworkCount = 0;
        for (NSString *file in [files sortedArrayUsingSelector:@selector(compare:)]) {
            if (![file.pathExtension isEqualToString:@"plist"]) {
                continue;
            }
            NSData *data = [NSData dataWithContentsOfFile:[directory stringByAppendingPathComponent:file]];
            NSPropertyListFormat format = NSPropertyListXMLFormat_v1_0;
            id object = data ? [NSPropertyListSerialization propertyListWithData:data
                options:NSPropertyListImmutable format:&format error:nil] : nil;
            id filter = [object isKindOfClass:NSDictionary.class] ? object[@"Filter"] : nil;
            if (![filter isKindOfClass:NSDictionary.class]) {
                [unparsed addObject:@{@"file": file, @"reason": @"unreadable_or_invalid_Filter"}];
                continue;
            }
            NSArray *bundles = SDPStringArray(filter[@"Bundles"]);
            NSArray *executables = SDPStringArray(filter[@"Executables"]);
            NSMutableArray *sharedTargets = [NSMutableArray array];
            NSMutableArray *frameworkTargets = [NSMutableArray array];
            for (NSString *executable in executables) {
                if ([sharedExecutables containsObject:executable]) {
                    [sharedTargets addObject:executable];
                }
            }
            for (NSString *bundle in bundles) {
                if ([knownFrameworks containsObject:bundle]) {
                    [frameworkTargets addObject:bundle];
                }
            }
            BOOL springBoard = [bundles containsObject:@"com.apple.springboard"] ||
                               [executables containsObject:@"SpringBoard"];
            springBoardCount += springBoard;
            sharedServiceCount += sharedTargets.count > 0;
            frameworkCount += frameworkTargets.count > 0;
            NSString *formatName = format == NSPropertyListOpenStepFormat ? @"openstep" :
                format == NSPropertyListBinaryFormat_v1_0 ? @"binary" : @"xml";
            [filters addObject:@{@"file": file, @"format": formatName,
                @"bundle_targets": bundles, @"executable_targets": executables,
                @"class_targets": SDPStringArray(filter[@"Classes"]),
                @"shared_service_targets": sharedTargets, @"known_framework_targets": frameworkTargets,
                @"springboard_target": @(springBoard),
                @"other_filter_keys": [[filter allKeys] sortedArrayUsingSelector:@selector(compare:)]}];
        }
        NSDictionary *report = @{@"schema_version": @1, @"scope": @"static_filter_declarations_only",
            @"counts": @{@"parsed": @(filters.count), @"unparsed": @(unparsed.count),
                @"springboard": @(springBoardCount), @"shared_services": @(sharedServiceCount),
                @"known_framework_rules": @(frameworkCount)},
            @"filters": filters, @"unparsed": unparsed,
            @"runtime_injection": @"not_proven", @"protected_app_isolation": @"not_proven",
            @"limits": @[@"Framework lists are not exhaustive; unrecognized rules remain listed.",
                         @"Declarations do not prove active loading, hook behavior or sensitive-app safety."]};
        NSData *output = [NSJSONSerialization dataWithJSONObject:report
            options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:&error];
        if (!output) {
            fprintf(stderr, "report_serialization_failed\n");
            return 1;
        }
        fwrite(output.bytes, 1, output.length, stdout);
        fputc('\n', stdout);
        return unparsed.count ? 3 : 0;
    }
}
