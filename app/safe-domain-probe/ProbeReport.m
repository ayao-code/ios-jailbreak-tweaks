#import "ProbeReport.h"
#import <TargetConditionals.h>
#import <arpa/inet.h>
#import <dlfcn.h>
#import <errno.h>
#import <fcntl.h>
#import <mach-o/dyld.h>
#import <poll.h>
#import <stdio.h>
#import <string.h>
#import <sys/mman.h>
#import <stdlib.h>
#import <sys/socket.h>
#import <sys/stat.h>
#import <sys/sysctl.h>
#import <sys/utsname.h>
#import <unistd.h>

#if TARGET_OS_IPHONE && !defined(SDP_APP_EXTENSION)
#import <UIKit/UIKit.h>
#endif

extern char **environ;

static NSDictionary *SDPImageDescription(const char *imagePath) {
    NSString *path = imagePath ? @(imagePath) : @"";
    NSString *lowercase = path.lowercaseString;
    BOOL knownMarker = [lowercase containsString:@"/var/jb/"] ||
        [lowercase containsString:@".jbroot-"] ||
        [lowercase containsString:@"tweakinject"] ||
        [lowercase containsString:@"substrate"] ||
        [lowercase containsString:@"ellekit"] ||
        [lowercase containsString:@"libhooker"] ||
        [lowercase containsString:@"systemhook"];
    NSString *location = @"other";
    NSString *bundle = NSBundle.mainBundle.bundlePath;
    NSString *hostBundle = NSBundle.mainBundle.bundleURL.URLByDeletingLastPathComponent
        .URLByDeletingLastPathComponent.path;
    if (knownMarker) {
        location = @"known_jailbreak_path_or_name";
    } else if ([path hasPrefix:[bundle stringByAppendingString:@"/"]] ||
               ([NSBundle.mainBundle.bundlePath.pathExtension isEqualToString:@"appex"] &&
                [path hasPrefix:[hostBundle stringByAppendingString:@"/"]])) {
        location = @"own_bundle";
    } else if ([path hasPrefix:@"/System/Library/"] || [path hasPrefix:@"/usr/lib/"]) {
        location = @"system_path_not_signature_attested";
    }
    return @{@"name": path.lastPathComponent ?: @"", @"location": location,
             @"known_jailbreak_marker": @(knownMarker)};
}

static NSArray *SDPLoadedImages(void) {
    NSMutableArray *images = [NSMutableArray array];
    uint32_t count = _dyld_image_count();
    for (uint32_t index = 0; index < count; index++) {
        [images addObject:SDPImageDescription(_dyld_get_image_name(index))];
    }
    return images;
}

static NSDictionary *SDPEnvironmentPresence(void) {
    NSArray *keys = @[@"DYLD_INSERT_LIBRARIES", @"DYLD_LIBRARY_PATH", @"JBROOT",
                      @"JB_ROOT_PATH", @"JB_SANDBOX_EXTENSIONS", @"JBRAND",
                      @"_SafeMode", @"_MSSafeMode"];
    NSMutableDictionary *presence = [NSMutableDictionary dictionary];
    for (NSString *key in keys) {
        presence[key] = @((BOOL)(getenv(key.UTF8String) != NULL));
    }
    return presence;
}

static NSDictionary *SDPEnvironmentContentMarkerPresence(void) {
    BOOL mixedCaseMarker = NO;
    BOOL lowercaseMarker = NO;
    for (char **entry = environ; entry && *entry; entry++) {
        mixedCaseMarker = mixedCaseMarker || strstr(*entry, "MobileSubstrate") != NULL;
        lowercaseMarker = lowercaseMarker || strstr(*entry, "mobilesubstrate") != NULL;
    }
    return @{@"MobileSubstrate": @(mixedCaseMarker),
             @"mobilesubstrate": @(lowercaseMarker)};
}

