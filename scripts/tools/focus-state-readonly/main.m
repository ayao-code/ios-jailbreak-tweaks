#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <dlfcn.h>

static id ReadProperty(id object, NSString *key) {
    if (!object || ![object respondsToSelector:NSSelectorFromString(key)]) return nil;
    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static id Encode(id object, NSUInteger depth) {
    if (!object || depth > 5) return NSNull.null;
    if ([object isKindOfClass:NSString.class] || [object isKindOfClass:NSNumber.class]) return object;
    if ([object isKindOfClass:NSDate.class]) return [object description];
    if ([object isKindOfClass:NSDateComponents.class]) {
        NSDateComponents *c = object;
        return @{ @"hour": @(c.hour), @"minute": @(c.minute), @"weekday": @(c.weekday) };
    }
    if ([object isKindOfClass:NSArray.class] || [object isKindOfClass:NSSet.class]) {
        NSMutableArray *result = [NSMutableArray new];
        for (id item in object) [result addObject:Encode(item, depth + 1)];
        return result;
    }
    NSMutableDictionary *result = [NSMutableDictionary new];
    result[@"class"] = NSStringFromClass([object class]);
    // Deliberately exclude contacts, allowed apps, location and device IDs.
    for (NSString *key in @[@"mode", @"name", @"modeIdentifier", @"semanticType",
                            @"triggers", @"enabled", @"isEnabled", @"startTime", @"endTime",
                            @"startDateComponents", @"endDateComponents", @"weekdays",
                            @"daysOfWeek", @"timeInterval", @"schedule", @"activeModeIdentifier",
                            @"activeModeIdentifiers", @"isActive", @"startDate", @"suppressionState",
                            @"userVisibleTransitionDate", @"userVisibleTransitionLifetimeType"]) {
        id value = ReadProperty(object, key);
        if (value) result[key] = Encode(value, depth + 1);
    }
    return result;
}

static id Query(NSString *className, NSString *methodName, NSError **error) {
    Class cls = NSClassFromString(className);
    SEL factory = NSSelectorFromString(@"serviceForClientIdentifier:");
    SEL method = NSSelectorFromString(methodName);
    if (![cls respondsToSelector:factory]) return nil;
    id service = ((id (*)(id, SEL, id))objc_msgSend)(cls, factory, @"com.apple.FocusSettings");
    if (![service respondsToSelector:method]) return nil;
    Method definition = class_getInstanceMethod([service class], method);
    if (!definition || method_getNumberOfArguments(definition) != 3) return nil;
    char returnType[16] = {0};
    char errorType[16] = {0};
    method_getReturnType(definition, returnType, sizeof(returnType));
    method_getArgumentType(definition, 2, errorType, sizeof(errorType));
    if (returnType[0] != '@' || errorType[0] != '^' || errorType[1] != '@') return nil;
    return ((id (*)(id, SEL, NSError **))objc_msgSend)(service, method, error);
}

int main(void) {
    @autoreleasepool {
        void *framework = dlopen("/System/Library/PrivateFrameworks/DoNotDisturb.framework/DoNotDisturb", RTLD_NOW);
        if (!framework) { fprintf(stderr, "framework_unavailable\n"); return 1; }
        NSError *stateError = nil, *configurationError = nil;
        id state = Query(@"DNDStateService", @"queryCurrentStateWithError:", &stateError);
        id configurations = Query(@"DNDModeConfigurationService", @"modeConfigurationsReturningError:", &configurationError);
        NSDictionary *result = @{
            @"operation": @"read_only_no_state_change", @"time": NSDate.date.description,
            @"timezone": NSTimeZone.localTimeZone.name,
            @"weekday": @([NSCalendar.currentCalendar component:NSCalendarUnitWeekday fromDate:NSDate.date]),
            @"state": Encode(state, 0), @"mode_configurations": Encode(configurations, 0),
            @"state_error": stateError ? @{ @"domain": stateError.domain, @"code": @(stateError.code) } : NSNull.null,
            @"configuration_error": configurationError ? @{ @"domain": configurationError.domain, @"code": @(configurationError.code) } : NSNull.null
        };
        NSData *data = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil];
        if (!data) return 2;
        fwrite(data.bytes, 1, data.length, stdout);
        fputc('\n', stdout);
        return state && configurations ? 0 : 3;
    }
}
