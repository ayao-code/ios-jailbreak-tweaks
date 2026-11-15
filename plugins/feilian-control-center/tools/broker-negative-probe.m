// This standalone tool is not SpringBoard: broker must refuse it.
#import <Foundation/Foundation.h>
#import "../Shared/VPNAuth.h"
int main(void) {
    @autoreleasepool {
        int fd=socket(AF_UNIX,SOCK_STREAM,0);if(fd<0)return 2;
        struct timeval timeout={.tv_sec=3};setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
        int yes=1;setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&yes,sizeof(yes));
        struct sockaddr_un address={.sun_family=AF_UNIX,.sun_len=sizeof(address)};
        strlcpy(address.sun_path,VPN_AUTH_SOCKET,sizeof(address.sun_path));
        if(connect(fd,(void *)&address,sizeof(address))){printf("broker_connect_errno=%d\n",errno);close(fd);return 3;}
        VPNAuthRequest request={.magic=VPN_AUTH_MAGIC,.provider=0};arc4random_buf(request.nonce,sizeof(request.nonce));
        VPNAuthTransfer(fd,&request,sizeof(request),YES);uint32_t result=0;
        BOOL received=VPNAuthTransfer(fd,&result,sizeof(result),NO);close(fd);
        printf("received=%d unauthorized_rejected=%d code=%u\n",received,received && result!=VPN_AUTH_MAGIC,result);
        return received && result!=VPN_AUTH_MAGIC?0:1;
    }
}
