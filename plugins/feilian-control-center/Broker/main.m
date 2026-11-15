// Root-owned narrow authenticator. It cannot start a VPN or accept commands.
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <sys/poll.h>
#import <signal.h>
#import <spawn.h>
#import <sys/wait.h>
#import "../Shared/VPNAuth.h"
#import "../Shared/VPNIPC.h"
extern int proc_pidpath(int,void *,uint32_t);
extern int csops_audittoken(pid_t,unsigned,void *,size_t,void *);
extern char **environ;
static BOOL ShellPublish(NSString *directory, const struct stat *identity, VPNAuthPermit *permit) {
    // RootHide's packaged root shell is the existing authorized filesystem
    // publisher. This fixed script cannot receive arbitrary commands or paths.
    unsigned char random[16];arc4random_buf(random,sizeof(random));
    NSMutableString *suffix=[NSMutableString string];
    for(unsigned i=0;i<sizeof(random);i++)[suffix appendFormat:@"%02x",random[i]];
    NSString *source=[@"/var/run/.vpncc-permit-" stringByAppendingString:suffix];
    int file=open(source.fileSystemRepresentation,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0600);
    if(file<0)return NO;
    BOOL ok=write(file,permit,sizeof(*permit))==sizeof(*permit);close(file);
    if(!ok){unlink(source.fileSystemRepresentation);return NO;}
    Dl_info info={0};dladdr((void *)ShellPublish,&info);
    NSString *root=info.dli_fname?@(info.dli_fname):nil;
    for(unsigned i=0;i<3;i++)root=root.stringByDeletingLastPathComponent;
    NSString *shell=[root stringByAppendingPathComponent:@"bin/sh"];
    NSString *script=[root stringByAppendingPathComponent:@"usr/libexec/vpncc-auth-publish"];
    NSString *physicalSource=[@"/rootfs" stringByAppendingString:source];
    NSString *physicalTarget=[@"/rootfs" stringByAppendingString:directory];
    NSString *device=[NSString stringWithFormat:@"%llu",(unsigned long long)identity->st_dev];
    NSString *inode=[NSString stringWithFormat:@"%llu",(unsigned long long)identity->st_ino];
    char *args[]={(char *)shell.fileSystemRepresentation,(char *)script.fileSystemRepresentation,
        (char *)physicalSource.fileSystemRepresentation,(char *)physicalTarget.fileSystemRepresentation,
        (char *)device.UTF8String,(char *)inode.UTF8String,NULL};
    char *childEnvironment[]={"PATH=/usr/bin:/bin:/usr/sbin:/sbin","HOME=/var/root","TMPDIR=/var/tmp",NULL};
    pid_t child;int error=posix_spawn(&child,shell.fileSystemRepresentation,NULL,NULL,args,childEnvironment);
    // Publication is asynchronous. The broker authenticates the caller here;
    // only the App's later nonce/audit/file verification authorizes the socket.
    // Do not hold the broker reply while RootHide waits for a shell child.
    if(error)unlink(source.fileSystemRepresentation);
    return error==0;
}
@interface NSObject (VPNBrokerRegistry)
+ (id)applicationProxyForIdentifier:(NSString *)identifier;
- (NSURL *)dataContainerURL;
- (NSURL *)bundleURL;
@end
static uint32_t Reason;
static BOOL Publish(int fd) {
    Reason=1;
    uint32_t audit[8]={0};socklen_t size=sizeof(audit);
    uid_t uid;gid_t gid;
    if(getpeereid(fd,&uid,&gid) || uid!=501 ||
        getsockopt(fd,SOL_LOCAL,LOCAL_PEERTOKEN,audit,&size) || size!=sizeof(audit))return NO;
    Reason=2;char executable[4096]={0};uint32_t flags=0;
    if(proc_pidpath((pid_t)audit[5],executable,sizeof(executable))<=0 ||
        strcmp(executable,"/System/Library/CoreServices/SpringBoard.app/SpringBoard") ||
        csops_audittoken((pid_t)audit[5],0,&flags,sizeof(flags),audit) || !(flags&0x04000000)){
        fprintf(stderr,"BROKER_CALLER_REJECTED errno=%d platform=%d\n",errno,(flags&0x04000000)!=0);return NO;
    }
    Reason=3;VPNAuthRequest request={0};
    if(!VPNAuthTransfer(fd,&request,sizeof(request),NO) || request.magic!=VPN_AUTH_MAGIC ||
        request.provider>=VPNProviders().count)return NO;
    Reason=4;NSString *provider=VPNProviders()[request.provider];
    Class cls=NSClassFromString(@"LSApplicationProxy");
    id proxy=[cls respondsToSelector:@selector(applicationProxyForIdentifier:)]?
        [cls applicationProxyForIdentifier:VPNBundle(provider)]:nil;
    if(![proxy respondsToSelector:@selector(dataContainerURL)] || ![proxy respondsToSelector:@selector(bundleURL)]){fprintf(stderr,"REGISTRY_UNAVAILABLE\n");return NO;}
    Reason=5;NSURL *container=[proxy dataContainerURL],*bundle=[proxy bundleURL];
    NSDictionary *info=[NSDictionary dictionaryWithContentsOfFile:[bundle.path stringByAppendingPathComponent:@"Info.plist"]];
    if(!container.isFileURL || ![info[@"CFBundleIdentifier"] isEqual:VPNBundle(provider)]){fprintf(stderr,"METADATA_REJECTED\n");return NO;}
    Reason=6;NSString *path=container.path;
    if([path hasPrefix:@"/private/var/"])path=[path substringFromIndex:8];
    if(![path hasPrefix:@"/var/mobile/Containers/Data/Application/"] ||
        path.pathComponents.count!=7){fprintf(stderr,"PATH_REJECTED count=%lu\n",(unsigned long)path.pathComponents.count);return NO;}
    Reason=7;NSString *directory=[path stringByAppendingPathComponent:@"tmp"];
    struct stat st;
    if(lstat(directory.fileSystemRepresentation,&st) || !S_ISDIR(st.st_mode) || st.st_uid!=501){fprintf(stderr,"DIRECTORY_REJECTED errno=%d\n",errno);return NO;}
    // All publications use the same descriptor-relative publisher. The old
    // direct open protected only the final component, not mutable ancestors.
    // Keep the existing RootHide shell projection, but never cd into App tmp.
    VPNAuthPermit permit={.request=request,.expires=(uint64_t)((NSDate.date.timeIntervalSince1970+20)*1000)};
    memcpy(permit.audit,audit,sizeof(audit));
    Reason=8;return ShellPublish(directory,&st,&permit);
}
int main(void) {
    @autoreleasepool {
        if(geteuid()!=0)return 2;
        setvbuf(stderr,NULL,_IONBF,0);
        signal(SIGPIPE,SIG_IGN);
        signal(SIGCHLD,SIG_IGN);
        dlopen("/System/Library/Frameworks/MobileCoreServices.framework/MobileCoreServices",RTLD_NOW);
        struct stat st;
        if(!lstat(VPN_AUTH_SOCKET,&st)) {
            if(!S_ISSOCK(st.st_mode)||st.st_uid!=0){fprintf(stderr,"BROKER_SOCKET_OWNER=%u MODE=%o\n",st.st_uid,st.st_mode);return 3;}
            // launchd has a single owner. Do not replace a live listener.
            int test=socket(AF_UNIX,SOCK_STREAM,0);
            struct sockaddr_un a={.sun_family=AF_UNIX,.sun_len=sizeof(a)};
            strlcpy(a.sun_path,VPN_AUTH_SOCKET,sizeof(a.sun_path));
            BOOL live=connect(test,(void *)&a,sizeof(a))==0;close(test);
            if(live){fprintf(stderr,"BROKER_ALREADY_RUNNING=1\n");return 3;}
            if(unlink(VPN_AUTH_SOCKET)){fprintf(stderr,"BROKER_SOCKET_REMOVE=%d\n",errno);return 3;}
        }
        int server=socket(AF_UNIX,SOCK_STREAM,0);if(server<0)return 4;
        struct sockaddr_un address={.sun_family=AF_UNIX,.sun_len=sizeof(address)};
        strlcpy(address.sun_path,VPN_AUTH_SOCKET,sizeof(address.sun_path));
        mode_t mask=umask(077);int bound=bind(server,(void *)&address,sizeof(address));umask(mask);
        if(bound || chown(VPN_AUTH_SOCKET,0,501) || chmod(VPN_AUTH_SOCKET,0660) || listen(server,4)) {
            fprintf(stderr,"BROKER_BIND_FAILED=%d\n",errno);return 4;
        }
        for(;;) {
            int peer=accept(server,NULL,NULL);if(peer<0){if(errno==EINTR)continue;return 5;}
            @autoreleasepool {
                struct timeval timeout={.tv_sec=2};
                setsockopt(peer,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
                setsockopt(peer,SOL_SOCKET,SO_SNDTIMEO,&timeout,sizeof(timeout));
                uint32_t result=Publish(peer)?VPN_AUTH_MAGIC:Reason;
                VPNAuthTransfer(peer,&result,sizeof(result),YES);close(peer);
            }
        }
    }
}
