#import <Foundation/Foundation.h>

// Пароль хранится в Keychain. Если Keychain недоступен (приложение подписано
// без entitlements), используется запасной файл с защитой данных iOS.
@interface KeychainStore : NSObject
+ (BOOL)savePassword:(NSString *)password forAccount:(NSString *)account;
+ (NSString *)passwordForAccount:(NSString *)account;
+ (void)deletePasswordForAccount:(NSString *)account;
@end
