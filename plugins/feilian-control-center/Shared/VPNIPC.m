#import "VPNIPC.h"
#import <sys/socket.h>
#import <sys/un.h>
#import <sys/stat.h>
#import <unistd.h>
#import <fcntl.h>
#import <errno.h>
#import <stdatomic.h>
#import <notify.h>
#import <dlfcn.h>
#import <objc/runtime.h>

extern int proc_pidpath(int pid, void *buffer, uint32_t size);
@interface NSObject (VPNApplicationRegistry)
+ (id)applicationProxyForIdentifier:(NSString *)identifier;
- (NSURL *)dataContainerURL;
- (instancetype)initWithPID:(int)pid flags:(unsigned)flags reason:(unsigned)reason name:(NSString *)name withHandler:(id)handler;
- (void)invalidate;
@end
NSString *VPNBundle(NSString *provider) {
    return @{@"easy":@"com.qdtiktok.easyvpn", @"feilian":@"com.volcengine.corplink",
             @"hotspot":@"co.hotspot.vpn.security", @"gofast":@"com.bestapp.gofast.vpn",
             @"jump":@"com.zenith.jump"}[provider ?: @""];
}
NSArray<NSString *> *VPNProviders(void) { return @[@"easy",@"feilian",@"hotspot",@"gofast",@"jump"]; }
BOOL VPNUsesNativeStop(NSString *provider) { return [VPNProviders() containsObject:provider]; }
NSTimeInterval VPNTimeout(NSString *provider) { return [provider isEqual:@"gofast"] ? 75 : 45; }
void VPNIPCRecordStage(NSString *provider, uint64_t stage) {
    NSString *name = [NSString stringWithFormat:@"ayao.vpn.%@.diagnostic-stage.v1", provider];
    // One process-lifetime registration, otherwise the last cancel discards state.
    static NSMutableDictionary *tokens;
    static dispatch_once_t once;dispatch_once(&once,^{tokens=[NSMutableDictionary dictionary];});
    int token;
    @synchronized(tokens) {
        NSNumber *saved=tokens[provider];
        if(saved)token=saved.intValue;
        else {if(notify_register_check(name.UTF8String,&token)!=NOTIFY_STATUS_OK)return;tokens[provider]=@(token);}
    }
    notify_set_state(token, stage);
}

typedef struct {
    uint32_t magic, version, action, code;
    uint64_t generation, deadline;
} VPNMessage;
static const uint32_t Magic = 0x56504e31;
NSString *VPNIPCSocketPath(NSString *provider) {
    NSString *bundle = VPNBundle(provider); if (!bundle) return nil;
#if defined(VPN_IPC_HOST_TEST)
    // Host-only fixture path: no device/App registry access or production bypass.
    return [NSString stringWithFormat:@"/tmp/vpn-v2-test-%d.sock", getpid()];
#endif
    NSString *temporary = nil;
    if ([NSBundle.mainBundle.bundleIdentifier isEqual:bundle]) temporary = NSTemporaryDirectory();
    else {
        Class proxyClass = NSClassFromString(@"LSApplicationProxy");
        if (![proxyClass respondsToSelector:@selector(applicationProxyForIdentifier:)]) return nil;
        id proxy = [proxyClass applicationProxyForIdentifier:bundle];
        if (![proxy respondsToSelector:@selector(dataContainerURL)]) return nil;
        NSURL *url = [proxy dataContainerURL];
        if (![url isKindOfClass:NSURL.class] || !url.isFileURL) return nil;
        temporary = [url.path stringByAppendingPathComponent:@"tmp"];
    }
    if ([temporary hasPrefix:@"/private/var/"]) temporary = [temporary substringFromIndex:8];
    // New path/version prevents an old loaded module from speaking the old
    // challenge protocol to a new helper during an incomplete installation.
    return [temporary stringByAppendingPathComponent:@"vcc2.sock"];
}
static BOOL TargetPeer(int fd, NSString *provider) {
    uint64_t base=400;
    NSString *diagnostic=provider;
    uid_t uid; gid_t gid;
    if (getpeereid(fd, &uid, &gid) || uid != 501) {VPNIPCRecordStage(diagnostic,base+1);return NO;}
    // The kernel's peer audit token binds the identity to this socket connection.
    uint32_t token[8] = {0}; socklen_t length = sizeof(token);
    if (getsockopt(fd, SOL_LOCAL, LOCAL_PEERTOKEN, token, &length) || length != sizeof(token) || !token[5]) {VPNIPCRecordStage(diagnostic,base+2);return NO;}
    pid_t pid = 0; length = sizeof(pid);
    if (getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &pid, &length) || pid != (pid_t)token[5]) {VPNIPCRecordStage(diagnostic,base+3);return NO;}
    char path[4096] = {0};
    if (proc_pidpath(pid, path, sizeof(path)) <= 0) {
        VPNIPCRecordStage(diagnostic,base+100+(uint64_t)errno);
        return NO;
    }
    NSString *observed = @(path);
    // A suffix alone is not identity: check the peer's actual App metadata.
    NSString *bundlePath = observed.stringByDeletingLastPathComponent;
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[bundlePath stringByAppendingPathComponent:@"Info.plist"]];
    BOOL valid=([observed hasPrefix:@"/private/var/containers/Bundle/Application/"] ||
            [observed hasPrefix:@"/var/containers/Bundle/Application/"]) &&
        [info[@"CFBundleIdentifier"] isEqualToString:VPNBundle(provider)] &&
        [observed.lastPathComponent isEqualToString:info[@"CFBundleExecutable"]];
    VPNIPCRecordStage(diagnostic,valid?410:404);return valid;
}
static BOOL WriteMessage(int fd, VPNMessage message) {
    const uint8_t *bytes = (void *)&message; size_t offset = 0;
    while (offset < sizeof(message)) {
        ssize_t count = send(fd, bytes + offset, sizeof(message) - offset, 0);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) return NO;
        offset += (size_t)count;
    }
    return YES;
}
static void Configure(int fd) {
    int yes = 1; setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes));
    fcntl(fd, F_SETFD, FD_CLOEXEC);
    struct timeval timeout = { .tv_sec = 2 };
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
}

