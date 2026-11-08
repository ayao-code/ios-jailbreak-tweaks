#import <Foundation/Foundation.h>
void ASGRecordDiagnostic(NSString *stage, NSDictionary<NSString *, NSNumber *> *values);
void ASGFlushDiagnostics(void);
void ASGStartDiagnosticCycle(uint64_t generation);
#if ASG_DIAGNOSTICS
#define ASGDiagnostic(...) ASGRecordDiagnostic(__VA_ARGS__)
#else
#define ASGDiagnostic(...) ((void)0)
#endif
