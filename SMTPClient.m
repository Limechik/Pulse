#import "SMTPClient.h"
#import "Localization.h"
#import <netdb.h>
#import <arpa/inet.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <errno.h>

static const NSTimeInterval kConnectTimeout = 15;
static const NSTimeInterval kIOTimeout = 30;

#pragma mark - Helpers

static NSString *Base64Encode(NSData *d, BOOL wrap) {
    static const char *tbl = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    const uint8_t *p = d.bytes;
    NSUInteger n = d.length;
    NSMutableString *out = [NSMutableString stringWithCapacity:n * 4 / 3 + n / 57 + 8];
    int col = 0;
    for (NSUInteger i = 0; i < n; i += 3) {
        uint32_t v = (uint32_t)p[i] << 16;
        if (i + 1 < n) v |= (uint32_t)p[i + 1] << 8;
        if (i + 2 < n) v |= p[i + 2];
        [out appendFormat:@"%c%c%c%c", tbl[(v >> 18) & 63], tbl[(v >> 12) & 63],
            (i + 1 < n) ? tbl[(v >> 6) & 63] : '=', (i + 2 < n) ? tbl[v & 63] : '='];
        col += 4;
        if (wrap && col >= 76 && i + 3 < n) { [out appendString:@"\r\n"]; col = 0; }
    }
    return out;
}

// RFC 2047: несколько encoded-word по ≤42 байт, чтобы не превысить 75 символов
static NSString *EncodeWords(NSString *s) {
    BOOL ascii = YES;
    for (NSUInteger i = 0; i < s.length; i++) if ([s characterAtIndex:i] > 127) { ascii = NO; break; }
    if (ascii) return s;
    NSMutableArray *words = [NSMutableArray array];
    NSMutableData *cur = [NSMutableData data];
    NSUInteger i = 0;
    while (i < s.length) {
        NSRange r = [s rangeOfComposedCharacterSequenceAtIndex:i];
        NSData *ch = [[s substringWithRange:r] dataUsingEncoding:NSUTF8StringEncoding];
        if (cur.length + ch.length > 42) { [words addObject:cur]; cur = [NSMutableData data]; }
        [cur appendData:ch];
        i = NSMaxRange(r);
    }
    if (cur.length) [words addObject:cur];
    NSMutableArray *enc = [NSMutableArray array];
    for (NSData *w in words) [enc addObject:[NSString stringWithFormat:@"=?UTF-8?B?%@?=", Base64Encode(w, NO)]];
    return [enc componentsJoinedByString:@"\r\n "];
}

#pragma mark - Client

@implementation SMTPClient {
    NSInputStream *_in;
    NSOutputStream *_out;
    NSRunLoop *_loop;
    NSMutableData *_buf;
    NSString *_host;
    NSString *_caps;
    BOOL _timedOut, _transient;
}

- (BOOL)connectToHost:(NSString *)host port:(int)port error:(NSString **)error {
    NSString *err = nil;
    for (int attempt = 0; attempt < 3; attempt++) {
        if (attempt > 0) [NSThread sleepForTimeInterval:1.5];
        err = nil;
        _transient = NO;
        if ([self openToHost:host port:port error:&err]) return YES;
        [self closeStreams];
        if (!_transient) break;
    }
    if (error) *error = err;
    return NO;
}

- (NSString *)resolveIPv4:(NSString *)host {
    struct addrinfo hints, *res = NULL;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;
    if (getaddrinfo([host UTF8String], NULL, &hints, &res) != 0 || !res) return nil;
    char buf[INET_ADDRSTRLEN];
    inet_ntop(AF_INET, &((struct sockaddr_in *)res->ai_addr)->sin_addr, buf, sizeof(buf));
    freeaddrinfo(res);
    return [NSString stringWithUTF8String:buf];
}

- (void)enableTLS {
    [_in setProperty:NSStreamSocketSecurityLevelNegotiatedSSL forKey:NSStreamSocketSecurityLevelKey];
    [_out setProperty:NSStreamSocketSecurityLevelNegotiatedSSL forKey:NSStreamSocketSecurityLevelKey];
    NSDictionary *ssl = @{(__bridge id)kCFStreamSSLPeerName: _host};
    CFReadStreamSetProperty((__bridge CFReadStreamRef)_in, kCFStreamPropertySSLSettings, (__bridge CFTypeRef)ssl);
    CFWriteStreamSetProperty((__bridge CFWriteStreamRef)_out, kCFStreamPropertySSLSettings, (__bridge CFTypeRef)ssl);
}