@implementation VPNIPCClient {
    NSString *_provider;
    int _fd, _openingFD;
    atomic_bool _closed;
    atomic_uint_fast64_t _lifecycle;
    id _executionAssertion;
}
- (void)releaseExecutionAssertion {
    id assertion;
    @synchronized(self) {
        assertion=_executionAssertion;
        _executionAssertion=nil;
    }
    if(!assertion)return;
    // BKSAssertion observer bookkeeping must not be mutated by simultaneous
    // timeout/IPC close paths. Detach once and invalidate on the host main queue.
    dispatch_async(dispatch_get_main_queue(),^{[assertion invalidate];});
}
- (instancetype)initWithProvider:(NSString *)provider {
    if ((self = [super init])) { _provider = [provider copy]; _fd = _openingFD = -1; atomic_init(&_closed, true);atomic_init(&_lifecycle,0); }
    return self;
}
- (BOOL)failOpen:(int)fd {
    @synchronized(self){if(_openingFD==fd)_openingFD=-1;}
    [self releaseExecutionAssertion];
    close(fd);
    return NO;
}
- (BOOL)open {
    [self close];
    uint64_t lifecycle=atomic_load(&_lifecycle);
    if (_fd >= 0) { close(_fd); _fd = -1; }
    NSString *path = VPNIPCSocketPath(_provider);
    struct stat st;
    if (!path || lstat(path.fileSystemRepresentation, &st) || !S_ISSOCK(st.st_mode) || st.st_uid != 501 || (st.st_mode & 077) != 0) return NO;
    int fd = socket(AF_UNIX, SOCK_STREAM, 0); if (fd < 0) return NO;
    Configure(fd);
    @synchronized(self) {
        if(atomic_load(&_lifecycle)!=lifecycle){close(fd);return NO;}
        _openingFD=fd;
    }
    struct timeval handshakeTimeout={.tv_sec=20};
    setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&handshakeTimeout,sizeof(handshakeTimeout));
    struct sockaddr_un address = { .sun_family = AF_UNIX };
    if (strlen(path.fileSystemRepresentation) >= sizeof(address.sun_path)) return [self failOpen:fd];
    strlcpy(address.sun_path, path.fileSystemRepresentation, sizeof(address.sun_path));
    address.sun_len = sizeof(address);
    // Client-side target verification prevents sending a VPN request or process
    // assertion to the wrong App. It is not a restriction on who may call us.
    if (connect(fd, (void *)&address, sizeof(address)) || !TargetPeer(fd, _provider)) return [self failOpen:fd];
    if(atomic_load(&_lifecycle)!=lifecycle)return [self failOpen:fd];
    if([NSBundle.mainBundle.bundleIdentifier isEqual:@"com.apple.springboard"]) {
        pid_t pid=0;socklen_t size=sizeof(pid);
        dlopen("/System/Library/PrivateFrameworks/AssertionServices.framework/AssertionServices",RTLD_NOW);
        // Use the verified system class/reason. Unsupported subclass/reason
        // combinations can return nil; never install callbacks on a nil object.
        Class assertion=NSClassFromString(@"BKSProcessAssertion");
        NSString *executionProvider=_provider;
        if(!getsockopt(fd,SOL_LOCAL,LOCAL_PEERPID,&pid,&size) && pid>0 && assertion) {
            __block id acquired;
            void (^acquire)(void)=^{
                if(atomic_load(&self->_lifecycle)!=lifecycle)return;
                acquired=[[assertion alloc] initWithPID:pid flags:1 reason:4
                name:@"VPNCC.finite-background-request" withHandler:^(BOOL valid){
                    VPNIPCRecordStage([executionProvider stringByAppendingString:@".execution"],valid?910:911);
                }];
                __weak typeof(self) weakSelf=self;
                if(!acquired){VPNIPCRecordStage([executionProvider stringByAppendingString:@".execution"],912);return;}
                __weak id current=acquired;
                // Release proactively, well before the system's shared legacy
                // FinishTask expiry. Over-budget requests fail closed rather
                // than keeping a stale assertion that gets the App terminated.
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,15*NSEC_PER_SEC),
                    dispatch_get_main_queue(),^{
                        typeof(self) strong=weakSelf;
                        if(!strong)return;
                        BOOL owns=NO;@synchronized(strong){owns=current && strong->_executionAssertion==current && atomic_load(&strong->_lifecycle)==lifecycle;}
                        if(owns){VPNIPCRecordStage([executionProvider stringByAppendingString:@".execution"],913);[strong close];}
                    });
            };
            if(NSThread.isMainThread)acquire();else dispatch_sync(dispatch_get_main_queue(),acquire);
            if(!acquired)return [self failOpen:fd];
            BOOL canceled=NO;
            @synchronized(self){
                canceled=atomic_load(&_lifecycle)!=lifecycle;
                if(!canceled)_executionAssertion=acquired;
            }
            if(canceled){dispatch_async(dispatch_get_main_queue(),^{[acquired invalidate];});return [self failOpen:fd];}
        } else return [self failOpen:fd];
    }
    if(atomic_load(&_lifecycle)!=lifecycle)return [self failOpen:fd];
    BOOL canceled=NO;
    @synchronized(self){
        canceled=atomic_load(&_lifecycle)!=lifecycle;
        if(!canceled){_openingFD=-1;_fd=fd;atomic_store(&_closed,false);}
    }
    if(canceled)return [self failOpen:fd];
    return YES;
}
- (NSInteger)exchange:(uint32_t)action generation:(uint64_t)generation {
    if (_fd < 0 || atomic_load(&_closed)) return VPNReplyUnavailable;
    struct timeval timeout = { .tv_sec = (long)(VPNTimeout(_provider) + 2) };
    setsockopt(_fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    VPNMessage message = { Magic, 2, action, 0, generation,
        (uint64_t)((NSDate.date.timeIntervalSince1970 + VPNTimeout(_provider)) * 1000) };
    if (!WriteMessage(_fd, message)) return VPNReplyUnavailable;
    VPNMessage reply; size_t offset = 0;
    while (offset < sizeof(reply)) {
        ssize_t count = recv(_fd, (uint8_t *)&reply + offset, sizeof(reply) - offset, 0);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) return VPNReplyTimeout;
        offset += (size_t)count;
    }
    return reply.magic == Magic && reply.version == 2 && reply.action == action && reply.generation == generation && reply.code <= VPNReplyUnauthorized ? reply.code : VPNReplyFailed;
}
- (BOOL)probe { return [self exchange:0 generation:0] == VPNReplyReady; }
- (NSInteger)requestConnect:(BOOL)connect generation:(uint64_t)generation {
    return [self exchange:connect ? 1 : 2 generation:generation];
}
- (void)close {
    // Cancellation interrupts blocking I/O but does not reuse the descriptor.
    // The owning IPC queue releases it after the in-flight exchange returns.
    @synchronized(self){
        atomic_fetch_add(&_lifecycle,1);
        // The opening worker owns closing this descriptor; cancellation only
        // wakes its in-flight reads. Never close/reuse another queue's fd.
        if(_openingFD>=0)shutdown(_openingFD,SHUT_RDWR);
        if (!atomic_exchange(&_closed, true) && _fd >= 0) shutdown(_fd, SHUT_RDWR);
    }
    [self releaseExecutionAssertion];
}
- (void)dealloc { [self close]; if (_fd >= 0) close(_fd); }
@end

