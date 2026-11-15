#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <mach/mach.h>
#import <fcntl.h>
#import <sys/stat.h>
#import <poll.h>
#import "protocol.h"
#import "../../VPNPrivate.h"

@interface NSObject (NativeOnboardingSystem)
+ (id)applicationProxyForIdentifier:(NSString *)identifier;
- (NSURL *)dataContainerURL;
+ (id)sharedService;
- (void)openApplication:(NSString *)identifier options:(NSDictionary *)options withResult:(void (^)(NSError *))result;
@end
static BOOL ReadBytes(int fd, void *bytes, size_t size) {
    size_t offset=0;
    while(offset<size) {
        ssize_t n=recv(fd,(uint8_t *)bytes+offset,size-offset,0);
        if(n<=0)return NO;offset+=(size_t)n;
    }
    return YES;
}
static BOOL Permit(NSString *path) {
    audit_token_t token={0};mach_msg_type_number_t count=TASK_AUDIT_TOKEN_COUNT;
    if(task_info(mach_task_self(),TASK_AUDIT_TOKEN,(task_info_t)&token,&count)!=KERN_SUCCESS)return NO;
    NSMutableArray *values=[NSMutableArray array];for(unsigned i=0;i<8;i++)[values addObject:@(token.val[i])];
    printf("PERMIT_REQUEST=%s\n",[[[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:
        @{@"pid":@(getpid()),@"audit":values,@"permitPath":path} options:0 error:nil] encoding:NSUTF8StringEncoding] UTF8String]);
    fflush(stdout);
    // The tool does not need sandbox access to the App's permit file. Its
    // supervisor acknowledges publication over the existing SSH stdin pipe.
    struct pollfd input={.fd=STDIN_FILENO,.events=POLLIN};
    if(poll(&input,1,20000)<=0)return NO;
    char response[32]={0};
    return fgets(response,sizeof(response),stdin)&&!strcmp(response,"AUTHORIZED\n");
}
int main(int argc,const char *argv[]) {
    @autoreleasepool {
        if(argc!=3)return 2;
        NSString *bundle=@(argv[1]), *mode=@(argv[2]);
        if ([mode isEqual:@"identity"]) {
            char executable[4096]={0}; proc_pidpath(getpid(),executable,sizeof(executable));
            puts(executable); return 0;
        }
        if ([mode isEqual:@"stage"]) {
            int token; uint64_t value=0;
            NSString *name=[NSString stringWithFormat:@"ayao.vpnadapter.%@.stage",bundle];
            if(notify_register_check(name.UTF8String,&token)==NOTIFY_STATUS_OK){notify_get_state(token,&value);notify_cancel(token);}
            printf("stage=%llu\n",value); return 0;
        }
        if(![@[ProbeBundles[0],ProbeBundles[1],ProbeBundles[2]] containsObject:bundle] ||
           ![@[@"discover",@"connect",@"disconnect",@"close-onboarding",@"locations",@"fastest",@"status",@"cleanup"] containsObject:mode])return 2;
        id proxy=[NSClassFromString(@"LSApplicationProxy") applicationProxyForIdentifier:bundle];
        NSString *path=[[[proxy dataContainerURL] path] stringByAppendingPathComponent:@"tmp/vpa1.sock"];
        if([path hasPrefix:@"/private/var/"])path=[path substringFromIndex:8];
        if(!path || strlen(path.fileSystemRepresentation)>=sizeof(((struct sockaddr_un *)0)->sun_path))return 3;
        if([mode isEqual:@"cleanup"]){printf("socket_path=%s\n",path.fileSystemRepresentation);return 0;}
        dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices",RTLD_NOW);
        mach_port_t (*port)(void)=dlsym(RTLD_DEFAULT,"SBSSpringBoardServerPort");
        void (*lock)(mach_port_t,BOOL *,BOOL *)=dlsym(RTLD_DEFAULT,"SBGetScreenLockStatus");
        BOOL locked=YES,passcode=YES;
        if(!port || !lock || port()==MACH_PORT_NULL)return 4;
        lock(port(),&locked,&passcode);
        if(locked){puts("REFUSED_LOCKED=1");return 4;}
        if(![[NSBundle bundleWithPath:@"/System/Library/PreferenceBundles/VPNPreferences.bundle"] load])return 3;
        id store=[NSClassFromString(@"VPNConnectionStore") sharedInstance];
        for(NSUInteger grade=0;grade<4;grade++)[store vpnServicesForCurrentSetWithGrade:grade];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:4]];
        if(!Permit([path.stringByDeletingLastPathComponent stringByAppendingPathComponent:@"vpa1.permit"])){
            puts("PERMIT_TIMEOUT=1");return 5;
        }
        for(NSUInteger grade=0;grade<4;grade++)for(id identifier in [store vpnServicesForCurrentSetWithGrade:grade]){
            id connection=[store connectionWithServiceID:identifier withGrade:grade];
            if([mode isEqual:@"connect"] && [connection notDisconnectedOrDisconnecting]){
                puts("REFUSED_ACTIVE_VPN=1");return 4;
            }
            if([mode isEqual:@"disconnect"] && [connection notDisconnectedOrDisconnecting] &&
               ![[connection bundleID] isEqual:bundle]){puts("REFUSED_OTHER_ACTIVE=1");return 4;}
        }
        dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices",RTLD_NOW);
        id service=[NSClassFromString(@"FBSSystemService") sharedService];
        [service openApplication:bundle options:@{} withResult:^(NSError *error){printf("launch_error=%ld\n",(long)error.code);}];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:4]];
        int fd=socket(AF_UNIX,SOCK_STREAM,0);if(fd<0)return 3;
        int yes=1;setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&yes,sizeof(yes));
        struct timeval timeout={.tv_sec=28};setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
        setsockopt(fd,SOL_SOCKET,SO_SNDTIMEO,&timeout,sizeof(timeout));
        struct sockaddr_un address={.sun_family=AF_UNIX,.sun_len=sizeof(address)};
        strlcpy(address.sun_path,path.fileSystemRepresentation,sizeof(address.sun_path));
        if(connect(fd,(void *)&address,sizeof(address))){printf("socket_connect_errno=%d\n",errno);close(fd);return 5;}
        uid_t peerUID=0;gid_t peerGID=0;
        uint32_t token[8]={0};socklen_t tokenLength=sizeof(token);
        char executable[4096]={0};
        if(getpeereid(fd,&peerUID,&peerGID) || peerUID!=501 ||
           getsockopt(fd,SOL_LOCAL,LOCAL_PEERTOKEN,token,&tokenLength) || tokenLength!=sizeof(token) ||
           proc_pidpath((int)token[5],executable,sizeof(executable))<=0){puts("PEER_IDENTITY_UNAVAILABLE=1");close(fd);return 5;}
        NSString *appPath=@((const char *)executable);
        NSDictionary *metadata=[NSDictionary dictionaryWithContentsOfFile:[appPath.stringByDeletingLastPathComponent stringByAppendingPathComponent:@"Info.plist"]];
        if(![metadata[@"CFBundleIdentifier"] isEqual:bundle] ||
           ![metadata[@"CFBundleExecutable"] isEqual:appPath.lastPathComponent]){
            printf("PEER_METADATA_PRESENT=%d BUNDLE_MATCH=%d EXECUTABLE_MATCH=%d\n",metadata!=nil,
                [metadata[@"CFBundleIdentifier"] isEqual:bundle],[metadata[@"CFBundleExecutable"] isEqual:appPath.lastPathComponent]);
            close(fd);return 5;
        }
        uint32_t action=[mode isEqual:@"discover"]?0:([mode isEqual:@"connect"]?1:([mode isEqual:@"disconnect"]?3:([mode isEqual:@"close-onboarding"]?4:([mode isEqual:@"locations"]?5:([mode isEqual:@"fastest"]?6:2)))));
        AdapterProbeCommand command={AdapterProbeMagic,action};
        if(send(fd,&command,sizeof(command),0)!=sizeof(command)){printf("REQUEST_SEND_ERRNO=%d\n",errno);close(fd);return 5;}
        uint32_t size=0;
        if(!ReadBytes(fd,&size,sizeof(size)) || size>16384){close(fd);puts("HELPER_NO_REPLY=1");return 5;}
        NSMutableData *data=[NSMutableData dataWithLength:size];BOOL received=ReadBytes(fd,data.mutableBytes,size);
        close(fd);if(!received){printf("INCOMPLETE_REPLY_BYTES=%u\n",size);return 5;}
        fwrite(data.bytes,1,data.length,stdout);puts("");return 0;
    }
}