- (void)markTransientIfNetworkError {
    NSError *e = _in.streamError ?: _out.streamError;
    if ([e.domain isEqualToString:NSPOSIXErrorDomain] &&
        (e.code == ENETDOWN || e.code == ENETUNREACH || e.code == EHOSTUNREACH)) _transient = YES;
}

- (BOOL)openToHost:(NSString *)host port:(int)port error:(NSString **)error {
    _buf = [NSMutableData data];
    _timedOut = NO;
    _host = host;
    BOOL implicitTLS = (port == 465);

    NSString *ip = [self resolveIPv4:host];     // только IPv4, см. IMAPClient
    if (!ip) {
        _transient = YES;
        if (error) *error = [NSString stringWithFormat:L(@"Не удалось найти сервер %@ (DNS). Проверьте подключение к интернету."), host];
        return NO;
    }
    CFReadStreamRef r = NULL; CFWriteStreamRef w = NULL;
    CFStreamCreatePairWithSocketToHost(NULL, (__bridge CFStringRef)ip, port, &r, &w);
    if (!r || !w) { if (error) *error = L(@"Не удалось создать соединение"); return NO; }
    _in = (__bridge_transfer NSInputStream *)r;
    _out = (__bridge_transfer NSOutputStream *)w;
    if (implicitTLS) [self enableTLS];

    _loop = [NSRunLoop currentRunLoop];
    [_in scheduleInRunLoop:_loop forMode:NSDefaultRunLoopMode];
    [_out scheduleInRunLoop:_loop forMode:NSDefaultRunLoopMode];
    [_in open]; [_out open];

    BOOL opened = [self waitUntil:^BOOL{
        NSStreamStatus st = _in.streamStatus;
        return st != NSStreamStatusNotOpen && st != NSStreamStatusOpening;
    } timeout:kConnectTimeout];
    if (!opened) _timedOut = YES;
    if (!opened || [self broken]) {
        [self markTransientIfNetworkError];
        if (error) *error = [self lastError];
        return NO;
    }

    NSMutableArray *lines = [NSMutableArray array];
    int code = [self readResponse:lines];
    if (code != 220) {
        [self markTransientIfNetworkError];
        if (error) *error = [self failureText:lines];
        return NO;
    }
    code = [self command:@"EHLO localhost" lines:lines];
    if (code != 250) { if (error) *error = [self failureText:lines]; return NO; }
    _caps = [[lines componentsJoinedByString:@"\n"] uppercaseString];

    if (!implicitTLS) {
        if ([_caps rangeOfString:@"STARTTLS"].location == NSNotFound) {
            if (error) *error = L(@"Сервер не поддерживает шифрование (STARTTLS)");
            return NO;
        }
        code = [self command:@"STARTTLS" lines:lines];
        if (code != 220) { if (error) *error = [self failureText:lines]; return NO; }
        _buf = [NSMutableData data];
        [self enableTLS];
        code = [self command:@"EHLO localhost" lines:lines];
        if (code != 250) { if (error) *error = [self failureText:lines]; return NO; }
        _caps = [[lines componentsJoinedByString:@"\n"] uppercaseString];
    }
    return YES;
}

- (BOOL)authenticateUser:(NSString *)user password:(NSString *)pass error:(NSString **)error {
    NSMutableArray *lines = [NSMutableArray array];
    BOOL plain = [_caps rangeOfString:@"PLAIN"].location != NSNotFound;
    BOOL login = [_caps rangeOfString:@"LOGIN"].location != NSNotFound;
    int code;
    if (plain || !login) {
        NSMutableData *d = [NSMutableData data];
        uint8_t z = 0;
        [d appendBytes:&z length:1];
        [d appendData:[user dataUsingEncoding:NSUTF8StringEncoding]];
        [d appendBytes:&z length:1];
        [d appendData:[pass dataUsingEncoding:NSUTF8StringEncoding]];
        code = [self command:[@"AUTH PLAIN " stringByAppendingString:Base64Encode(d, NO)] lines:lines];
    } else {
        code = [self command:@"AUTH LOGIN" lines:lines];
        if (code == 334) code = [self command:Base64Encode([user dataUsingEncoding:NSUTF8StringEncoding], NO) lines:lines];
        if (code == 334) code = [self command:Base64Encode([pass dataUsingEncoding:NSUTF8StringEncoding], NO) lines:lines];
    }
    if (code != 235) { if (error) *error = [self failureText:lines]; return NO; }
    return YES;
}