@implementation VPNIPCServer {
    NSString *_provider, *_path;
    VPNIPCCommand _command;
    void (^_cancel)(uint64_t);
    dispatch_source_t _listener, _reader, _timeout;
    int _listenFD, _peerFD;
    NSMutableData *_input;
    uint64_t _generation, _lastGeneration, _nextOperation;
    BOOL _pending;
    BOOL _ownsPath;
    uint64_t _peerEpoch;
    uint64_t _deadlineEpoch;
}
- (instancetype)initWithProvider:(NSString *)provider command:(VPNIPCCommand)command cancel:(void (^)(uint64_t))cancel {
    if (!(self = [super init])) return nil;
    _listenFD = _peerFD = -1;
    _provider = provider; _path = VPNIPCSocketPath(provider); _command = [command copy]; _cancel = [cancel copy];
    if (![_provider length] || !_path) return nil;
#if !defined(VPN_IPC_HOST_TEST)
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:VPNBundle(provider)]) return nil;
#endif
    if (strlen(_path.fileSystemRepresentation) >= sizeof(((struct sockaddr_un *)0)->sun_path)) {
        VPNIPCRecordStage(provider, 1100); return nil;
    }
    struct stat st;
    if (!lstat(_path.fileSystemRepresentation, &st)) {
        if (!S_ISSOCK(st.st_mode) || st.st_uid != geteuid()) return nil;
        // Do not replace a live owner, even if it is another instance of this App.
        int probe=socket(AF_UNIX,SOCK_STREAM,0);
        if(probe<0)return nil;
        fcntl(probe,F_SETFL,O_NONBLOCK);
        struct sockaddr_un old={.sun_family=AF_UNIX,.sun_len=sizeof(old)};
        strlcpy(old.sun_path,_path.fileSystemRepresentation,sizeof(old.sun_path));
        int result=connect(probe,(void *)&old,sizeof(old));
        int error=errno;close(probe);
        if(result==0 || error!=ECONNREFUSED)return nil;
        struct stat current;
        if(lstat(_path.fileSystemRepresentation,&current) ||
           current.st_dev!=st.st_dev || current.st_ino!=st.st_ino)return nil;
        if (unlink(_path.fileSystemRepresentation)) return nil;
    }
    _listenFD = socket(AF_UNIX, SOCK_STREAM, 0); if (_listenFD < 0) return nil;
    Configure(_listenFD); fcntl(_listenFD, F_SETFL, O_NONBLOCK);
    struct sockaddr_un address = { .sun_family = AF_UNIX, .sun_len = sizeof(address) };
    strlcpy(address.sun_path, _path.fileSystemRepresentation, sizeof(address.sun_path));
    mode_t mask = umask(077);
    int bound = bind(_listenFD, (void *)&address, sizeof(address)); umask(mask);
    _ownsPath = bound == 0;
    if (bound || chmod(_path.fileSystemRepresentation, 0600) || listen(_listenFD, 1)) {
        VPNIPCRecordStage(provider, 1000 + (uint64_t)errno); return nil;
    }
    _listener = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, _listenFD, 0, dispatch_get_main_queue());
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(_listener, ^{ [weakSelf acceptPeer]; });
    dispatch_resume(_listener);
    VPNIPCRecordStage(provider, 200);
    return self;
}
- (void)endPeer {
    _peerEpoch++;
    _deadlineEpoch++;
    if (_pending && _cancel) _cancel(_generation);
    _pending = NO;
    if (_timeout) { dispatch_source_cancel(_timeout); _timeout = nil; }
    if (_reader) { dispatch_source_cancel(_reader); _reader = nil; }
    if (_peerFD >= 0) { shutdown(_peerFD, SHUT_RDWR); close(_peerFD); _peerFD = -1; }
    _input = nil;
    VPNIPCRecordStage([_provider stringByAppendingString:@".transport"],300);
}
- (void)armDeadline:(NSTimeInterval)remaining {
    uint64_t deadline=++_deadlineEpoch;
    if (_timeout) dispatch_source_cancel(_timeout);
    _timeout = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    __weak typeof(self) weakSelf = self;
    uint64_t epoch=_peerEpoch;
    dispatch_source_set_timer(_timeout, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(remaining * NSEC_PER_SEC)), DISPATCH_TIME_FOREVER, NSEC_PER_MSEC * 50);
    dispatch_source_set_event_handler(_timeout, ^{
        typeof(self) strong=weakSelf;
        if(strong && strong->_peerEpoch==epoch && strong->_deadlineEpoch==deadline)[strong endPeer];
    }); dispatch_resume(_timeout);
}
- (void)acceptPeer {
    int fd = accept(_listenFD, NULL, NULL); if (fd < 0) return;
    Configure(fd);
    if (_peerFD >= 0) { close(fd); return; }
    // Request numbering is connection-local. An open local caller must not
    // poison future clients by submitting an arbitrarily high generation.
    // Reset only after accepting a new peer, never on a refused second peer.
    _lastGeneration = 0;
    VPNIPCRecordStage([_provider stringByAppendingString:@".server"],330);
    // Deliberately no caller PID, identity, nonce, token or permit check. This
    // local App-owned socket accepts any caller able to reach it via its sandbox.
    VPNIPCRecordStage([_provider stringByAppendingString:@".server"],331);
    _peerEpoch++;
    fcntl(fd, F_SETFL, O_NONBLOCK); _peerFD = fd; _input = [NSMutableData data];
    _reader = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, fd, 0, dispatch_get_main_queue());
    __weak typeof(self) weakSelf = self;
    uint64_t epoch=_peerEpoch;
    dispatch_source_set_event_handler(_reader, ^{
        typeof(self) strong=weakSelf;
        if(strong && strong->_peerEpoch==epoch)[strong readPeer];
    }); dispatch_resume(_reader);
    [self armDeadline:5];
}
- (void)readPeer {
    uint8_t bytes[sizeof(VPNMessage)];
    ssize_t count = recv(_peerFD, bytes, sizeof(bytes), 0);
    if (count <= 0) { if (count == 0 || (errno != EAGAIN && errno != EINTR)) [self endPeer]; return; }
    [_input appendBytes:bytes length:(NSUInteger)count];
    if (_input.length < sizeof(VPNMessage)) return;
    if (_input.length != sizeof(VPNMessage) || _pending) { [self endPeer]; return; }
    VPNMessage message; memcpy(&message, _input.bytes, sizeof(message)); [_input setLength:0];
    VPNIPCRecordStage([_provider stringByAppendingString:@".transport"],400+message.action);
    NSTimeInterval remaining = (double)message.deadline / 1000 - NSDate.date.timeIntervalSince1970;
    if (message.magic != Magic || message.version != 2 || message.action > 2 || message.code != 0 || remaining <= 0 || remaining > VPNTimeout(_provider) + 1) { [self endPeer]; return; }
    if (message.action == 0) { message.code = VPNReplyReady; WriteMessage(_peerFD, message); return; }
    if (!message.generation || message.generation <= _lastGeneration) { [self endPeer]; return; }
    // Wire IDs are caller-local, but helper callbacks need a never-reused ID
    // across connections. Otherwise a canceled old helper retry can act on a
    // new client's operation carrying the same wire number.
    if (_nextOperation == UINT64_MAX) { [self endPeer]; return; }
    _lastGeneration = message.generation;
    _generation = ++_nextOperation;
    uint64_t operation = _generation;
    _pending = YES;
    [self armDeadline:remaining];
    __weak typeof(self) weakSelf = self;
    uint64_t epoch=_peerEpoch;
    _command(operation, message.action == 1, ^(NSInteger code) {
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf || strongSelf->_peerEpoch!=epoch || !strongSelf->_pending || strongSelf->_generation != operation) return;
            VPNMessage reply = message; reply.code = (uint32_t)code;
            strongSelf->_pending = NO;
            BOOL sent=WriteMessage(strongSelf->_peerFD, reply);
            VPNIPCRecordStage([strongSelf->_provider stringByAppendingString:@".transport"],sent?500+reply.code:600+(uint64_t)errno);
        });
    });
}
- (void)dealloc {
    if (_listener) dispatch_source_cancel(_listener);
    if (_reader) dispatch_source_cancel(_reader);
    if (_timeout) dispatch_source_cancel(_timeout);
    if (_peerFD >= 0) close(_peerFD);
    if (_listenFD >= 0) close(_listenFD);
    if (_ownsPath && _path) unlink(_path.fileSystemRepresentation);
}
@end
