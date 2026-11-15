#include "SIRate.h"
#include "SIPresentation.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <string.h>
int main(void) {
    SIRateState state = {0}; SISample a[2] = {{"en0", 100, 200}, {"pdp_ip0", 30, 40}};
    assert(SIPhysicalInterface("en0") && SIPhysicalInterface("pdp_ip1"));
    assert(!SIPhysicalInterface("utun2") && !SIPhysicalInterface("lo0"));
    assert(!SIPhysicalInterface(NULL) && !SIPhysicalInterface("pdp_ip") && !SIPhysicalInterface("pdp_ipx"));
    assert(!SIUpdateRate(&state,a,2,1).valid);
    a[0].received+=2048; a[0].sent+=1024;
    SIRate r=SIUpdateRate(&state,a,2,3); assert(r.valid && r.download==1024 && r.upload==512);
    a[0].received=0;a[0].sent=0; r=SIUpdateRate(&state,a,2,5);assert(!r.valid && r.download==0 && r.upload==0);
    SISample b={"pdp_ip1",9000,8000}; r=SIUpdateRate(&state,&b,1,7);assert(!r.valid && r.download==0);
    assert(!SIUpdateRate(&state,&b,1,30).valid);
    assert(!SIUpdateRate(&state,&b,SI_MAX_INTERFACES+1,31).valid);
    assert(!SIUpdateRate(&state,&b,1,NAN).valid);
    a[1]=a[0];assert(!SIUpdateRate(&state,a,2,32).valid);
    memset(&state,0,sizeof(state));
    SISample huge={"en0", UINT64_C(4294967290), UINT64_C(4294967290)};
    assert(!SIUpdateRate(&state,&huge,1,1).valid);
    huge.received += 2048; huge.sent += 4096;
    r=SIUpdateRate(&state,&huge,1,3);assert(r.valid && r.download==1024 && r.upload==2048);
    assert(!SIUpdateRate(&state,&huge,1,2).valid);
    assert(!SIUpdateRate(&state,&huge,1,2.1).valid);
    huge.name[0]=0; memset(huge.name,'x',sizeof(huge.name));
    assert(!SIUpdateRate(&state,&huge,1,5).valid);
    memset(&state,0,sizeof(state));
    SISample single={"en0",1000,1000};
    assert(!SIUpdateRate(&state,&single,1,1).valid);
    single.received=0;single.sent=2000;
    r=SIUpdateRate(&state,&single,1,3);assert(!r.valid && r.download==0 && r.upload==0);
    char output[96];
    for (unsigned zero=0;zero<2;zero++) {
        for (unsigned hide=0;hide<2;hide++) {
            SIComposeSpeed(r.download,r.upload,r.valid,1,0,false,false,false,hide,zero,0,0,output,sizeof(output));
            assert(!strcmp(output,zero ? "0" : "--")); // Invalid zero is never hidden as idle.
        }
    }
    single.received=2048;single.sent=3024;
    r=SIUpdateRate(&state,&single,1,5);assert(r.valid && r.download==1024 && r.upload==512);
    single.sent=0;
    r=SIUpdateRate(&state,&single,1,7);assert(!r.valid); // One-direction reset invalidates the aggregate.
    r=SIUpdateRate(&state,&single,1,9);assert(r.valid && r.download==0 && r.upload==0);
    r=SIUpdateRate(&state,&single,0,11);assert(!r.valid);
    r=SIUpdateRate(&state,&single,0,13);assert(!r.valid);
    r=SIUpdateRate(&state,&single,1,15);assert(!r.valid); // Reappearance establishes a baseline.
    r=SIUpdateRate(&state,&single,1,17);assert(r.valid && r.download==0 && r.upload==0);
    SISample reorder[2]={{"en0",1000,1000},{"pdp_ip0",100,100}};
    memset(&state,0,sizeof(state));assert(!SIUpdateRate(&state,reorder,2,1).valid);
    SISample swap=reorder[0];reorder[0]=reorder[1];reorder[1]=swap;
    r=SIUpdateRate(&state,reorder,2,3);assert(r.valid); // Ordering alone does not invalidate.
    strcpy(reorder[0].name,"pdp_ip1");
    r=SIUpdateRate(&state,reorder,2,5);assert(!r.valid); // Same count, different interface set.
    r=SIUpdateRate(&state,reorder,2,7);assert(r.valid);
    puts("PASS rates: physical-only, delta/interval, reset, interface replacement, suspension gap, invalid input");
}
