#import "Localization.h"
#import "AppSettings.h"

NSString *PulseCurrentLanguage(void) {
    NSString *pref = [AppSettings language];
    if ([pref isEqualToString:@"ru"] || [pref isEqualToString:@"en"]) return pref;
    NSArray *langs = [NSLocale preferredLanguages];
    NSString *sys = langs.count ? [langs objectAtIndex:0] : nil;
    return [sys hasPrefix:@"ru"] ? @"ru" : @"en";
}

NSString *PulseLocalized(NSString *key) {
    if (!key || [PulseCurrentLanguage() isEqualToString:@"ru"]) return key;
    return PulseEnglishStrings()[key] ?: key;
}

NSLocale *PulseLocale(void) {
    return [[NSLocale alloc] initWithLocaleIdentifier:PulseCurrentLanguage()];
}
