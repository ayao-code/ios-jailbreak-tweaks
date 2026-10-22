#import <Preferences/PSListController.h>

@interface LAPRootListController : PSListController
- (id)readSystemVolume:(PSSpecifier *)specifier;
- (void)setSystemVolume:(id)value specifier:(PSSpecifier *)specifier;
- (void)setModePreferenceValue:(id)value specifier:(PSSpecifier *)specifier;
@end
