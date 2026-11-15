#ifndef SI_PRESENTATION_H
#define SI_PRESENTATION_H
#include <stdbool.h>
#include <stddef.h>
typedef struct { double x, y, width, height; } SIItemFrame;
SIItemFrame SIPlaceItem(double hostWidth, double hostHeight, double width, double height,
                        double xPercent, double offsetY);
// No units means a stable KB/s scale, not an ambiguous automatically changing scale.
void SIFormatRate(double bytes, bool valid, bool units, char *output, size_t capacity);
void SIComposeSpeed(double download, double upload, bool valid, unsigned mode, unsigned arrangement,
                    bool units, bool arrows, bool uploadFirst, bool hideZero, bool zeroWhenInvalid,
                    unsigned precision, unsigned unitStyle, char *output, size_t capacity);
#endif
