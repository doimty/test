#import <Foundation/Foundation.h>

@interface PSSpecifier : NSObject
@property (nonatomic, retain) NSMutableDictionary *properties;
- (void)setValues:(id)values titles:(id)titles;
@end
