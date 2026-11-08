#import <Foundation/Foundation.h>
#import <CFNetwork/CFNetwork.h>
#include <ifaddrs.h>

int main(int argc, char *argv[])
{
    @autoreleasepool {
        if (argc != 1) return 2;
        CFDictionaryRef proxyValue = CFNetworkCopySystemProxySettings();
        NSDictionary *settings = CFBridgingRelease(proxyValue);
        NSMutableDictionary *flags = [NSMutableDictionary new];
        for (NSString *key in @[@"HTTPEnable", @"HTTPSEnable", @"SOCKSEnable", @"ProxyAutoConfigEnable"]) {
            if ([settings[key] isKindOfClass:NSNumber.class]) flags[key] = settings[key];
        }
        NSUInteger tunnels = 0;
        struct ifaddrs *interfaces = NULL;
        if (getifaddrs(&interfaces) == 0) {
            NSMutableSet *names = [NSMutableSet new];
            for (struct ifaddrs *interface = interfaces; interface; interface = interface->ifa_next) {
                if (interface->ifa_name) [names addObject:@(interface->ifa_name)];
            }
            for (NSString *name in names) if ([name hasPrefix:@"utun"]) tunnels++;
            freeifaddrs(interfaces);
        }
        NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
        configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        configuration.URLCache = nil;
        configuration.HTTPCookieStorage = nil;
        configuration.URLCredentialStorage = nil;
        configuration.timeoutIntervalForRequest = 10;
        configuration.timeoutIntervalForResource = 12;
        NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];
        NSArray *hosts = @[@"www.apple.com", @"telegram.org", @"api.telegram.org", @"x.com", @"api.x.com", @"api.twitter.com"];
        NSMutableArray *results = [NSMutableArray new];
        dispatch_group_t group = dispatch_group_create();
        for (NSString *host in hosts) {
            NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"https://%@/", host]]];
            request.HTTPMethod = @"HEAD";
            dispatch_group_enter(group);
            NSDate *start = NSDate.date;
            [[session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? [(NSHTTPURLResponse *)response statusCode] : 0;
                NSDictionary *entry = @{@"host": host, @"http_status": @(status),
                    @"error_domain": error.domain ?: @"none", @"error_code": @(error.code),
                    @"elapsed_seconds": @(-start.timeIntervalSinceNow)};
                @synchronized (results) { [results addObject:entry]; }
                dispatch_group_leave(group);
            }] resume];
        }
        BOOL completed = dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, 16 * NSEC_PER_SEC)) == 0;
        [session invalidateAndCancel];
        NSArray *snapshot;
        @synchronized (results) { snapshot = [results copy]; }
        NSDictionary *report = @{@"mode": @"public_https_head_no_accounts", @"completed": @(completed),
            @"system_proxy_enable_flags": flags, @"tunnel_interface_count": @(tunnels),
            @"results": snapshot, @"limitations": @"not_target_app_routing_or_telegram_mtproto_or_login_validation"};
        NSData *json = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:NULL];
        if (!json) return 1;
        fwrite(json.bytes, 1, json.length, stdout);
        fputc('\n', stdout);
        return completed ? 0 : 1;
    }
}
