#include "MachOInspector.h"
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static uint32_t word(const unsigned char *p, bool big) {
    return big ? ((uint32_t)p[0]<<24 | (uint32_t)p[1]<<16 | p[2]<<8 | p[3])
               : ((uint32_t)p[3]<<24 | (uint32_t)p[2]<<16 | p[1]<<8 | p[0]);
}
static uint64_t wideword(const unsigned char *p, bool big) {
    return big ? (uint64_t)word(p,true)<<32 | word(p+4,true)
               : (uint64_t)word(p+4,false)<<32 | word(p,false);
}
static bool readbytes(FILE *f, uint64_t offset, void *p, size_t n) {
    return offset <= INT64_MAX && !fseeko(f,(off_t)offset,SEEK_SET) && fread(p,1,n,f)==n;
}
static bool parse(FILE *f, uint64_t base, uint64_t length, CloneMachOInfo *out, unsigned depth) {
    unsigned char h[32];
    if (length<4 || !readbytes(f,base,h,4)) return false;
    uint32_t magic=word(h,false);
    bool fat=magic==0xbebafeca || magic==0xbfbafeca || magic==0xcafebabe || magic==0xcafebabf;
    bool thin=magic==0xfeedfacf || magic==0xcefaedfe || magic==0xcffaedfe || magic==0xfeedface;
    if (!fat && !thin) return false;
    out->is_macho=true;
    if (depth>1 || length<28 || !readbytes(f,base,h,28)) { out->malformed=true; return true; }
    if (fat) {
        bool big=magic==0xbebafeca || magic==0xbfbafeca;
        bool wide=magic==0xbfbafeca || magic==0xcafebabf;
        uint32_t count=word(h+4,big), size=wide?32:20;
        if (!count || count>64 || 8+(uint64_t)count*size>length) { out->malformed=true; return true; }
        uint64_t ends[64], starts[64];
        for (unsigned i=0;i<count;i++) {
            if (!readbytes(f,base+8+i*size,h,size)) { out->malformed=true; break; }
            uint64_t start=wide?wideword(h+8,big):word(h+8,big);
            uint64_t n=wide?wideword(h+16,big):word(h+12,big);
            if (start<8+(uint64_t)count*size || start>length || n>length-start) { out->malformed=true; break; }
            for (unsigned j=0;j<i;j++) if (start<ends[j] && starts[j]<start+n) out->malformed=true;
            starts[i]=start; ends[i]=start+n;
            if (!parse(f,base+start,n,out,depth+1)) out->malformed=true;
        }
        return true;
    }
    bool big=magic==0xcefaedfe || magic==0xcffaedfe;
    bool wide=magic==0xfeedfacf || magic==0xcffaedfe;
    uint32_t count=word(h+16,big), bytes=word(h+20,big);
    uint64_t pos=wide?32:28;
    if (pos>length || bytes>length-pos || count>bytes/8) { out->malformed=true; return true; }
    out->slices++;
    if (word(h+4,big)==0x100000c && (word(h+8,big)&0xffffff)==0) out->has_arm64=true;
    uint64_t end=pos+bytes;
    for (unsigned i=0;i<count;i++) {
        if (end-pos<8 || !readbytes(f,base+pos,h,8)) { out->malformed=true; break; }
        uint32_t cmd=word(h,big), size=word(h+4,big);
        if (size<8 || size>end-pos) { out->malformed=true; break; }
        if (cmd==0x21 || cmd==0x2c) {
            if (size<20 || !readbytes(f,base+pos,h,20)) { out->malformed=true; break; }
            uint32_t off=word(h+8,big), n=word(h+12,big);
            if (off>length || n>length-off) out->malformed=true;
            if (word(h+16,big)) out->encrypted=true;
        } else if (cmd==0x25 || cmd==0x32) {
            unsigned off=cmd==0x32?12:8;
            if (size<off+4 || !readbytes(f,base+pos,h,off+4)) { out->malformed=true; break; }
            unsigned v=word(h+off,big);
            if (v>out->max_minimum_ios) out->max_minimum_ios=v;
        } else if (cmd==0xc || cmd==0x80000018 || cmd==0x8000001f || cmd==0x80000023) {
            if (size<24 || !readbytes(f,base+pos,h,12)) { out->malformed=true; break; }
            unsigned off=word(h+8,big); char name[4096];
            size_t n=off<size ? size-off : 0;
            if (!n || n>=sizeof(name) || !readbytes(f,base+pos+off,name,n) || !memchr(name,0,n)) { out->malformed=true; break; }
            if (strstr(name,"/var/jb") || strstr(name,".jbroot") || strstr(name,"CydiaSubstrate") || strstr(name,"AutoSkip") || strstr(name,"libsubstrate")) out->jailbreak_dependency=true;
        }
        pos+=size;
    }
    if (pos!=end) out->malformed=true;
    return true;
}
CloneMachOInfo cloneInspectMachO(const char *path) {
    CloneMachOInfo out={0}; FILE *f=fopen(path,"rb");
    if (!f) { out.malformed=true; return out; }
    if (fseeko(f,0,SEEK_END)) out.malformed=true;
    else { off_t n=ftello(f); if(n<0) out.malformed=true; else parse(f,0,(uint64_t)n,&out,0); }
    fclose(f); return out;
}