static NSDictionary *SDPCodeSigningState(void) {
    int (*queryFlags)(pid_t, unsigned int, void *, size_t) = dlsym(RTLD_DEFAULT, "csops");
    if (!queryFlags) {
        return @{@"status": @"unavailable"};
    }
    uint32_t flags = 0;
    errno = 0;
    int result = queryFlags(getpid(), 0, &flags, sizeof(flags));
    if (result != 0) {
        return @{@"status": @"query_failed", @"errno": @(errno)};
    }
    return @{@"status": @"observed", @"flags_hex": [NSString stringWithFormat:@"0x%08x", flags],
             @"valid": @((BOOL)((flags & 0x00000001) != 0)),
             @"get_task_allow": @((BOOL)((flags & 0x00000004) != 0)),
             @"platform_binary": @((BOOL)((flags & 0x04000000) != 0)),
             @"debugged": @((BOOL)((flags & 0x10000000) != 0))};
}

static NSDictionary *SDPEntitlementState(void) {
    CFTypeRef (*createTask)(CFAllocatorRef) = dlsym(RTLD_DEFAULT, "SecTaskCreateFromSelf");
    CFTypeRef (*copyValue)(CFTypeRef, CFStringRef, CFErrorRef *) =
        dlsym(RTLD_DEFAULT, "SecTaskCopyValueForEntitlement");
    if (!createTask || !copyValue) {
        return @{@"status": @"unavailable", @"values": @{}};
    }
    CFTypeRef task = createTask(kCFAllocatorDefault);
    if (!task) {
        return @{@"status": @"task_creation_failed", @"values": @{}};
    }
    NSArray *keys = @[@"platform-application", @"get-task-allow",
        @"com.apple.private.security.no-container", @"com.apple.private.security.no-sandbox",
        @"com.apple.private.security.storage.AppDataContainers",
        @"com.apple.private.security.storage.AppBundles",
        @"com.apple.private.security.storage.AppGroupContainers"];
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    for (NSString *key in keys) {
        CFErrorRef queryError = NULL;
        CFTypeRef value = copyValue(task, (__bridge CFStringRef)key, &queryError);
        if (value) {
            if (CFGetTypeID(value) == CFBooleanGetTypeID()) {
                values[key] = @{@"status": @"observed", @"enabled": @((BOOL)CFBooleanGetValue(value))};
            } else {
                values[key] = @{@"status": @"observed_non_boolean", @"enabled": @YES};
            }
            CFRelease(value);
        } else {
            values[key] = @{@"status": queryError ? @"query_error" : @"not_present"};
        }
        if (queryError) {
            CFRelease(queryError);
        }
    }
    CFRelease(task);
    return @{@"status": @"queried", @"values": values};
}

static NSString *SDPFilesystemResult(int result, int errorNumber) {
    if (result == 0) {
        return @"visible";
    }
    if (errorNumber == EACCES || errorNumber == EPERM) {
        return @"denied";
    }
    if (errorNumber == ENOENT) {
        return @"not_found";
    }
    return @"other_error";
}

static NSArray *SDPPathObservations(void) {
    NSArray *paths = @[@"/var/jb", @"/var/jb/usr/lib", @"/Applications/Cydia.app",
                       @"/Library/MobileSubstrate/MobileSubstrate.dylib",
                       @"/etc/apt", @"/private/var/lib/apt", @"/var/lib/cydia/",
                       @"/User/Applications/", @"/bin/bash", @"/usr/sbin/sshd"];
    NSMutableArray *observations = [NSMutableArray array];
    for (NSString *path in paths) {
        struct stat metadata = {0};
        errno = 0;
        int result = stat(path.UTF8String, &metadata);
        int errorNumber = result == 0 ? 0 : errno;
        [observations addObject:@{@"path": path, @"operation": @"stat_read_only",
            @"result": SDPFilesystemResult(result, errorNumber), @"errno": @(errorNumber)}];

        errno = 0;
        result = access(path.UTF8String, F_OK);
        errorNumber = result == 0 ? 0 : errno;
        [observations addObject:@{@"path": path, @"operation": @"access_f_ok_read_only",
            @"result": SDPFilesystemResult(result, errorNumber), @"errno": @(errorNumber)}];

        errno = 0;
        FILE *stream = fopen(path.UTF8String, "r");
        errorNumber = stream ? 0 : errno;
        if (stream) {
            fclose(stream);
        }
        [observations addObject:@{@"path": path, @"operation": @"fopen_read_only",
            @"result": stream ? @"visible" : SDPFilesystemResult(-1, errorNumber),
            @"errno": @(errorNumber)}];
    }
    return observations;
}