- (BOOL)sendFrom:(NSString *)from recipients:(NSArray *)rcpts message:(NSData *)msg error:(NSString **)error {
    NSMutableArray *lines = [NSMutableArray array];
    int code = [self command:[NSString stringWithFormat:@"MAIL FROM:<%@>", from] lines:lines];
    if (code != 250) { if (error) *error = [self failureText:lines]; return NO; }
    for (NSString *r in rcpts) {
        code = [self command:[NSString stringWithFormat:@"RCPT TO:<%@>", r] lines:lines];
        if (code != 250 && code != 251) {
            if (error) *error = [NSString stringWithFormat:L(@"Адрес %@ отклонён. %@"), r, [self failureText:lines]];
            return NO;
        }
    }
    code = [self command:@"DATA" lines:lines];
    if (code != 354) { if (error) *error = [self failureText:lines]; return NO; }
    if (![self writeAll:msg] || ![self writeAll:[@".\r\n" dataUsingEncoding:NSUTF8StringEncoding]]) {
        if (error) *error = [self lastError];
        return NO;
    }
    code = [self readResponse:lines];
    if (code != 250) { if (error) *error = [self failureText:lines]; return NO; }
    return YES;
}

- (void)quit {
    if (_out && ![self broken] && [_out hasSpaceAvailable]) {
        NSData *d = [@"QUIT\r\n" dataUsingEncoding:NSUTF8StringEncoding];
        [_out write:d.bytes maxLength:d.length];
    }
    [self closeStreams];
}

- (void)closeStreams {
    if (_loop) {
        [_in removeFromRunLoop:_loop forMode:NSDefaultRunLoopMode];
        [_out removeFromRunLoop:_loop forMode:NSDefaultRunLoopMode];
    }
    [_in close]; [_out close];
    _in = nil; _out = nil;
}

#pragma mark - Сообщение

