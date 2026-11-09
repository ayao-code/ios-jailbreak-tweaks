#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <mach/mach_time.h>
#import <unistd.h>
#include <stdbool.h>
int main(void) {
 @autoreleasepool {
  void *s=dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices",RTLD_NOW);
  unsigned (*port)(void)=dlsym(s,"SBSSpringBoardServerPort");
  void (*lock)(unsigned,BOOL*,BOOL*)=dlsym(s,"SBGetScreenLockStatus");
  BOOL locked=(BOOL)-1,pass=(BOOL)-1;if(!port||!lock)return 2;
  lock(port(),&locked,&pass);if(locked!=NO || pass!=NO){puts("refused: requires current unlocked and no passcode");return 3;}
  void *io=dlopen("/System/Library/Frameworks/IOKit.framework/IOKit",RTLD_NOW);
  CFTypeRef (*client)(CFAllocatorRef)=dlsym(io,"IOHIDEventSystemClientCreate");
  CFTypeRef (*event)(CFAllocatorRef,uint64_t,uint32_t,uint32_t,bool,uint32_t)=dlsym(io,"IOHIDEventCreateKeyboardEvent");
  void (*sender)(CFTypeRef,uint64_t)=dlsym(io,"IOHIDEventSetSenderID");
  void (*send)(CFTypeRef,CFTypeRef)=dlsym(io,"IOHIDEventSystemClientDispatchEvent");
  if(!client||!event||!sender||!send)return 4;
  CFTypeRef c=client(kCFAllocatorDefault);if(!c)return 5;
  CFTypeRef events[4];for(int i=0;i<4;i++){events[i]=event(kCFAllocatorDefault,mach_absolute_time(),0x0c,0x30,(i%2)==0,0);if(!events[i])return 6;sender(events[i],0x8000000817319372);}
  for(int i=0;i<4;i++){send(c,events[i]);usleep(i%2?100000:60000);CFRelease(events[i]);}
  CFRelease(c);puts("four HID events requested; not proof of hardware callback/camera foreground");return 0;
 }
}
