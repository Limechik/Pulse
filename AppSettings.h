#import <Foundation/Foundation.h>

@interface AppSettings : NSObject
+ (BOOL)darkTheme;
+ (void)setDarkTheme:(BOOL)on;
+ (int)messageCount;                 // 25 / 50 / 100, по умолчанию 50
+ (void)setMessageCount:(int)n;
+ (BOOL)showPreview;                 // по умолчанию YES
+ (void)setShowPreview:(BOOL)on;
+ (NSString *)language;                // @"auto" | @"ru" | @"en"
+ (void)setLanguage:(NSString *)code;
@end
