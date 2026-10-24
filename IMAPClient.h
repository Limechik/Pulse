#import <Foundation/Foundation.h>

// Блокирующий IMAP-клиент с таймаутами. Весь жизненный цикл (connect...disconnect)
// должен идти в ОДНОМ фоновом потоке (внутри одного dispatch_async-блока).
@interface IMAPClient : NSObject
- (BOOL)connectToHost:(NSString *)host port:(int)port error:(NSString **)error;
- (BOOL)loginWithUser:(NSString *)user password:(NSString *)password error:(NSString **)error;
// Папки: path (сырое имя для SELECT), displayName, special (sent/drafts/trash/junk/archive/all/flagged или "")
- (NSArray *)listFolders:(NSString **)error;
// Письма: seq, seen (BOOL), from (имя), subject, date (NSDate), preview. Новые сверху.
- (NSArray *)fetchLatest:(int)count inFolder:(NSString *)path error:(NSString **)error;
// Полное письмо: from, fromAddress, to, cc, subject, date, body, html (BOOL), attachments [{name,size}]
// Помечает письмо прочитанным, если mark == YES.
- (NSDictionary *)fetchMessageUID:(NSString *)uid inFolder:(NSString *)path markSeen:(BOOL)mark error:(NSString **)error;
- (void)disconnect;
@end
