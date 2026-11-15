// Runs the real v2 server transport in a disposable Mac process. Raw socket
// clients deliberately have no SpringBoard identity, token or broker permit.
#import <Foundation/Foundation.h>
#import <sys/socket.h>
#import <sys/un.h>
#import <unistd.h>
#import <stdatomic.h>
#import <time.h>
#import "../Shared/VPNIPC.h"

typedef struct { uint32_t magic, version, action, code; uint64_t generation, deadline; } Message;
static NSUInteger Commands, Canceled;
static uint64_t PreviousOperation;
static atomic_bool Done;
static atomic_uint Passed;
static double Monotonic(void) { struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return t.tv_sec+t.tv_nsec/1e9; }
#define CHECK(x) do { if(!(x)){fprintf(stderr,"FAIL line=%d %s\n",__LINE__,#x);exit(1);}atomic_fetch_add(&Passed,1); }while(0)
static int Open(void) {
    int fd=socket(AF_UNIX,SOCK_STREAM,0);CHECK(fd>=0);
    struct timeval timeout={.tv_sec=3};setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
    int yes=1;setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&yes,sizeof(yes));
    struct sockaddr_un a={.sun_family=AF_UNIX,.sun_len=sizeof(a)};
    strlcpy(a.sun_path,VPNIPCSocketPath(@"easy").fileSystemRepresentation,sizeof(a.sun_path));
    CHECK(!connect(fd,(void *)&a,sizeof(a)));return fd;
}
static Message Make(uint32_t action,uint64_t generation,double seconds) {
    return (Message){0x56504e31,2,action,0,generation,(uint64_t)((NSDate.date.timeIntervalSince1970+seconds)*1000)};
}
static Message Exchange(int fd,Message message) {
    CHECK(send(fd,&message,sizeof(message),0)==sizeof(message));
    Message reply={0};size_t count=0;
    while(count<sizeof(reply)){ssize_t n=recv(fd,(char *)&reply+count,sizeof(reply)-count,0);CHECK(n>0);count+=(size_t)n;}
    CHECK(reply.magic==message.magic && reply.version==2 && reply.action==message.action && reply.generation==message.generation);
    return reply;
}
static void Reject(Message message) {
    int fd=Open();CHECK(send(fd,&message,sizeof(message),0)==sizeof(message));
    char byte;CHECK(recv(fd,&byte,1,0)==0);close(fd);
}
int main(void) { @autoreleasepool {
    atomic_init(&Done,false);atomic_init(&Passed,0);
    VPNIPCServer *server=[[VPNIPCServer alloc] initWithProvider:@"easy" command:^(uint64_t generation,BOOL connect,VPNIPCReply reply){
        Commands++;
        CHECK(generation > PreviousOperation);
        PreviousOperation = generation;
        if(Commands==4)return; // Hold a request to verify real timer cancellation.
        reply(connect?VPNReplyConnected:VPNReplyDisconnected);
    } cancel:^(uint64_t generation){CHECK(generation==PreviousOperation);Canceled++;}];
    CHECK(server!=nil);
    CHECK([[VPNIPCSocketPath(@"easy") lastPathComponent] hasSuffix:@".sock"]);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT,0),^{@autoreleasepool{
        int fd=Open();CHECK(Exchange(fd,Make(0,0,2)).code==VPNReplyReady);
        CHECK(Exchange(fd,Make(1,1,2)).code==VPNReplyConnected);
        CHECK(Exchange(fd,Make(2,2,2)).code==VPNReplyDisconnected);
        Message replay=Make(1,2,2);CHECK(send(fd,&replay,sizeof(replay),0)==sizeof(replay));char b;CHECK(recv(fd,&b,1,0)==0);close(fd);
        Message bad=Make(1,3,2);bad.version=1;Reject(bad);
        bad=Make(1,3,2);bad.magic=0;Reject(bad);
        bad=Make(3,3,2);Reject(bad);
        bad=Make(1,3,2);bad.code=1;Reject(bad);
        bad=Make(1,3,-1);Reject(bad);
        bad=Make(1,3,1000);Reject(bad);
        bad=Make(1,0,2);Reject(bad);
        // Fragmented request is assembled, not mistaken for a complete command.
        fd=Open();Message partial=Make(1,3,2);
        CHECK(send(fd,&partial,7,0)==7);usleep(20000);
        CHECK(send(fd,(char *)&partial+7,sizeof(partial)-7,0)==sizeof(partial)-7);
        Message response;CHECK(recv(fd,&response,sizeof(response),MSG_WAITALL)==sizeof(response));CHECK(response.code==VPNReplyConnected);close(fd);
        // Pending request is canceled exactly once on its deadline, then a fresh
        // non-SpringBoard caller can reconnect without any helper daemon.
        fd=Open();Message held=Make(1,999,0.3);double started=Monotonic();
        CHECK(send(fd,&held,sizeof(held),0)==sizeof(held));
        // EOF must come from the server's deadline, before the client's 3s
        // SO_RCVTIMEO. EAGAIN/local timeout cannot count as server cancellation.
        CHECK(recv(fd,&b,1,0)==0);CHECK(Monotonic()-started<1.5);close(fd);
        fd=Open();CHECK(Exchange(fd,Make(0,0,2)).code==VPNReplyReady);close(fd);
        // A different client's high sequence must not poison normal callers.
        fd=Open();CHECK(Exchange(fd,Make(1,UINT64_MAX,2)).code==VPNReplyConnected);close(fd);
        fd=Open();CHECK(Exchange(fd,Make(1,1,2)).code==VPNReplyConnected);
        Message duplicate=Make(1,1,2);CHECK(send(fd,&duplicate,sizeof(duplicate),0)==sizeof(duplicate));
        CHECK(recv(fd,&b,1,0)==0);close(fd);
        atomic_store(&Done,true);
    }});
    NSDate *limit=[NSDate dateWithTimeIntervalSinceNow:15];
    while(!atomic_load(&Done) && limit.timeIntervalSinceNow>0)[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    CHECK(atomic_load(&Done));CHECK(Commands==6);CHECK(Canceled==1);
    printf("LOCAL_OPEN_IPC_CHECKS=%u PASS=1 (host real sockets; no device VPN operation)\n",atomic_load(&Passed));
    (void)server;
}return 0;}