static NSDictionary *SDPSentinelWriteObservation(void) {
#if TARGET_OS_IPHONE
    const char *path = "/private/jailbreak.txt";
    errno = 0;
    int descriptor = open(path, O_WRONLY | O_CREAT | O_EXCL, 0600);
    int createError = descriptor >= 0 ? 0 : errno;
    if (descriptor < 0) {
        return @{@"path": @(path), @"operation": @"create_empty_o_excl_then_remove",
            @"create_result": SDPFilesystemResult(-1, createError), @"create_errno": @(createError),
            @"created_by_probe": @NO, @"cleanup_attempted": @NO,
            @"cleanup_result": @"not_applicable"};
    }
    int closeResult = close(descriptor);
    int closeError = closeResult == 0 ? 0 : errno;
    errno = 0;
    int removeResult = unlink(path);
    int removeError = removeResult == 0 ? 0 : errno;
    struct stat metadata = {0};
    errno = 0;
    int readbackResult = lstat(path, &metadata);
    int readbackError = readbackResult == 0 ? 0 : errno;
    NSString *cleanupResult = removeResult != 0 ? @"remove_failed" :
        (readbackResult != 0 && readbackError == ENOENT) ? @"removed_and_absent" :
        @"remove_succeeded_but_still_visible";
    return @{@"path": @(path), @"operation": @"create_empty_o_excl_then_remove",
        @"create_result": @"created", @"create_errno": @0, @"created_by_probe": @YES,
        @"cleanup_attempted": @YES,
        @"cleanup_result": cleanupResult, @"cleanup_errno": @(removeError),
        @"close_result": closeResult == 0 ? @"closed" : @"close_failed",
        @"close_errno": @(closeError),
        @"readback_result": SDPFilesystemResult(readbackResult, readbackError),
        @"readback_errno": @(readbackError)};
#else
    return @{@"path": @"/private/jailbreak.txt",
        @"operation": @"create_empty_o_excl_then_remove", @"create_result": @"not_run_on_host",
        @"create_errno": @0, @"created_by_probe": @NO, @"cleanup_attempted": @NO,
        @"cleanup_result": @"not_applicable"};
#endif
}

