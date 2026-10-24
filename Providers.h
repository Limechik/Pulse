#import <Foundation/Foundation.h>

// Пресеты: name, imapHost, imapPort, smtpHost, smtpPort, hint
@interface Providers : NSObject
+ (NSArray *)all;
@end
