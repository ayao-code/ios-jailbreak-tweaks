// Root-only supervisor: verify the live tool's audit identity and pinned CDHash.
#import <Foundation/Foundation.h>
#import "protocol.h"
#import <fcntl.h>
#import <sys/stat.h>
int main(int argc,const char *argv[]){
    @autoreleasepool{
        if(geteuid()!=0||argc!=3)return 2;
        NSString *file=@(argv[1]),*destination=@(argv[2]);
        if(![destination hasSuffix:@"/tmp/vpa1.permit"]||![destination hasPrefix:@"/var/mobile/Containers/Data/Application/"])return 2;
        NSData *input=[NSData dataWithContentsOfFile:file];
        if(!input)return 3;
        NSDictionary *request=[NSJSONSerialization JSONObjectWithData:input options:0 error:nil];
        NSArray *audit=request[@"audit"];if(audit.count!=8||![request[@"permitPath"] isEqual:destination])return 3;
        AdapterProbePermit permit={.magic=AdapterProbeMagic,.expires=(uint64_t)((NSDate.date.timeIntervalSince1970+35)*1000)};
        for(unsigned i=0;i<8;i++)permit.token[i]=[audit[i] unsignedIntValue];
        if(permit.token[5]!=[request[@"pid"] unsignedIntValue]||permit.token[1]!=501)return 3;
        uint8_t hash[20]={0};
        if(csops_audittoken((pid_t)permit.token[5],5,hash,sizeof(hash),permit.token)){printf("AUDIT_CODEHASH_ERRNO=%d\n",errno);return 4;}
        if(memcmp(hash,AdapterExpectedCodeHash,sizeof(hash))){
            puts("PINNED_HASH_MISMATCH=1");
            printf("RUNTIME_CDHASH=");for(unsigned i=0;i<20;i++)printf("%02x",hash[i]);puts("");
            return 4;
        }
        char executable[4096]={0};if(proc_pidpath((int)permit.token[5],executable,sizeof(executable))<=0)return 4;
        NSString *path=@((const char *)executable);
        if(![path hasPrefix:@"/private/var/mobile/Containers/Shared/AppGroup/.jbroot-"]||
           ![path hasSuffix:@"/var/tmp/vpn-adapter-native-probe"]){puts("CALLER_PATH_MISMATCH=1");return 4;}
        NSString *physical=destination;
        NSString *temporary=[physical stringByAppendingString:@".incoming"];
        int fd=open(temporary.fileSystemRepresentation,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0644);
        if(fd<0){
            // RootHide still sandboxes this standalone executable; the already
            // authorized root supervisor publishes the verified IPC permit.
            NSData *payload=[NSData dataWithBytes:&permit length:sizeof(permit)];
            printf("VERIFIED_PERMIT=%s\n",[[payload base64EncodedStringWithOptions:0] UTF8String]);
            puts("AUTHORIZED_PINNED_CALLER=1");return 0;
        }
        BOOL ok=write(fd,&permit,sizeof(permit))==sizeof(permit)&&!fchown(fd,0,0)&&!fchmod(fd,0644);close(fd);
        if(!ok||rename(temporary.fileSystemRepresentation,physical.fileSystemRepresentation)){
            printf("PERMIT_PUBLISH_ERRNO=%d\n",errno);
            unlink(temporary.fileSystemRepresentation);return 5;
        }
        puts("AUTHORIZED_PINNED_CALLER=1");return 0;
    }
}
