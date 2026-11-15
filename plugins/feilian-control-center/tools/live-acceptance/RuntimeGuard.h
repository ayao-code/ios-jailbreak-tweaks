#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// A class name alone does not identify code in a process hosting system bundles.
static inline BOOL VPNTestObjectMatches(id object, NSString *name, NSString *executable) {
    if (!object || !executable.length || ![NSStringFromClass([object class]) isEqual:name]) return NO;
    const char *image=class_getImageName([object class]);
    if (!image) return NO;
    NSString *actual=[@(image) stringByResolvingSymlinksInPath];
    return [actual isEqual:[executable stringByResolvingSymlinksInPath]];
}
static inline BOOL VPNTestSignature(id object, SEL selector, NSUInteger count, const char *result) {
    if (!object || ![object respondsToSelector:selector]) return NO;
    NSMethodSignature *signature=[object methodSignatureForSelector:selector];
    return signature && signature.numberOfArguments==count && !strcmp(signature.methodReturnType,result);
}