static NSDictionary *SDPWritableExecutableMappingObservation(void) {
#if TARGET_OS_IPHONE
    NSURL *documents = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory
                                                           inDomains:NSUserDomainMask].firstObject;
    if (!documents) {
        return @{@"operation": @"own_documents_file_mmap_write_exec_shared",
            @"status": @"documents_unavailable", @"created_by_probe": @NO,
            @"cleanup_attempted": @NO};
    }
    NSURL *temporary = [documents URLByAppendingPathComponent:@"sdp-wx-map-probe.tmp"];
    const char *path = temporary.fileSystemRepresentation;
    errno = 0;
    int descriptor = open(path, O_RDWR | O_CREAT | O_EXCL, 0600);
    int createError = descriptor >= 0 ? 0 : errno;
    if (descriptor < 0) {
        return @{@"operation": @"own_documents_file_mmap_write_exec_shared",
            @"status": @"create_failed", @"create_errno": @(createError),
            @"created_by_probe": @NO, @"cleanup_attempted": @NO};
    }

    const char payload[] = "com.alipay";
    ssize_t bytesWritten = write(descriptor, payload, sizeof(payload) - 1);
    int writeError = bytesWritten == (ssize_t)(sizeof(payload) - 1) ? 0 : errno;
    errno = 0;
    void *mapping = bytesWritten == (ssize_t)(sizeof(payload) - 1) ?
        mmap(NULL, sizeof(payload) - 1, PROT_WRITE | PROT_EXEC, MAP_SHARED, descriptor, 0) :
        MAP_FAILED;
    int mappingError = mapping == MAP_FAILED ? errno : 0;
    int unmapResult = mapping == MAP_FAILED ? 0 : munmap(mapping, sizeof(payload) - 1);
    int unmapError = unmapResult == 0 ? 0 : errno;
    int closeResult = close(descriptor);
    int closeError = closeResult == 0 ? 0 : errno;
    errno = 0;
    int removeResult = unlink(path);
    int removeError = removeResult == 0 ? 0 : errno;
    struct stat metadata = {0};
    errno = 0;
    int readbackResult = lstat(path, &metadata);
    int readbackError = readbackResult == 0 ? 0 : errno;
    NSString *cleanupResult = removeResult != 0 ? @"remove_failed" :
        (readbackResult != 0 && readbackError == ENOENT) ? @"removed_and_absent" :
        @"remove_succeeded_but_still_visible";
    return @{@"operation": @"own_documents_file_mmap_write_exec_shared",
        @"status": @"observed", @"created_by_probe": @YES,
        @"write_result": bytesWritten == (ssize_t)(sizeof(payload) - 1) ? @"written" : @"write_failed",
        @"write_errno": @(writeError),
        @"mapping_result": mapping == MAP_FAILED ? @"denied_or_failed" : @"mapped_write_exec",
        @"mapping_errno": @(mappingError),
        @"unmap_result": unmapResult == 0 ? @"unmapped_or_not_mapped" : @"unmap_failed",
        @"unmap_errno": @(unmapError),
        @"close_result": closeResult == 0 ? @"closed" : @"close_failed",
        @"close_errno": @(closeError), @"cleanup_attempted": @YES,
        @"cleanup_result": cleanupResult, @"cleanup_errno": @(removeError),
        @"readback_result": SDPFilesystemResult(readbackResult, readbackError),
        @"readback_errno": @(readbackError)};
#else
    return @{@"operation": @"own_documents_file_mmap_write_exec_shared",
        @"status": @"not_run_on_host", @"created_by_probe": @NO,
        @"cleanup_attempted": @NO, @"mapping_result": @"not_run_on_host"};
#endif
}

static NSArray *SDPURLSchemeObservations(void) {
    NSArray<NSString *> *schemes = @[@"cydia", @"sileo", @"zbra"];
    NSMutableArray *observations = [NSMutableArray array];
#if TARGET_OS_IPHONE && !defined(SDP_APP_EXTENSION)
    void (^querySchemes)(void) = ^{
        for (NSString *scheme in schemes) {
            NSURL *url = [NSURL URLWithString:[scheme stringByAppendingString:@"://"]];
            BOOL visible = url && [UIApplication.sharedApplication canOpenURL:url];
            [observations addObject:@{@"scheme": scheme, @"operation": @"can_open_url",
                @"result": visible ? @"visible" : @"not_visible"}];
        }
    };
    if (NSThread.isMainThread) {
        querySchemes();
    } else {
        dispatch_sync(dispatch_get_main_queue(), querySchemes);
    }
#else
    NSString *result = TARGET_OS_IPHONE ? @"unavailable_in_app_extension" : @"not_run_on_host";
    for (NSString *scheme in schemes) {
        [observations addObject:@{@"scheme": scheme, @"operation": @"can_open_url",
            @"result": result}];
    }
#endif
    return observations;
}

