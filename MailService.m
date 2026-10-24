#import "MailService.h"
#import "Localization.h"
#import "IMAPClient.h"
#import "SMTPClient.h"
#import "Providers.h"
#import "KeychainStore.h"
#import "AccountStore.h"

static NSString *SpecialFor(NSString *flagSpecial, NSString *path, NSString *lastComp) {
    if (flagSpecial.length) return flagSpecial;
    if ([path caseInsensitiveCompare:@"INBOX"] == NSOrderedSame) return @"inbox";
    NSDictionary *map = @{@"sent": @"sent", @"sent items": @"sent", @"sent messages": @"sent", @"отправленные": @"sent",
                          @"drafts": @"drafts", @"draft": @"drafts", @"черновики": @"drafts",
                          @"trash": @"trash", @"deleted items": @"trash", @"deleted messages": @"trash",
                          @"bin": @"trash", @"корзина": @"trash",
                          @"spam": @"junk", @"junk": @"junk", @"junk email": @"junk", @"bulk mail": @"junk", @"спам": @"junk",
                          @"archive": @"archive", @"архив": @"archive"};
    return map[[lastComp lowercaseString]] ?: @"";
}

@implementation MailService {
    dispatch_queue_t _queue;
}

+ (MailService *)shared {
    static MailService *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[MailService alloc] init]; });
    return s;
}

- (id)init {
    self = [super init];
    if (self) _queue = dispatch_queue_create("com.lime.pulse.mail", DISPATCH_QUEUE_SERIAL);
    return self;
}

- (void)perform:(id (^)(IMAPClient *c, NSString **err))work done:(void (^)(id result, NSString *err))done {
    NSString *email = [AccountStore activeEmail];
    NSDictionary *p = [Providers all][[AccountStore activeProviderIndex]];
    NSString *pass = [KeychainStore passwordForAccount:email ?: @""];

    dispatch_async(_queue, ^{
        NSString *err = nil;
        id result = nil;
        IMAPClient *c = [[IMAPClient alloc] init];
        if ([c connectToHost:p[@"imapHost"] port:[p[@"imapPort"] intValue] error:&err] &&
            [c loginWithUser:email password:pass ?: @"" error:&err]) {
            result = work(c, &err);
        }
        [c disconnect];
        dispatch_async(dispatch_get_main_queue(), ^{
            done(result, result ? nil : (err ?: L(@"Неизвестная ошибка")));
        });
    });
}

- (void)loadFolders:(void (^)(NSArray *, NSString *))done {
    [self perform:^id(IMAPClient *c, NSString **err) {
        NSArray *raw = [c listFolders:err];
        return raw ? [MailService normalize:raw] : nil;
    } done:^(id r, NSString *e) { done(r, e); }];
}

- (void)loadMessagesInFolder:(NSString *)path count:(int)count
                  completion:(void (^)(NSArray *, NSString *))done {
    [self perform:^id(IMAPClient *c, NSString **err) {
        return [c fetchLatest:count inFolder:path error:err];
    } done:^(id r, NSString *e) { done(r, e); }];
}

- (void)loadMessageUID:(NSString *)uid inFolder:(NSString *)path
           completion:(void (^)(NSDictionary *, NSString *))done {
    [self perform:^id(IMAPClient *c, NSString **err) {
        return [c fetchMessageUID:uid inFolder:path markSeen:YES error:err];
    } done:^(id r, NSString *e) { done(r, e); }];
}

- (void)sendTo:(NSArray *)to cc:(NSArray *)cc subject:(NSString *)subject body:(NSString *)body
    inReplyTo:(NSString *)irt references:(NSString *)refs
   completion:(void (^)(BOOL, NSString *))done {
    NSString *email = [AccountStore activeEmail];
    NSDictionary *p = [Providers all][[AccountStore activeProviderIndex]];
    NSString *pass = [KeychainStore passwordForAccount:email ?: @""];

    dispatch_async(_queue, ^{
        NSString *err = nil;
        SMTPClient *c = [[SMTPClient alloc] init];
        NSData *msg = [SMTPClient buildMessageFrom:email to:to cc:cc subject:subject body:body
                                         inReplyTo:irt references:refs];
        NSArray *all = [to arrayByAddingObjectsFromArray:cc ?: @[]];
        BOOL ok = [c connectToHost:p[@"smtpHost"] port:[p[@"smtpPort"] intValue] error:&err]
               && [c authenticateUser:email password:pass ?: @"" error:&err]
               && [c sendFrom:email recipients:all message:msg error:&err];
        [c quit];
        dispatch_async(dispatch_get_main_queue(), ^{ done(ok, ok ? nil : (err ?: L(@"Неизвестная ошибка"))); });
    });
}

+ (NSArray *)normalize:(NSArray *)raw {
    NSDictionary *names = @{@"inbox": L(@"Входящие"), @"drafts": L(@"Черновики"), @"sent": L(@"Отправленные"),
                            @"junk": L(@"Спам"), @"trash": L(@"Корзина"), @"archive": L(@"Архив"),
                            @"all": L(@"Вся почта"), @"flagged": L(@"Помеченные")};
    NSDictionary *rank = @{@"inbox": @0, @"drafts": @1, @"sent": @2, @"archive": @3,
                           @"all": @4, @"flagged": @5, @"junk": @6, @"trash": @7};
    NSMutableArray *out = [NSMutableArray array];
    BOOL hasInbox = NO;
    for (NSDictionary *f in raw) {
        NSString *special = SpecialFor(f[@"special"], f[@"path"], f[@"displayName"]);
        if ([special isEqualToString:@"inbox"]) {
            if (hasInbox) continue;
            hasInbox = YES;
        }
        NSString *name = special.length ? names[special] : f[@"displayName"];
        [out addObject:@{@"path": f[@"path"], @"name": name, @"special": special,
                         @"rank": rank[special] ?: @10}];
    }
    if (!hasInbox)
        [out addObject:@{@"path": @"INBOX", @"name": L(@"Входящие"), @"special": @"inbox", @"rank": @0}];
    [out sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSComparisonResult r = [a[@"rank"] compare:b[@"rank"]];
        return r != NSOrderedSame ? r : [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
    }];
    return out;
}

@end
