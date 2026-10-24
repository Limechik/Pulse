#import <Foundation/Foundation.h>

// Список почтовых аккаунтов (email + индекс сервиса). Пароли — в Keychain (KeychainStore).
@interface AccountStore : NSObject
+ (NSArray *)accounts;                         // [{email, providerIndex}]
+ (NSDictionary *)activeAccount;               // nil, если аккаунтов нет
+ (NSString *)activeEmail;
+ (NSInteger)activeProviderIndex;
+ (NSInteger)activeIndex;
+ (void)setActiveIndex:(NSInteger)index;
+ (void)addAccount:(NSString *)email providerIndex:(NSInteger)providerIndex;   // новый или обновление; становится активным
+ (void)removeActiveAccount;                   // удаляет и пароль из Keychain
@end