+ (NSData *)buildMessageFrom:(NSString *)from to:(NSArray *)to cc:(NSArray *)cc
                     subject:(NSString *)subject body:(NSString *)body
                   inReplyTo:(NSString *)irt references:(NSString *)refs {
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    df.dateFormat = @"EEE, dd MMM yyyy HH:mm:ss Z";
    NSString *domain = [[from componentsSeparatedByString:@"@"] lastObject];
    NSString *subj = [[subject ?: @"" stringByReplacingOccurrencesOfString:@"\r" withString:@" "]
                      stringByReplacingOccurrencesOfString:@"\n" withString:@" "];

    NSMutableString *h = [NSMutableString string];
    [h appendFormat:@"From: %@\r\n", from];
    [h appendFormat:@"To: %@\r\n", [to componentsJoinedByString:@", "]];
    if (cc.count) [h appendFormat:@"Cc: %@\r\n", [cc componentsJoinedByString:@", "]];
    [h appendFormat:@"Subject: %@\r\n", EncodeWords(subj)];
    [h appendFormat:@"Date: %@\r\n", [df stringFromDate:[NSDate date]]];
    [h appendFormat:@"Message-ID: <%@@%@>\r\n", [[NSUUID UUID] UUIDString], domain];
    if (irt.length) [h appendFormat:@"In-Reply-To: %@\r\n", irt];
    if (refs.length) [h appendFormat:@"References: %@\r\n", refs];
    [h appendString:@"MIME-Version: 1.0\r\n"];
    [h appendString:@"Content-Type: text/plain; charset=UTF-8\r\n"];
    [h appendString:@"Content-Transfer-Encoding: base64\r\n"];
    [h appendString:@"X-Mailer: Pulse\r\n\r\n"];

    NSString *norm = [(body ?: @"") stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
    norm = [norm stringByReplacingOccurrencesOfString:@"\n" withString:@"\r\n"];
    [h appendString:Base64Encode([norm dataUsingEncoding:NSUTF8StringEncoding], YES)];
    [h appendString:@"\r\n"];
    return [h dataUsingEncoding:NSUTF8StringEncoding];
}

#pragma mark - Низкий уровень

- (NSString *)lastError {
    NSError *e = _in.streamError ?: _out.streamError;
    if (e) {
        if ([e.domain isEqualToString:NSPOSIXErrorDomain] &&
            (e.code == ENETDOWN || e.code == ENETUNREACH || e.code == EHOSTUNREACH))
            return [NSString stringWithFormat:L(@"Нет доступа к сети (%@ %ld). Проверьте Wi-Fi или мобильный интернет и режим полёта."),
                    e.domain, (long)e.code];
        return [NSString stringWithFormat:L(@"Ошибка соединения: %@ (%@ %ld)"), e.localizedDescription, e.domain, (long)e.code];
    }
    if (_timedOut) return L(@"Сервер не отвечает (тайм-аут).");
    return L(@"Соединение закрыто сервером");
}

- (NSString *)failureText:(NSArray *)lines {
    NSString *l = [lines lastObject];
    return l.length ? [L(@"Сервер ответил: ") stringByAppendingString:l] : [self lastError];
}

- (BOOL)broken {
    NSStreamStatus s = _in.streamStatus;
    return s == NSStreamStatusError || s == NSStreamStatusClosed || s == NSStreamStatusAtEnd
        || _out.streamStatus == NSStreamStatusError;
}

- (BOOL)waitUntil:(BOOL (^)(void))cond timeout:(NSTimeInterval)t {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:t];
    while (!cond()) {
        if ([deadline timeIntervalSinceNow] <= 0) return NO;
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    return YES;
}

// Читает многострочный ответ, возвращает код (или -1)
- (int)readResponse:(NSMutableArray *)lines {
    [lines removeAllObjects];
    while (YES) {
        NSString *l = [self readLine];
        if (!l) return -1;
        [lines addObject:l];
        if (l.length < 4) return [l intValue];
        if ([l characterAtIndex:3] != '-') return [[l substringToIndex:3] intValue];
    }
}

- (int)command:(NSString *)cmd lines:(NSMutableArray *)lines {
    NSData *d = [[cmd stringByAppendingString:@"\r\n"] dataUsingEncoding:NSUTF8StringEncoding];
    if (![self writeAll:d]) { [lines removeAllObjects]; return -1; }
    return [self readResponse:lines];
}

- (BOOL)writeAll:(NSData *)data {
    const uint8_t *p = data.bytes;
    NSUInteger left = data.length;
    while (left > 0) {
        BOOL can = [self waitUntil:^BOOL{ return [_out hasSpaceAvailable] || [self broken]; } timeout:kIOTimeout];
        if (!can) { _timedOut = YES; return NO; }
        NSInteger n = [_out write:p maxLength:left];
        if (n <= 0) return NO;
        p += n; left -= n;
    }
    return YES;
}

- (BOOL)fill {
    BOOL got = [self waitUntil:^BOOL{ return [_in hasBytesAvailable] || [self broken]; } timeout:kIOTimeout];
    if (!got) { _timedOut = YES; return NO; }
    if (![_in hasBytesAvailable]) return NO;
    uint8_t tmp[4096];
    NSInteger n = [_in read:tmp maxLength:sizeof(tmp)];
    if (n <= 0) return NO;
    [_buf appendBytes:tmp length:n];
    return YES;
}

- (NSString *)readLine {
    NSData *crlf = [NSData dataWithBytes:"\r\n" length:2];
    while (YES) {
        NSRange r = [_buf rangeOfData:crlf options:0 range:NSMakeRange(0, _buf.length)];
        if (r.location != NSNotFound) {
            NSData *d = [_buf subdataWithRange:NSMakeRange(0, r.location)];
            [_buf replaceBytesInRange:NSMakeRange(0, r.location + 2) withBytes:NULL length:0];
            NSString *s = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
            return s ?: [[NSString alloc] initWithData:d encoding:NSISOLatin1StringEncoding];
        }
        if (![self fill]) return nil;
    }
}

@end
