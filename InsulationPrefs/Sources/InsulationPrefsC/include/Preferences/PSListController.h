#import <UIKit/UIKit.h>
#import <Preferences/PSSpecifier.h>

@interface PSListController : UITableViewController
@property (nonatomic, retain) NSMutableArray *specifiers;
- (NSMutableArray *)loadSpecifiersFromPlistName:(NSString *)plistName target:(id)target;
- (id)readPreferenceValue:(PSSpecifier *)specifier;
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier;
- (void)reloadSpecifiers;
@end
