#import "Providers.h"

@implementation Providers

+ (NSArray *)all {
    static NSArray *list;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        list = @[
            @{@"name": @"Gmail",
              @"imapHost": @"imap.gmail.com", @"imapPort": @993,
              @"smtpHost": @"smtp.gmail.com", @"smtpPort": @465,
              @"hint": @"Нужна двухфакторная аутентификация и пароль приложения."},
            @{@"name": @"Yandex",
              @"imapHost": @"imap.yandex.ru", @"imapPort": @993,
              @"smtpHost": @"smtp.yandex.ru", @"smtpPort": @465,
              @"hint": @"Включите доступ почтовых клиентов и создайте пароль приложения."},
            @{@"name": @"Mail.ru",
              @"imapHost": @"imap.mail.ru", @"imapPort": @993,
              @"smtpHost": @"smtp.mail.ru", @"smtpPort": @465,
              @"hint": @"Нужен пароль для внешнего приложения."},
            @{@"name": @"iCloud",
              @"imapHost": @"imap.mail.me.com", @"imapPort": @993,
              @"smtpHost": @"smtp.mail.me.com", @"smtpPort": @587,
              @"hint": @"Нужен пароль для конкретного приложения (appleid.apple.com)."},
            @{@"name": @"Yahoo",
              @"imapHost": @"imap.mail.yahoo.com", @"imapPort": @993,
              @"smtpHost": @"smtp.mail.yahoo.com", @"smtpPort": @465,
              @"hint": @"Нужен сгенерированный пароль приложения."},
        ];
    });
    return list;
}

@end
