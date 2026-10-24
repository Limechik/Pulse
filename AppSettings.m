#import "AppSettings.h"

@implementation AppSettings

+ (BOOL)darkTheme { return [[NSUserDefaults standardUserDefaults] boolForKey:@"darkTheme"]; }
+ (void)setDarkTheme:(BOOL)on {
    [[NSUserDefaults standardUserDefaults] setBool:on forKey:@"darkTheme"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

+ (int)messageCount {
    NSInteger n = [[NSUserDefaults standardUserDefaults] integerForKey:@"messageCount"];
    return n > 0 ? (int)n : 50;
}
+ (void)setMessageCount:(int)n {
    [[NSUserDefaults standardUserDefaults] setInteger:n forKey:@"messageCount"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

+ (BOOL)showPreview {
    NSNumber *n = [[NSUserDefaults standardUserDefaults] objectForKey:@"showPreview"];
    return n ? [n boolValue] : YES;
}
+ (void)setShowPreview:(BOOL)on {
    [[NSUserDefaults standardUserDefaults] setBool:on forKey:@"showPreview"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

+ (NSString *)language { return [[NSUserDefaults standardUserDefaults] stringForKey:@"language"] ?: @"auto"; }
+ (void)setLanguage:(NSString *)code {
    [[NSUserDefaults standardUserDefaults] setObject:code forKey:@"language"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

@end
