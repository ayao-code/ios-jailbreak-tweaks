#import <Foundation/Foundation.h>
#import <sys/socket.h>
#import <sys/un.h>
#import <sys/stat.h>
#import <unistd.h>
#import <fcntl.h>
#import <errno.h>

#define VPN_AUTH_MAGIC 0x56414132u
#define VPN_AUTH_SOCKET "/var/run/ayao.vpncc-auth.sock"
#define VPN_AUTH_PERMIT "vcc1.permit"
typedef struct {
    uint32_t magic, provider;
    unsigned char nonce[16];
} VPNAuthRequest;
typedef struct {
    VPNAuthRequest request;
    uint32_t audit[8];
    uint64_t expires;
} VPNAuthPermit;
static inline BOOL VPNAuthTransfer(int fd, void *buffer, size_t size, BOOL write) {
    size_t offset=0;
    while(offset<size) {
        ssize_t n=write?send(fd,(char *)buffer+offset,size-offset,0):recv(fd,(char *)buffer+offset,size-offset,0);
        if(n<0 && errno==EINTR)continue;
        if(n<=0)return NO;
        offset+=(size_t)n;
    }
    return YES;
}
