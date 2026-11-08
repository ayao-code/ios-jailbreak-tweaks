#include "GroupMigration.h"
#include "MachOInspector.h"
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct { uint64_t offset,size,address; unsigned char names[32]; uint32_t flags; } Section;
typedef struct { uint32_t offset,size,id; } Crypt;
struct CloneGroupPlan {
    Section sections[512]; Crypt crypt[16]; uint64_t patches[128];
    unsigned sectionCount,cryptCount,patchCount;
    uint64_t signatureOffset,signatureSize,fileSize;
};
static uint32_t u32(const unsigned char *p) { return (uint32_t)p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24; }
static uint64_t u64(const unsigned char *p) { return u32(p)|(uint64_t)u32(p+4)<<32; }
static bool readAt(FILE *f,uint64_t off,void *buf,size_t n) { return off<=INT64_MAX && !fseeko(f,(off_t)off,SEEK_SET) && fread(buf,1,n,f)==n; }
static bool zeroFill(uint32_t flags) { unsigned k=flags&255; return k==1 || k==12 || k==18; }
static bool overlaps(uint64_t a,uint64_t n,uint64_t b,uint64_t m) { return a<b+m && b<a+n; }
static bool parse(FILE *f,CloneGroupPlan *p) {
    unsigned char h[80];
    if(fseeko(f,0,SEEK_END)) return false;
    off_t size=ftello(f); if(size<32) return false; p->fileSize=(uint64_t)size;
    if(!readAt(f,0,h,32) || u32(h)!=0xfeedfacf || u32(h+4)!=0x100000c || (u32(h+8)&0xffffff)!=0) return false;
    unsigned count=u32(h+16),bytes=u32(h+20); uint64_t pos=32,end=32+(uint64_t)bytes;
    if(end>p->fileSize || count>bytes/8) return false;
    for(unsigned i=0;i<count;i++) {
        if(pos+8>end || !readAt(f,pos,h,8)) return false;
        unsigned cmd=u32(h),n=u32(h+4); if(n<8 || n>end-pos) return false;
        if(cmd==0x19) {
            if(n<72 || !readAt(f,pos,h,72)) return false;
            unsigned ns=u32(h+64); if(ns>(n-72)/80 || ns>512-p->sectionCount) return false;
            for(unsigned j=0;j<ns;j++) {
                if(!readAt(f,pos+72+j*80,h,80)) return false;
                Section *s=&p->sections[p->sectionCount++]; memcpy(s->names,h,32);
                s->address=u64(h+32);s->size=u64(h+40);s->offset=u32(h+48);s->flags=u32(h+64);
                if(!zeroFill(s->flags) && (s->offset>p->fileSize || s->size>p->fileSize-s->offset)) return false;
            }
        } else if(cmd==0x21 || cmd==0x2c) {
            if(n<20 || p->cryptCount==16 || !readAt(f,pos,h,20)) return false;
            Crypt *c=&p->crypt[p->cryptCount++];c->offset=u32(h+8);c->size=u32(h+12);c->id=u32(h+16);
            if(c->offset>p->fileSize || c->size>p->fileSize-c->offset) return false;
        } else if(cmd==0x1d) {
            if(n<16 || p->signatureSize || !readAt(f,pos,h,16)) return false;
            p->signatureOffset=u32(h+8);p->signatureSize=u32(h+12);
            if(p->signatureOffset>p->fileSize || p->signatureSize>p->fileSize-p->signatureOffset) return false;
        }
        pos+=n;
    }
    return pos==end;
}
static bool record(FILE *f,CloneGroupPlan *p,uint64_t offset,const char *old,size_t n) {
    if(p->signatureSize && offset>=p->signatureOffset && offset+n<=p->signatureOffset+p->signatureSize) return true;
    Section *s=NULL;
    for(unsigned i=0;i<p->sectionCount;i++) {
        Section *candidate=&p->sections[i];
        if(!zeroFill(candidate->flags) && offset>=candidate->offset && offset+n<=candidate->offset+candidate->size) { s=candidate;break; }
    }
    if(!s || memcmp(s->names,"__cstring\0",10) || s->flags&0x80000400 || p->patchCount==128) return false;
    unsigned char previous=0,tail[3];
    if(offset>s->offset && (!readAt(f,offset-1,&previous,1) || previous)) return false;
    if(offset+n>=s->offset+s->size || !readAt(f,offset+n,tail,1)) return false;
    if(tail[0]) {
        if(offset+n+3>s->offset+s->size || !readAt(f,offset+n,tail,3) || memcmp(tail,"OS\0",3)) return false;
    }
    for(unsigned i=0;i<p->cryptCount;i++) {
        Crypt *c=&p->crypt[i]; if(c->id && overlaps(offset,n,c->offset,c->size)) return false;
    }
    (void)old;
    p->patches[p->patchCount++]=offset;return true;
}
CloneGroupPlan *cloneGroupPlan(const char *path,const char *old) {
    size_t n=strlen(old); if(!n || n>64) return NULL;
    FILE *f=fopen(path,"rb"),*lookup=fopen(path,"rb");
    CloneGroupPlan *p=calloc(1,sizeof(*p)); bool ok=f && lookup && p && parse(lookup,p);
    unsigned char buf[65536+64];size_t carry=0;uint64_t consumed=0;
    while(ok) {
        size_t got=fread(buf+carry,1,65536,f),total=got+carry;
        if(!got) { if(ferror(f)) ok=false; break; }
        for(size_t i=0;i+n<=total;i++) if(!memcmp(buf+i,old,n)) {
            if(!record(lookup,p,consumed-carry+i,old,n)) { ok=false;break; }
        }
        consumed+=got;carry=total<n-1?total:n-1;memmove(buf,buf+total-carry,carry);
    }
    if(f) fclose(f);if(lookup) fclose(lookup);
    if(!ok) { free(p);return NULL; } return p;
}
size_t cloneGroupPatchCount(const CloneGroupPlan *p) { return p?p->patchCount:0; }
bool cloneGroupApply(const char *path,const CloneGroupPlan *p,const char *old,const char *next) {
    size_t n=strlen(old); if(!p || strlen(next)!=n || n>64) return false;
    FILE *f=fopen(path,"r+b"); if(!f) return false; bool ok=true;char buf[64];
    for(unsigned i=0;i<p->patchCount;i++) {
        uint64_t off=p->patches[i];
        if(!readAt(f,off,buf,n) || memcmp(buf,old,n) || fseeko(f,(off_t)off,SEEK_SET) || fwrite(next,1,n,f)!=n) { ok=false;break; }
    }
    if(fclose(f)) ok=false;return ok;
}
static bool compareRange(FILE *a,FILE *b,uint64_t start,uint64_t size,const CloneGroupPlan *p,const char *next,bool patched) {
    unsigned char aa[32768],bb[32768];size_t length=strlen(next);
    for(uint64_t pos=start;pos<start+size;) {
        size_t n=start+size-pos>sizeof(aa)?sizeof(aa):(size_t)(start+size-pos);
        if(!readAt(a,pos,aa,n) || !readAt(b,pos,bb,n)) return false;
        if(patched) for(unsigned i=0;i<p->patchCount;i++) {
            uint64_t off=p->patches[i];
            if(overlaps(pos,n,off,length)) {
                uint64_t begin=pos>off?pos:off,end=pos+n<off+length?pos+n:off+length;
                memcpy(aa+begin-pos,next+begin-off,(size_t)(end-begin));
            }
        }
        if(memcmp(aa,bb,n)) return false;pos+=n;
    }
    return true;
}
bool cloneGroupVerify(const char *before,const char *after,const CloneGroupPlan *p,const char *old,const char *next) {
    if(!p || strlen(old)!=strlen(next)) return false;
    FILE *a=fopen(before,"rb"),*b=fopen(after,"rb");CloneGroupPlan *final=calloc(1,sizeof(*final));
    bool ok=a && b && final && parse(b,final) && p->sectionCount==final->sectionCount && p->cryptCount==final->cryptCount &&
        !memcmp(p->sections,final->sections,p->sectionCount*sizeof(Section)) && !memcmp(p->crypt,final->crypt,p->cryptCount*sizeof(Crypt));
    for(unsigned i=0;ok && i<p->sectionCount;i++) { const Section *s=&p->sections[i];if(!zeroFill(s->flags)) ok=compareRange(a,b,s->offset,s->size,p,next,true); }
    for(unsigned i=0;ok && i<p->cryptCount;i++) { const Crypt *c=&p->crypt[i];ok=compareRange(a,b,c->offset,c->size,p,next,false); }
    if(a) fclose(a);if(b) fclose(b);free(final);
    if(ok) { CloneGroupPlan *remaining=cloneGroupPlan(after,old);ok=remaining && !remaining->patchCount;free(remaining); }
    return ok && cloneMachOCodeEqual(before,after);
}
void cloneGroupFree(CloneGroupPlan *p) { free(p); }
