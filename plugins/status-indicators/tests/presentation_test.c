#include "SIPresentation.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <string.h>
static void expect(double bytes, bool valid, bool units, const char *expected) {
    char result[32]; SIFormatRate(bytes, valid, units, result, sizeof(result));
    assert(!strcmp(result, expected));
}
int main(void) {
    expect(0, true, false, "0");
    expect(3072, true, false, "3");
    expect(1024 * 1024, true, false, "1024");
    expect(1024 * 1024, true, true, "1.0M");
    expect(3 * 1024, true, true, "3K");
    expect(1024.0 * 1024 * 1024, true, true, "1.0G");
    expect(0, false, false, "--");
    expect(NAN, true, false, "--");
    expect(-1, true, true, "--");
    expect(1e20, true, false, "999999");
    char tiny[2] = {0}; SIFormatRate(1024, true, false, tiny, sizeof(tiny));
    assert(!strcmp(tiny, "1")); SIFormatRate(0, false, true, NULL, 0);
    SIItemFrame vpn = SIPlaceItem(375, 50, 10, 10, 25, 0);
    SIItemFrame location = SIPlaceItem(375, 50, 10, 10, 29, 0);
    assert(vpn.x == 88.75 && vpn.y == 20 && location.x == 103.75);
    // Different dimensions, independent positions and clipping at every edge.
    for (int i = -50; i <= 150; i++) {
        SIItemFrame f = SIPlaceItem(375,50,48,24,i,i-50);
        assert(f.x >= 0 && f.y >= 0 && f.x + f.width <= 375 && f.y + f.height <= 50);
        SIItemFrame landscape = SIPlaceItem(812, 20, 48, 24, i, i-50);
        assert(landscape.height==20 && landscape.y==0);
        assert(landscape.x >= 0 && landscape.x+landscape.width <= 812);
    }
    SIItemFrame belowIsland = SIPlaceItem(375, 200, 48, 24, 71, 100);
    assert(belowIsland.y > 150 && belowIsland.y + belowIsland.height <= 200);
    SIItemFrame vpnBelowIsland = SIPlaceItem(375, 200, 20, 20, 25, 100);
    assert(vpnBelowIsland.y > 150 && vpnBelowIsland.y + vpnBelowIsland.height <= 200);
    SIItemFrame invalid = SIPlaceItem(0, 0, 10, 10, 50, 0); assert(invalid.width == 0);
    invalid = SIPlaceItem(375,50,10,10,NAN,0); assert(invalid.width == 0);
    char text[96];
    SIComposeSpeed(4096,1024,true,0,0,false,false,false,false,false,0,0,text,sizeof(text)); assert(!strcmp(text,"4\n1"));
    SIComposeSpeed(4096,1024,true,0,1,false,true,true,false,false,0,0,text,sizeof(text)); assert(!strcmp(text,"\xe2\x86\x91" "1 " "\xe2\x86\x93" "4"));
    SIComposeSpeed(4096,1024,true,1,1,true,true,false,false,false,0,1,text,sizeof(text)); assert(!strcmp(text,"\xe2\x86\x93" "4KB/s"));
    SIComposeSpeed(1048576,1024,true,1,0,true,false,false,false,false,0,0,text,sizeof(text)); assert(!strcmp(text,"1.0M"));
    SIComposeSpeed(1048576,1024,true,1,0,true,false,false,false,false,1,1,text,sizeof(text)); assert(!strcmp(text,"1MB/s"));
    SIComposeSpeed(1536,0,true,1,0,false,false,false,false,false,2,0,text,sizeof(text)); assert(!strcmp(text,"1.5"));
    SIComposeSpeed(0,0,true,0,0,false,false,false,true,false,0,0,text,sizeof(text)); assert(!text[0]);
    SIComposeSpeed(0,0,false,0,0,false,false,false,true,false,0,0,text,sizeof(text)); assert(!strcmp(text,"--\n--"));
    SIComposeSpeed(0,0,false,0,0,true,false,false,false,true,0,0,text,sizeof(text)); assert(!strcmp(text,"0K\n0K"));
    SIComposeSpeed(0,0,false,1,1,true,true,false,false,true,0,1,text,sizeof(text)); assert(!strcmp(text,"\xe2\x86\x93" "0KB/s"));
    SIComposeSpeed(0,8192,true,1,0,false,false,false,true,false,0,0,text,sizeof(text)); assert(!text[0]);
    SIComposeSpeed(4096,0,true,2,0,false,false,false,true,false,0,0,text,sizeof(text)); assert(!text[0]);
    SIComposeSpeed(4096,1024,true,3,0,false,false,false,false,false,0,0,text,sizeof(text)); assert(!strcmp(text,"--"));
    SIComposeSpeed(NAN,0,true,0,0,false,false,false,false,false,0,0,text,sizeof(text)); assert(!strcmp(text,"--\n--"));
    unsigned combinations=0;
    for (unsigned mode=0;mode<3;mode++) for(unsigned arrangement=0;arrangement<2;arrangement++)
      for (unsigned flags=0;flags<16;flags++) for(unsigned precision=0;precision<3;precision++)
       for (unsigned units=0;units<2;units++) {
        char result[96];memset(result,0x7f,sizeof(result));
        SIComposeSpeed(4096,1024,true,mode,arrangement,units,flags&1,flags&2,flags&4,flags&8,precision,flags&8?1:0,result,sizeof(result));
        assert(memchr(result,0,sizeof(result)) && strlen(result)<90);combinations++;
       }
    printf("PASS speed styles: %u combinations + 12 format/unknown/idle tests\n",combinations);
    puts("PASS presentation: numeric-only fixed scale, optional units, independent positions and 402 edge/rotation cases");
}