// Signing may change __LINKEDIT and load commands, never instruction bytes.
static bool codeEqual(FILE *a, FILE *b, uint64_t abase, uint64_t bbase, unsigned depth) {
    unsigned char ah[32],bh[32];
    if(depth>1 || !readbytes(a,abase,ah,28) || !readbytes(b,bbase,bh,28)) return false;
    uint32_t magic=word(ah,false);
    if(magic!=word(bh,false)) return false;
    if(magic==0xbebafeca || magic==0xbfbafeca || magic==0xcafebabe || magic==0xcafebabf) {
        bool big=magic==0xbebafeca || magic==0xbfbafeca;
        bool wide=magic==0xbfbafeca || magic==0xcafebabf;
        unsigned count=word(ah+4,big), size=wide?32:20;
        if(!count || count>64 || count!=word(bh+4,big)) return false;
        for(unsigned i=0;i<count;i++) {
            if(!readbytes(a,abase+8+i*size,ah,size) || !readbytes(b,bbase+8+i*size,bh,size)) return false;
            if(memcmp(ah,bh,8)) return false;
            uint64_t ao=wide?wideword(ah+8,big):word(ah+8,big), bo=wide?wideword(bh+8,big):word(bh+8,big);
            if(!codeEqual(a,b,abase+ao,bbase+bo,depth+1)) return false;
        }
        return true;
    }
    bool big=magic==0xcefaedfe || magic==0xcffaedfe;
    bool wide=magic==0xfeedfacf || magic==0xcffaedfe;
    if(magic!=0xfeedface && magic!=0xfeedfacf && magic!=0xcefaedfe && magic!=0xcffaedfe) return false;
    if(memcmp(ah+4,bh+4,12)) return false;
    unsigned count=word(ah+16,big),bcount=word(bh+16,big),bbytes=word(bh+20,big);
    uint64_t pos=wide?32:28;
    for(unsigned i=0;i<count;i++) {
        if(!readbytes(a,abase+pos,ah,8)) return false;
        unsigned cmd=word(ah,big),size=word(ah+4,big);
        if(size<8) return false;
        if(cmd==(wide?0x19u:1u)) {
            unsigned header=wide?72:56,section=wide?80:68;
            unsigned char aseg[72],bseg[72];
            if(size<header || !readbytes(a,abase+pos,aseg,header)) return false;
            unsigned nsects=word(aseg+(wide?64:48),big);
            uint64_t bpos=wide?32:28; bool found=false;
            for(unsigned j=0;j<bcount;j++) {
                if(!readbytes(b,bbase+bpos,bh,8)) return false;
                unsigned bc=word(bh,big),bs=word(bh+4,big);
                if(bs<8 || bpos+bs>(wide?32u:28u)+(uint64_t)bbytes) return false;
                if(bc==cmd && bs>=header && readbytes(b,bbase+bpos,bseg,header) && !memcmp(aseg+8,bseg+8,16)) { found=true; break; }
                bpos+=bs;
            }
            if(!found || nsects!=word(bseg+(wide?64:48),big) || nsects>(size-header)/section) return false;
            for(unsigned k=0;k<nsects;k++) {
                unsigned char as[80],bs[80];
                if(!readbytes(a,abase+pos+header+k*section,as,section) || !readbytes(b,bbase+bpos+header+k*section,bs,section)) return false;
                unsigned flags=word(as+(wide?64:56),big);
                if(flags&0x80000400) {
                    uint64_t length=wide?wideword(as+40,big):word(as+36,big);
                    uint64_t blength=wide?wideword(bs+40,big):word(bs+36,big);
                    if(memcmp(as,bs,32) || length!=blength) return false;
                    unsigned ao=word(as+(wide?48:40),big),bo=word(bs+(wide?48:40),big);
                    unsigned char ab[32768],bb[32768];
                    for(uint64_t off=0;off<length;) {
                        size_t n=length-off>sizeof(ab)?sizeof(ab):(size_t)(length-off);
                        if(!readbytes(a,abase+ao+off,ab,n) || !readbytes(b,bbase+bo+off,bb,n) || memcmp(ab,bb,n)) return false;
                        off+=n;
                    }
                }
            }
        }
        pos+=size;
    }
    return true;
}
bool cloneMachOCodeEqual(const char *before,const char *after) {
    FILE *a=fopen(before,"rb"),*b=fopen(after,"rb");
    bool same=a && b && codeEqual(a,b,0,0,0);
    if(a) fclose(a); if(b) fclose(b); return same;
}