static NSDictionary *SDPProcessMarkerObservation(void) {
    NSDictionary<NSString *, NSString *> *markers = @{
        @"sshd": @"sshd", @"dropbear": @"dropbear", @"frida-server": @"frida-server",
        @"frida": @"frida", @"sileo": @"Sileo", @"zebra": @"Zebra",
        @"dopamine": @"Dopamine", @"roothide": @"RootHide", @"apt": @"apt",
        @"dpkg": @"dpkg"
    };
    int query[] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
    size_t byteCount = 0;
    errno = 0;
    if (sysctl(query, 4, NULL, &byteCount, NULL, 0) != 0) {
        return @{@"operation": @"sysctl_kern_proc_all", @"status": @"size_query_failed",
            @"errno": @(errno), @"matched_markers": @[]};
    }
    struct kinfo_proc *processes = NULL;
    int queryResult = -1;
    int queryError = 0;
    for (NSUInteger attempt = 0; attempt < 3; attempt++) {
        size_t capacity = byteCount + (byteCount / 8) + sizeof(struct kinfo_proc) * 8;
        struct kinfo_proc *resized = realloc(processes, capacity);
        if (!resized) {
            free(processes);
            return @{@"operation": @"sysctl_kern_proc_all", @"status": @"allocation_failed",
                @"errno": @ENOMEM, @"matched_markers": @[]};
        }
        processes = resized;
        byteCount = capacity;
        errno = 0;
        queryResult = sysctl(query, 4, processes, &byteCount, NULL, 0);
        queryError = queryResult == 0 ? 0 : errno;
        if (queryResult == 0 || queryError != ENOMEM) {
            break;
        }
    }
    if (queryResult != 0) {
        free(processes);
        return @{@"operation": @"sysctl_kern_proc_all", @"status": @"query_failed",
            @"errno": @(queryError), @"matched_markers": @[]};
    }
    NSMutableSet<NSString *> *matches = [NSMutableSet set];
    size_t processCount = byteCount / sizeof(struct kinfo_proc);
    for (size_t index = 0; index < processCount; index++) {
        NSString *rawName = [NSString stringWithUTF8String:processes[index].kp_proc.p_comm];
        if (!rawName) {
            continue;
        }
        NSString *name = rawName.lowercaseString;
        NSString *reportedName = markers[name];
        if (reportedName) {
            [matches addObject:reportedName];
        }
    }
    free(processes);
    NSArray *sortedMatches = [matches.allObjects sortedArrayUsingSelector:@selector(compare:)];
    return @{@"operation": @"sysctl_kern_proc_all", @"status": @"observed", @"errno": @0,
        @"matched_markers": sortedMatches};
}

static NSArray *SDPFunctionOrigins(void) {
    NSMutableArray *origins = [NSMutableArray array];
    for (NSString *name in @[@"stat", @"access", @"fopen", @"sysctl", @"dlopen", @"csops"]) {
        void *symbol = dlsym(RTLD_DEFAULT, name.UTF8String);
        Dl_info information = {0};
        if (symbol && dladdr(symbol, &information)) {
            NSMutableDictionary *origin = [@{@"symbol": name, @"status": @"observed",
                @"image": SDPImageDescription(information.dli_fname)} mutableCopy];
            if ([name isEqualToString:@"stat"]) {
                NSString *imagePath = information.dli_fname ? @(information.dli_fname) : @"";
                NSString *expectedPath = @"/usr/lib/system/libsystem_kernel.dylib";
                origin[@"expected_image"] = expectedPath;
                origin[@"matches_expected_image"] = @([imagePath isEqualToString:expectedPath]);
            }
            [origins addObject:origin];
        } else {
            [origins addObject:@{@"symbol": name, @"status": @"unavailable"}];
        }
    }
    return origins;
}

