#import <Foundation/Foundation.h>
#import <sys/socket.h>
#import <sys/un.h>
#import <unistd.h>
#import <notify.h>
#import <fcntl.h>
#import <sys/stat.h>

// Test-only adapter protocol. The three Apps are NOT added to the shipping menu.
static NSString *const ProbeBundles[] = {
    @"co.hotspot.vpn.security", @"com.bestapp.gofast.vpn", @"com.zenith.jump"
};
typedef struct { uint32_t magic, action; } AdapterProbeCommand;
typedef struct { uint32_t magic, token[8]; uint64_t expires; } AdapterProbePermit;
static const uint32_t AdapterProbeMagic = 0x41505431;
static const char *const AdapterProbeSocket = "vpa1.sock";
extern int proc_pidpath(int pid, void *buffer, uint32_t size);
extern int csops_audittoken(pid_t pid, unsigned int operation, void *address, size_t size, void *token);
static inline void ProbeStage(uint64_t value) {
    static int diagnosticToken = NOTIFY_TOKEN_INVALID;
    NSString *name = [NSString stringWithFormat:@"ayao.vpnadapter.%@.stage", NSBundle.mainBundle.bundleIdentifier];
    if (diagnosticToken == NOTIFY_TOKEN_INVALID && notify_register_check(name.UTF8String, &diagnosticToken)) return;
    notify_set_state(diagnosticToken, value);
}

static inline BOOL ProbePeer(int descriptor, NSString *expectedExecutable) {
    uid_t uid; gid_t gid;
    uint32_t token[8] = {0}; socklen_t length = sizeof(token);
    if (getpeereid(descriptor, &uid, &gid) || uid != 501) { ProbeStage(301); return NO; }
    if (getsockopt(descriptor, SOL_LOCAL, LOCAL_PEERTOKEN, token, &length) ||
        length != sizeof(token) || !token[5]) { ProbeStage(302); return NO; }
#ifdef ADAPTER_HELPER_BUILD
    NSString *path=[NSTemporaryDirectory() stringByAppendingPathComponent:@"vpa1.permit"];
    int file=open(path.fileSystemRepresentation,O_RDONLY|O_NOFOLLOW);
    if(file<0){ProbeStage(305);return NO;}
    struct stat st;AdapterProbePermit permit;
    BOOL valid=!fstat(file,&st)&&S_ISREG(st.st_mode)&&st.st_uid==0&&(st.st_mode&022)==0&&
        read(file,&permit,sizeof(permit))==sizeof(permit);close(file);
    uint64_t now=(uint64_t)(NSDate.date.timeIntervalSince1970*1000);
    if(!valid||permit.magic!=AdapterProbeMagic||permit.expires<now||permit.expires>now+45000||
        memcmp(permit.token,token,sizeof(token))){ProbeStage(306);return NO;}
    (void)expectedExecutable;
    return YES;
#else
    char path[4096] = {0};
    if (proc_pidpath((int)token[5], path, sizeof(path)) <= 0) { ProbeStage(303); return NO; }
    NSString *actual = @((const char *)path);
    BOOL accepted = [actual isEqualToString:expectedExecutable] ||
        ([actual hasPrefix:@"/private/var/mobile/Containers/Shared/AppGroup/.jbroot-"] &&
         [actual hasSuffix:expectedExecutable]);
    if (!accepted) ProbeStage(304);
    return accepted;
#endif
}
