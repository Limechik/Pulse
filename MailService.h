#import <Foundation/Foundation.h>

// Все сетевые операции идут через одну последовательную очередь.
// Колбэки приходят в главном потоке.
@interface MailService : NSObject
+ (MailService *)shared;
// folders: path, name (локализованное), special, rank
- (void)loadFolders:(void (^)(NSArray *folders, NSString *error))done;
- (void)loadMessagesInFolder:(NSString *)path count:(int)count
                  completion:(void (^)(NSArray *messages, NSString *error))done;
- (void)loadMessageUID:(NSString *)uid inFolder:(NSString *)path
           completion:(void (^)(NSDictionary *message, NSString *error))done;
// Отправка письма по SMTP (To/Cc — массивы адресов)
- (void)sendTo:(NSArray *)to cc:(NSArray *)cc subject:(NSString *)subject body:(NSString *)body
    inReplyTo:(NSString *)inReplyTo references:(NSString *)references
   completion:(void (^)(BOOL ok, NSString *error))done;
@end