static NSArray *SDPLoopbackPortObservations(void) {
    NSArray<NSNumber *> *ports = @[@22, @2222, @44, @27042];
    NSMutableArray *observations = [NSMutableArray array];
    for (NSNumber *portValue in ports) {
        int socketDescriptor = socket(AF_INET, SOCK_STREAM, 0);
        int errorNumber = socketDescriptor < 0 ? errno : 0;
        NSString *result = socketDescriptor < 0 ? @"socket_error" : @"error";
        if (socketDescriptor >= 0) {
            int flags = fcntl(socketDescriptor, F_GETFL, 0);
            if (flags >= 0 && fcntl(socketDescriptor, F_SETFL, flags | O_NONBLOCK) == 0) {
                struct sockaddr_in address = {0};
                address.sin_len = sizeof(address);
                address.sin_family = AF_INET;
                address.sin_port = htons(portValue.unsignedShortValue);
                address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
                errno = 0;
                int connectResult = connect(socketDescriptor, (const struct sockaddr *)&address, sizeof(address));
                if (connectResult == 0) {
                    result = @"reachable";
                    errorNumber = 0;
                } else if (errno == EINPROGRESS) {
                    struct pollfd descriptor = {.fd = socketDescriptor, .events = POLLOUT};
                    int pollResult = poll(&descriptor, 1, 250);
                    if (pollResult > 0) {
                        socklen_t optionLength = sizeof(errorNumber);
                        if (getsockopt(socketDescriptor, SOL_SOCKET, SO_ERROR, &errorNumber, &optionLength) != 0) {
                            errorNumber = errno;
                        }
                        result = errorNumber == 0 ? @"reachable" :
                            errorNumber == ECONNREFUSED ? @"refused" : @"error";
                    } else if (pollResult == 0) {
                        result = @"timeout";
                        errorNumber = ETIMEDOUT;
                    } else {
                        result = @"poll_error";
                        errorNumber = errno;
                    }
                } else {
                    errorNumber = errno;
                    result = errorNumber == ECONNREFUSED ? @"refused" : @"error";
                }
            } else {
                result = @"fcntl_error";
                errorNumber = errno;
            }
            close(socketDescriptor);
        }
        [observations addObject:@{@"address": @"127.0.0.1", @"port": portValue,
            @"operation": @"tcp_connect_no_payload", @"result": result, @"errno": @(errorNumber)}];
    }
    return observations;
}

