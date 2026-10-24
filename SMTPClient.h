#import <Foundation/Foundation.h>

// Блокирующий SMTP-клиент. Порт 465 — сразу TLS, остальные (587) — STARTTLS.
// Весь жизненный цикл — в одном фоновом потоке.
@interface SMTPClient : NSObject
- (BOOL)connectToHost:(NSString *)host port:(int)port error:(NSString **)error;
- (BOOL)authenticateUser:(NSString *)user password:(NSString *)password error:(NSString **)error;
- (BOOL)sendFrom:(NSString *)from recipients:(NSArray *)recipients message:(NSData *)message error:(NSString **)error;
- (void)quit;

+ (NSData *)buildMessageFrom:(NSString *)from to:(NSArray *)to cc:(NSArray *)cc
                     subject:(NSString *)subject body:(NSString *)body
                   inReplyTo:(NSString *)inReplyTo references:(NSString *)references;
@end
