#import "AMFIManager.h"

typedef NSObject *xpc_object_t;
typedef xpc_object_t xpc_connection_t;
typedef void (^xpc_handler_t)(xpc_object_t object);

extern xpc_connection_t xpc_connection_create_mach_service(const char *name, dispatch_queue_t targetQueue, uint64_t flags);
extern void xpc_connection_set_event_handler(xpc_connection_t connection, xpc_handler_t handler);
extern void xpc_connection_resume(xpc_connection_t connection);
extern xpc_object_t xpc_connection_send_message_with_reply_sync(xpc_connection_t connection, xpc_object_t message);
extern xpc_object_t xpc_dictionary_get_value(xpc_object_t dictionary, const char *key);
extern xpc_object_t _CFXPCCreateXPCMessageWithCFObject(CFTypeRef object);
extern CFTypeRef _CFXPCCreateCFObjectFromXPCMessage(xpc_object_t object);

typedef NS_ENUM(NSInteger, AMFIAction) {
    AMFIActionArm = 0,
    AMFIActionDisable = 1,
    AMFIActionStatus = 2,
};

@implementation AMFIManager

+ (DeveloperModePreparationResult)prepareDeveloperModeWithMessage:(NSString **)message {
    xpc_connection_t connection = xpc_connection_create_mach_service("com.apple.amfi.xpc", NULL, 0);
    if (!connection) {
        if (message) {
            *message = @"无法连接 AMFI，未继续安装";
        }
        return DeveloperModePreparationResultFailed;
    }
    xpc_connection_set_event_handler(connection, ^(xpc_object_t event) {});
    xpc_connection_resume(connection);

    NSDictionary *before = [self sendAction:AMFIActionStatus connection:connection];
    if (![before[@"success"] boolValue]) {
        if (message) {
            *message = @"无法读取开发者模式状态，未继续安装";
        }
        return DeveloperModePreparationResultFailed;
    }

    BOOL enabled = [before[@"status"] boolValue];
    BOOL armed = [before[@"armed"] boolValue];
    if (enabled) {
        if (message) {
            *message = @"开发者模式已开启";
        }
        return DeveloperModePreparationResultEnabled;
    }

    if (!armed) {
        NSDictionary *armResult = [self sendAction:AMFIActionArm connection:connection];
        if (![armResult[@"success"] boolValue]) {
            if (message) {
                *message = @"无法预备开发者模式，未继续安装";
            }
            return DeveloperModePreparationResultFailed;
        }
    }

    NSDictionary *after = [self sendAction:AMFIActionStatus connection:connection];
    BOOL prepared = [after[@"success"] boolValue] && ![after[@"status"] boolValue] && [after[@"armed"] boolValue];
    if (message) {
        *message = prepared
            ? @"开发者模式已预备：请重启手机并在系统弹窗中确认打开"
            : @"开发者模式未能进入待确认状态";
    }
    return prepared ? DeveloperModePreparationResultArmed : DeveloperModePreparationResultFailed;
}

+ (NSDictionary *)sendAction:(AMFIAction)action connection:(xpc_connection_t)connection {
    NSDictionary *request = @{@"action": @(action)};
    xpc_object_t message = _CFXPCCreateXPCMessageWithCFObject((__bridge CFDictionaryRef)request);
    xpc_object_t replyMessage = xpc_connection_send_message_with_reply_sync(connection, message);
    if (!replyMessage) {
        return nil;
    }
    xpc_object_t replyObject = xpc_dictionary_get_value(replyMessage, "cfreply");
    if (!replyObject) {
        return nil;
    }
    CFTypeRef result = _CFXPCCreateCFObjectFromXPCMessage(replyObject);
    return CFBridgingRelease(result);
}

@end