NSDictionary<NSString *, id> *SDPCollectReport(NSString *component) {
    NSArray *images = SDPLoadedImages();
    NSDictionary *environment = SDPEnvironmentPresence();
    NSDictionary *environmentContentMarkers = SDPEnvironmentContentMarkerPresence();
    NSDictionary *signing = SDPCodeSigningState();
    NSDictionary *entitlements = SDPEntitlementState();
    NSArray *pathObservations = SDPPathObservations();
    NSDictionary *sentinelWrite = SDPSentinelWriteObservation();
    NSDictionary *writableExecutableMapping = SDPWritableExecutableMappingObservation();
    NSArray *schemeObservations = SDPURLSchemeObservations();
    NSDictionary *processMarkers = SDPProcessMarkerObservation();
    NSMutableArray *findings = [NSMutableArray array];
    for (NSDictionary *image in images) {
        if ([image[@"known_jailbreak_marker"] boolValue]) {
            [findings addObject:@{@"kind": @"loaded_image_marker", @"name": image[@"name"]}];
        }
    }
    for (NSString *key in environment) {
        if ([environment[key] boolValue]) {
            [findings addObject:@{@"kind": @"environment_variable_present", @"name": key}];
        }
    }
    for (NSString *marker in environmentContentMarkers) {
        if ([environmentContentMarkers[marker] boolValue]) {
            [findings addObject:@{@"kind": @"environment_content_marker_present", @"name": marker}];
        }
    }
    if (geteuid() == 0 || getuid() == 0) {
        [findings addObject:@{@"kind": @"root_identity"}];
    }
    for (NSString *key in @[@"platform_binary", @"debugged", @"get_task_allow"]) {
        if ([signing[key] boolValue]) {
            [findings addObject:@{@"kind": @"non_store_baseline_signing_flag", @"name": key}];
        }
    }
    for (NSString *key in entitlements[@"values"]) {
        if ([entitlements[@"values"][key][@"enabled"] boolValue]) {
            [findings addObject:@{@"kind": @"privileged_or_debug_entitlement", @"name": key}];
        }
    }
    for (NSDictionary *observation in pathObservations) {
        if ([observation[@"result"] isEqual:@"visible"]) {
            [findings addObject:@{@"kind": @"jailbreak_path_visible",
                @"name": observation[@"path"], @"operation": observation[@"operation"]}];
        }
    }
    for (NSDictionary *observation in schemeObservations) {
        if ([observation[@"result"] isEqual:@"visible"]) {
            [findings addObject:@{@"kind": @"jailbreak_url_scheme_visible",
                @"name": observation[@"scheme"]}];
        }
    }
    for (NSString *name in processMarkers[@"matched_markers"]) {
        [findings addObject:@{@"kind": @"jailbreak_process_marker_visible", @"name": name}];
    }
    if ([sentinelWrite[@"created_by_probe"] boolValue]) {
        [findings addObject:@{@"kind": @"sandbox_escape_write_succeeded",
            @"cleanup_result": sentinelWrite[@"cleanup_result"]}];
    }
    if ([writableExecutableMapping[@"mapping_result"] isEqualToString:@"mapped_write_exec"]) {
        [findings addObject:@{@"kind": @"writable_executable_file_mapping_succeeded"}];
    }
    struct utsname system = {0};
    uname(&system);
    NSISO8601DateFormatter *formatter = [NSISO8601DateFormatter new];
    return @{@"schema_version": @1, @"probe_version": @"0.1.6", @"component": component,
        @"collected_at": [formatter stringFromDate:NSDate.date],
        @"platform": TARGET_OS_IPHONE ? @"ios" : @"macos_host_validation_only",
        @"model": @(system.machine), @"os_version": NSProcessInfo.processInfo.operatingSystemVersionString,
        @"bundle_id": NSBundle.mainBundle.bundleIdentifier ?: @"host_validation",
        @"identity": @{@"uid": @(getuid()), @"effective_uid": @(geteuid())},
        @"installation_provenance": @"not_attested_by_runtime_probe",
        @"build_evidence_scope": @"non_app_store_diagnostic_only",
        @"loaded_images": images, @"environment_presence": environment,
        @"environment_content_marker_presence": environmentContentMarkers,
        @"code_signing": signing, @"entitlements": entitlements,
        @"path_observations": pathObservations, @"sentinel_write_observation": sentinelWrite,
        @"writable_executable_mapping_observation": writableExecutableMapping,
        @"url_scheme_observations": schemeObservations,
        @"process_marker_observation": processMarkers,
        @"function_origins": SDPFunctionOrigins(),
        @"loopback_port_observations": SDPLoopbackPortObservations(),
        @"findings": findings,
        @"assessment": @{@"known_process_markers": [processMarkers[@"matched_markers"] count] ? @"observed" : @"not_observed",
            @"ordinary_ios_sandbox": @"not_proven",
            @"isolated_filesystem_and_services": @"not_proven",
            @"clean_ios_environment": @"not_proven"},
        @"limits": @[@"Absence of known markers is not proof of no hooks or no jailbreak.",
            @"System-looking library paths are not signature or integrity attestations.",
            @"Environment content scanning reports only two fixed MobileSubstrate marker booleans and never records environment entries or values.",
            @"Write probes only use exclusive files created by this probe: /private/jailbreak.txt and one temporary file in this app's own Documents; both are removed and read back when created.",
            @"Process enumeration reports only matches from a fixed marker allowlist, never the full process list.",
            @"URL-scheme visibility is queried only for cydia, sileo and zbra; the extension does not call UIApplication.",
            @"Loopback checks only attempt TCP connections to fixed 127.0.0.1 ports and send no payload.",
            @"The host validation result is not iPhone runtime evidence.",
            @"No account, Keychain, external app container or incoming share content is read."]};
}

NSURL *SDPSaveReport(NSDictionary<NSString *, id> *report, NSError **error) {
    NSURL *documents = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory
                                                           inDomains:NSUserDomainMask].firstObject;
    NSURL *directory = [documents URLByAppendingPathComponent:@"SafeDomainReports" isDirectory:YES];
    if (![NSFileManager.defaultManager createDirectoryAtURL:directory
                               withIntermediateDirectories:YES attributes:nil error:error]) {
        return nil;
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:report
                                                  options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                                    error:error];
    if (!data) {
        return nil;
    }
    NSString *name = [NSString stringWithFormat:@"%@-%@.json", report[@"component"], NSUUID.UUID.UUIDString];
    NSURL *destination = [directory URLByAppendingPathComponent:name];
    return [data writeToURL:destination options:NSDataWritingAtomic error:error] ? destination : nil;
}
