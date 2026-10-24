#import <Foundation/Foundation.h>

// Ключи локализации — это исходные русские строки; английский перевод — в LocalizationEN.m.
NSString *PulseCurrentLanguage(void);     // @"ru" или @"en" (с учётом настройки языка)
NSString *PulseLocalized(NSString *key);
NSLocale *PulseLocale(void);
NSDictionary *PulseEnglishStrings(void);  // LocalizationEN.m

#define L(s) PulseLocalized(s)
