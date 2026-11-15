#include "SIPresentation.h"
#include <math.h>
#include <stdio.h>
#include <string.h>
static double SIClamp(double value, double low, double high) {
    return fmin(high, fmax(low, value));
}
SIItemFrame SIPlaceItem(double hostWidth, double hostHeight, double width, double height,
                        double xPercent, double offsetY) {
    SIItemFrame result = {0};
    if (!isfinite(hostWidth) || !isfinite(hostHeight) || hostWidth <= 0 || hostHeight <= 0
        || !isfinite(width) || !isfinite(height) || width <= 0 || height <= 0
        || !isfinite(xPercent) || !isfinite(offsetY)) return result;
    result.width = fmin(width, hostWidth); result.height = fmin(height, hostHeight);
    result.x = SIClamp(hostWidth * SIClamp(xPercent, 0, 100) / 100 - result.width / 2,
                       0, hostWidth - result.width);
    result.y = SIClamp((hostHeight - result.height) / 2 + offsetY, 0, hostHeight - result.height);
    return result;
}
void SIFormatRate(double bytes, bool valid, bool units, char *output, size_t capacity) {
    if (!output || !capacity) return;
    if (!valid || !isfinite(bytes) || bytes < 0) { snprintf(output, capacity, "--"); return; }
    double value = bytes / 1024;
    if (!units) {
        // Fixed scale and bounded width even for corrupted input.
        snprintf(output, capacity, "%.0f", fmin(value, 999999)); return;
    }
    const char *suffix = "K";
    if (value >= 1024 * 1024) { value /= 1024 * 1024; suffix = "G"; }
    else if (value >= 1024) { value /= 1024; suffix = "M"; }
    if (suffix[0] == 'K') snprintf(output, capacity, "%.0f%s", value, suffix);
    else snprintf(output, capacity, "%.1f%s", fmin(value, 999.9), suffix);
}
static void SIStyledRate(double bytes, bool valid, bool units, unsigned precision, unsigned unitStyle,
                         bool zeroWhenInvalid, char *output, size_t capacity) {
    if (!valid && !zeroWhenInvalid) { snprintf(output,capacity,"--"); return; }
    if (!isfinite(bytes) || bytes<0) { snprintf(output,capacity,"--"); return; }
    double value=bytes/1024;
    const char *suffix="";
    if (units) {
        suffix="K";
        if (value>=1024*1024) {value/=1024*1024; suffix="G";}
        else if (value>=1024) {value/=1024; suffix="M";}
    }
    unsigned decimals=precision==2 ? 1 : (precision==1 ? 0 : (units && suffix[0]!='K' ? 1 : 0));
    double limit=units ? (suffix[0]=='K' ? 1024 : 999.9) : 999999;
    snprintf(output,capacity,"%.*f%s%s",decimals,fmin(value,limit),suffix,units && unitStyle==1 ? "B/s" : "");
}
void SIComposeSpeed(double download, double upload, bool valid, unsigned mode, unsigned arrangement,
                    bool units, bool arrows, bool uploadFirst, bool hideZero, bool zeroWhenInvalid,
                    unsigned precision, unsigned unitStyle, char *output, size_t capacity) {
    if (!output || !capacity) return;
    if (mode>2 || arrangement>1 || precision>2 || unitStyle>1) { snprintf(output,capacity,"--"); return; }
    bool measured = valid && isfinite(download) && isfinite(upload) && download>=0 && upload>=0;
    valid = measured;
    if (!measured) { download = 0; upload = 0; }
    bool idle=mode==1 ? download<.5 : (mode==2 ? upload<.5 : download<.5 && upload<.5);
    if (valid && hideZero && idle) { output[0]=0; return; }
    char down[24],up[24];
    SIStyledRate(download,valid,units,precision,unitStyle,zeroWhenInvalid,down,sizeof(down));
    SIStyledRate(upload,valid,units,precision,unitStyle,zeroWhenInvalid,up,sizeof(up));
    const char *d=arrows ? "\xe2\x86\x93" : "", *u=arrows ? "\xe2\x86\x91" : "";
    if (mode==1) snprintf(output,capacity,"%s%s",d,down);
    else if (mode==2) snprintf(output,capacity,"%s%s",u,up);
    else {
        const char *separator=arrangement==0 ? "\n" : " ";
        snprintf(output,capacity,"%s%s%s%s%s",uploadFirst ? u:d,uploadFirst ? up:down,separator,
            uploadFirst ? d:u,uploadFirst ? down:up);
    }
}
