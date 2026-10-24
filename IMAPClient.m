#import "IMAPClient.h"
#import "Localization.h"
#import <netdb.h>
#import <arpa/inet.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <errno.h>
#import <ctype.h>

static const NSTimeInterval kConnectTimeout = 15;
static const NSTimeInterval kIOTimeout = 20;

#pragma mark - Helpers (RFC 2047)

static NSData *B64Decode(NSString *s) {
    static const char *tbl = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    NSMutableData *out = [NSMutableData data];
    uint32_t acc = 0; int bits = 0;
    for (NSUInteger i = 0; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        if (c == 0 || c > 127 || c == '=') continue;
        const char *p = strchr(tbl, (char)c);
        if (!p) continue;
        acc = (acc << 6) | (uint32_t)(p - tbl);
        bits += 6;
        if (bits >= 8) {
            bits -= 8;
            uint8_t b = (acc >> bits) & 0xFF;
            [out appendBytes:&b length:1];
        }
    }
    return out;
}

static NSData *QDecode(NSString *s) {
    NSMutableData *out = [NSMutableData data];
    for (NSUInteger i = 0; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        uint8_t b;
        if (c == '_') b = ' ';
        else if (c == '=' && i + 2 < s.length) {
            b = (uint8_t)strtol([[s substringWithRange:NSMakeRange(i + 1, 2)] UTF8String], NULL, 16);
            i += 2;
        } else b = (uint8_t)c;
        [out appendBytes:&b length:1];
    }
    return out;
}

static NSString *Decode2047(NSString *s) {
    NSRegularExpression *re = [NSRegularExpression
        regularExpressionWithPattern:@"=\\?([^?]+)\\?([bBqQ])\\?([^?]*)\\?="
                             options:0 error:NULL];
    NSArray *matches = [re matchesInString:s options:0 range:NSMakeRange(0, s.length)];
    if (!matches.count) return s;
    NSMutableString *out = [NSMutableString string];
    NSUInteger last = 0;
    BOOL first = YES;
    for (NSTextCheckingResult *m in matches) {
        NSString *gap = [s substringWithRange:NSMakeRange(last, m.range.location - last)];
        // пробелы между закодированными словами игнорируются
        if (!first && [[gap stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] length] == 0) gap = @"";
        [out appendString:gap];
        NSString *cs = [s substringWithRange:[m rangeAtIndex:1]];
        NSString *enc = [[s substringWithRange:[m rangeAtIndex:2]] uppercaseString];
        NSString *txt = [s substringWithRange:[m rangeAtIndex:3]];
        NSData *data = [enc isEqualToString:@"B"] ? B64Decode(txt) : QDecode(txt);
        CFStringEncoding cf = CFStringConvertIANACharSetNameToEncoding((__bridge CFStringRef)cs);
        NSStringEncoding ns = (cf == kCFStringEncodingInvalidId)
            ? NSUTF8StringEncoding : CFStringConvertEncodingToNSStringEncoding(cf);
        NSString *dec = [[NSString alloc] initWithData:data encoding:ns];
        [out appendString:dec ?: @""];
        last = m.range.location + m.range.length;
        first = NO;
    }
    [out appendString:[s substringFromIndex:last]];
    return out;
}

static NSData *QPBody(NSString *s) {
    NSMutableData *out = [NSMutableData data];
    NSUInteger n = s.length;
    for (NSUInteger i = 0; i < n; i++) {
        unichar c = [s characterAtIndex:i];
        if (c == '=') {
            if (i + 1 < n) {
                unichar d = [s characterAtIndex:i + 1];
                if (d == '\r' || d == '\n') {
                    i++;
                    if (d == '\r' && i + 1 < n && [s characterAtIndex:i + 1] == '\n') i++;
                    continue;
                }
            }
            if (i + 2 < n) {
                char hex[3] = {(char)[s characterAtIndex:i + 1], (char)[s characterAtIndex:i + 2], 0};
                uint8_t b = (uint8_t)strtol(hex, NULL, 16);
                [out appendBytes:&b length:1];
                i += 2;
            }
            continue;
        }
        if (c < 128) { uint8_t b = (uint8_t)c; [out appendBytes:&b length:1]; }
        else [out appendData:[[s substringWithRange:NSMakeRange(i, 1)] dataUsingEncoding:NSUTF8StringEncoding]];
    }
    return out;
}

static NSString *UTF8Lenient(NSData *d) {
    for (int k = 0; k <= 3 && d.length > (NSUInteger)k; k++) {
        NSString *t = [[NSString alloc] initWithData:[d subdataWithRange:NSMakeRange(0, d.length - k)]
                                            encoding:NSUTF8StringEncoding];
        if (t) return t;
    }
    return nil;
}

// Грубое превью: base64 / quoted-printable / HTML -> обычный текст
static NSString *MakePreview(NSData *raw) {
    if (!raw.length) return @"";
    NSString *s = UTF8Lenient(raw);
    if (!s) s = [[NSString alloc] initWithData:raw encoding:NSISOLatin1StringEncoding];
    if (!s) return @"";
    if ([s hasPrefix:@"--"]) {
        NSRange r = [s rangeOfString:@"\r\n\r\n"];
        if (r.location == NSNotFound) return @"";
        s = [s substringFromIndex:r.location + 4];
    }
    NSString *compact = [[s componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
                         componentsJoinedByString:@""];
    NSCharacterSet *b64 = [NSCharacterSet characterSetWithCharactersInString:
        @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/="];
    if (compact.length >= 16 && [compact rangeOfCharacterFromSet:[b64 invertedSet]].location == NSNotFound) {
        NSString *t = UTF8Lenient(B64Decode(compact));
        if (t) s = t;
    } else if ([s rangeOfString:@"=[0-9A-F]{2}|=\\r?\\n" options:NSRegularExpressionSearch].location != NSNotFound) {
        NSString *t = UTF8Lenient(QPBody(s));
        if (t) s = t;
    }
    s = [s stringByReplacingOccurrencesOfString:@"<[^>]+>" withString:@" "
                                        options:NSRegularExpressionSearch range:NSMakeRange(0, s.length)];
    s = [s stringByReplacingOccurrencesOfString:@"\\s+" withString:@" "
                                        options:NSRegularExpressionSearch range:NSMakeRange(0, s.length)];
    s = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return s.length > 200 ? [s substringToIndex:200] : s;
}

static NSDictionary *ParseHeaders(NSData *d) {
    NSString *s = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
    if (!s) s = [[NSString alloc] initWithData:d encoding:NSISOLatin1StringEncoding];
    s = [s stringByReplacingOccurrencesOfString:@"\r\n " withString:@" "];
    s = [s stringByReplacingOccurrencesOfString:@"\r\n\t" withString:@" "];
    NSMutableDictionary *h = [NSMutableDictionary dictionary];
    for (NSString *line in [s componentsSeparatedByString:@"\r\n"]) {
        NSRange r = [line rangeOfString:@":"];
        if (r.location == NSNotFound) continue;
        NSString *key = [[line substringToIndex:r.location] lowercaseString];
        NSString *val = [[line substringFromIndex:r.location + 1]
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        [h setObject:Decode2047(val) forKey:key];
    }
    return h;
}

static NSString *SenderName(NSString *from) {
    if (!from.length) return @"";
    NSCharacterSet *trim = [NSCharacterSet characterSetWithCharactersInString:@" \t\"'"];
    NSRange lt = [from rangeOfString:@"<"];
    NSString *name = (lt.location != NSNotFound) ? [from substringToIndex:lt.location] : from;
    name = [name stringByTrimmingCharactersInSet:trim];
    if (!name.length) name = [from stringByTrimmingCharactersInSet:
                              [NSCharacterSet characterSetWithCharactersInString:@" <>"]];
    return name;
}

static NSDate *ParseDate(NSString *s) {
    if (!s.length) return nil;
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    NSString *c = [s stringByReplacingOccurrencesOfString:@"\\s*\\(.*\\)\\s*$" withString:@""
                                                  options:NSRegularExpressionSearch range:NSMakeRange(0, s.length)];
    for (NSString *f in @[@"EEE, d MMM yyyy HH:mm:ss Z", @"d MMM yyyy HH:mm:ss Z",
                          @"EEE, d MMM yyyy HH:mm Z", @"EEE, d MMM yy HH:mm:ss Z"]) {
        df.dateFormat = f;
        NSDate *d = [df dateFromString:c];
        if (d) return d;
    }
    return nil;
}

static NSString *DecodeMUTF7(NSString *s) {
    if ([s rangeOfString:@"&"].location == NSNotFound) return s;
    NSMutableString *out = [NSMutableString string];
    NSUInteger i = 0, n = s.length;
    while (i < n) {
        unichar c = [s characterAtIndex:i];
        if (c != '&') { [out appendFormat:@"%C", c]; i++; continue; }
        NSRange end = [s rangeOfString:@"-" options:0 range:NSMakeRange(i + 1, n - i - 1)];
        if (end.location == NSNotFound) { [out appendString:[s substringFromIndex:i]]; break; }
        NSString *enc = [s substringWithRange:NSMakeRange(i + 1, end.location - i - 1)];
        if (!enc.length) [out appendString:@"&"];
        else {
            NSString *b = [enc stringByReplacingOccurrencesOfString:@"," withString:@"/"];
            NSString *dec = [[NSString alloc] initWithData:B64Decode(b) encoding:NSUTF16BigEndianStringEncoding];
            if (dec) [out appendString:dec];
        }
        i = end.location + 1;
    }
    return out;
}

#pragma mark - MIME / BODYSTRUCTURE

static id ParseSexp(NSString *s, NSUInteger *pos) {
    NSUInteger n = s.length;
    while (*pos < n && [s characterAtIndex:*pos] == ' ') (*pos)++;
    if (*pos >= n) return nil;
    unichar c = [s characterAtIndex:*pos];
    if (c == '(') {
        (*pos)++;
        NSMutableArray *arr = [NSMutableArray array];
        while (*pos < n) {
            while (*pos < n && [s characterAtIndex:*pos] == ' ') (*pos)++;
            if (*pos >= n) break;
            if ([s characterAtIndex:*pos] == ')') { (*pos)++; return arr; }
            id item = ParseSexp(s, pos);
            if (!item) break;
            [arr addObject:item];
        }
        return arr;
    }
    if (c == '"') {
        (*pos)++;
        NSMutableString *str = [NSMutableString string];
        while (*pos < n) {
            unichar d = [s characterAtIndex:*pos];
            if (d == '\\' && *pos + 1 < n) { [str appendFormat:@"%C", [s characterAtIndex:*pos + 1]]; *pos += 2; continue; }
            if (d == '"') { (*pos)++; break; }
            [str appendFormat:@"%C", d];
            (*pos)++;
        }
        return str;
    }
    NSUInteger st = *pos;
    while (*pos < n) {
        unichar d = [s characterAtIndex:*pos];
        if (d == ' ' || d == '(' || d == ')') break;
        (*pos)++;
    }
    if (*pos == st) { (*pos)++; return [NSNull null]; }
    NSString *atom = [s substringWithRange:NSMakeRange(st, *pos - st)];
    if ([atom caseInsensitiveCompare:@"NIL"] == NSOrderedSame) return [NSNull null];
    return atom;
}

static NSString *StrAt(NSArray *a, NSUInteger i) {
    return (i < a.count && [a[i] isKindOfClass:[NSString class]]) ? a[i] : @"";
}

static NSDictionary *ParamDict(id list) {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    if (![list isKindOfClass:[NSArray class]]) return d;
    NSArray *a = list;
    for (NSUInteger i = 0; i + 1 < a.count; i += 2) {
        if ([a[i] isKindOfClass:[NSString class]] && [a[i + 1] isKindOfClass:[NSString class]])
            d[[a[i] lowercaseString]] = a[i + 1];
    }
    return d;
}

static void CollectParts(NSArray *node, NSString *prefix, NSMutableArray *out) {
    if (node.count && [node[0] isKindOfClass:[NSArray class]]) {      // multipart
        int i = 1;
        for (id child in node) {
            if (![child isKindOfClass:[NSArray class]]) break;
            NSString *num = prefix.length ? [NSString stringWithFormat:@"%@.%d", prefix, i]
                                          : [NSString stringWithFormat:@"%d", i];
            CollectParts(child, num, out);
            i++;
        }
        return;
    }
    if (node.count < 7) return;
    NSDictionary *params = ParamDict(node[2]);
    NSString *disp = @"", *filename = params[@"name"] ?: @"";
    for (NSUInteger i = 7; i < node.count; i++) {
        if ([node[i] isKindOfClass:[NSArray class]]) {
            NSArray *dl = node[i];
            NSString *kind = [StrAt(dl, 0) lowercaseString];
            if ([kind isEqualToString:@"attachment"] || [kind isEqualToString:@"inline"]) {
                disp = kind;
                NSString *fn = ParamDict(dl.count > 1 ? dl[1] : nil)[@"filename"];
                if (fn.length) filename = fn;
                break;
            }
        }
    }
    [out addObject:@{@"part": prefix.length ? prefix : @"1",
                     @"type": [StrAt(node, 0) lowercaseString],
                     @"subtype": [StrAt(node, 1) lowercaseString],
                     @"charset": params[@"charset"] ?: @"",
                     @"encoding": [StrAt(node, 5) lowercaseString],
                     @"size": @([StrAt(node, 6) intValue]),
                     @"disposition": disp,
                     @"filename": Decode2047(filename)}];
}

static NSData *QPDecodeBytes(NSData *d) {
    const uint8_t *p = d.bytes;
    NSUInteger n = d.length;
    NSMutableData *out = [NSMutableData dataWithCapacity:n];
    for (NSUInteger i = 0; i < n; i++) {
        uint8_t c = p[i];
        if (c == '=') {
            if (i + 1 < n && (p[i + 1] == '\r' || p[i + 1] == '\n')) {
                i++;
                if (p[i] == '\r' && i + 1 < n && p[i + 1] == '\n') i++;
                continue;
            }
            if (i + 2 < n && isxdigit(p[i + 1]) && isxdigit(p[i + 2])) {
                char hex[3] = {(char)p[i + 1], (char)p[i + 2], 0};
                uint8_t b = (uint8_t)strtol(hex, NULL, 16);
                [out appendBytes:&b length:1];
                i += 2;
                continue;
            }
        }
        [out appendBytes:&c length:1];
    }
    return out;
}

static NSString *DecodeBody(NSData *raw, NSString *enc, NSString *charset) {
    NSData *bytes = raw;
    if ([enc isEqualToString:@"base64"]) {
        NSString *s = [[NSString alloc] initWithData:raw encoding:NSASCIIStringEncoding]
                   ?: [[NSString alloc] initWithData:raw encoding:NSISOLatin1StringEncoding];
        bytes = B64Decode(s ?: @"");
    } else if ([enc isEqualToString:@"quoted-printable"]) {
        bytes = QPDecodeBytes(raw);
    }
    NSStringEncoding e = NSUTF8StringEncoding;
    if (charset.length) {
        CFStringEncoding cf = CFStringConvertIANACharSetNameToEncoding((__bridge CFStringRef)charset);
        if (cf != kCFStringEncodingInvalidId) e = CFStringConvertEncodingToNSStringEncoding(cf);
    }
    NSString *str = [[NSString alloc] initWithData:bytes encoding:e];
    if (!str) str = UTF8Lenient(bytes);
    if (!str) str = [[NSString alloc] initWithData:bytes encoding:NSISOLatin1StringEncoding];
    return str ?: @"";
}

static NSString *AddressNames(NSString *list) {
    if (!list.length) return @"";
    NSMutableArray *names = [NSMutableArray array];
    NSMutableString *cur = [NSMutableString string];
    BOOL inQ = NO; int depth = 0;
    for (NSUInteger i = 0; i <= list.length; i++) {
        unichar c = i < list.length ? [list characterAtIndex:i] : ',';
        if (i < list.length) {
            if (c == '"') inQ = !inQ;
            else if (!inQ && c == '<') depth++;
            else if (!inQ && c == '>') depth--;
        }
        if (c == ',' && (i == list.length || (!inQ && depth <= 0))) {
            NSString *t = [cur stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (t.length) [names addObject:SenderName(t)];
            [cur setString:@""];
        } else {
            [cur appendFormat:@"%C", c];
        }
    }
    return [names componentsJoinedByString:@", "];
}

static NSString *AddrOnly(NSString *from) {
    NSRange a = [from rangeOfString:@"<"], b = [from rangeOfString:@">" options:NSBackwardsSearch];
    if (a.location != NSNotFound && b.location != NSNotFound && b.location > a.location)
        return [from substringWithRange:NSMakeRange(a.location + 1, b.location - a.location - 1)];
    return @"";
}

static NSArray *SplitAddresses(NSString *list) {
    NSMutableArray *parts = [NSMutableArray array];
    if (!list.length) return parts;
    NSMutableString *cur = [NSMutableString string];
    BOOL inQ = NO; int depth = 0;
    for (NSUInteger i = 0; i <= list.length; i++) {
        unichar c = i < list.length ? [list characterAtIndex:i] : ',';
        if (i < list.length) {
            if (c == '"') inQ = !inQ;
            else if (!inQ && c == '<') depth++;
            else if (!inQ && c == '>') depth--;
        }
        if (c == ',' && (i == list.length || (!inQ && depth <= 0))) {
            NSString *t = [cur stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (t.length) [parts addObject:t];
            [cur setString:@""];
        } else {
            [cur appendFormat:@"%C", c];
        }
    }
    return parts;
}

static NSArray *AddressEmails(NSString *list) {
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *p in SplitAddresses(list)) {
        NSString *a = AddrOnly(p);
        if (!a.length && [p rangeOfString:@"@"].location != NSNotFound) a = p;
        if (a.length) [out addObject:a];
    }
    return out;
}

static NSString *RegexReplace(NSString *s, NSString *pattern, NSString *tmpl, NSRegularExpressionOptions opts) {
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern options:opts error:NULL];
    return re ? [re stringByReplacingMatchesInString:s options:0 range:NSMakeRange(0, s.length) withTemplate:tmpl] : s;
}

static NSString *HTMLToText(NSString *h) {
    NSRegularExpressionOptions ci = NSRegularExpressionCaseInsensitive | NSRegularExpressionDotMatchesLineSeparators;
    NSString *s = RegexReplace(h, @"<(style|script)[^>]*>.*?</\\1>", @"", ci);
    s = RegexReplace(s, @"<br\\s*/?>|</p>|</div>|</tr>|</li>|</h[1-6]>", @"\n", ci);
    s = RegexReplace(s, @"<[^>]+>", @"", 0);
    s = [s stringByReplacingOccurrencesOfString:@"&nbsp;" withString:@" "];
    s = [s stringByReplacingOccurrencesOfString:@"&lt;" withString:@"<"];
    s = [s stringByReplacingOccurrencesOfString:@"&gt;" withString:@">"];
    s = [s stringByReplacingOccurrencesOfString:@"&quot;" withString:@"\""];
    s = [s stringByReplacingOccurrencesOfString:@"&#39;" withString:@"'"];
    s = [s stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
    s = RegexReplace(s, @"[ \\t]+\\n", @"\n", 0);
    s = RegexReplace(s, @"\\n{3,}", @"\n\n", 0);
    return [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

#pragma mark - Client

@implementation IMAPClient {
    NSInputStream *_in;
    NSOutputStream *_out;
    NSRunLoop *_loop;
    NSMutableData *_buf;
    BOOL _timedOut;
    BOOL _transient;
    int _tag;
}

- (BOOL)connectToHost:(NSString *)host port:(int)port error:(NSString **)error {
    NSString *err = nil;
    for (int attempt = 0; attempt < 3; attempt++) {
        if (attempt > 0) [NSThread sleepForTimeInterval:1.5];
        err = nil;
        _transient = NO;
        if ([self openToHost:host port:port error:&err]) return YES;
        [self disconnect];
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
    struct sockaddr_in *sin = (struct sockaddr_in *)res->ai_addr;
    inet_ntop(AF_INET, &sin->sin_addr, buf, sizeof(buf));
    freeaddrinfo(res);
    return [NSString stringWithUTF8String:buf];
}

- (void)markTransientIfNetworkError {
    NSError *e = _in.streamError ?: _out.streamError;
    if ([e.domain isEqualToString:NSPOSIXErrorDomain] &&
        (e.code == ENETDOWN || e.code == ENETUNREACH || e.code == EHOSTUNREACH)) _transient = YES;
}

- (BOOL)openToHost:(NSString *)host port:(int)port error:(NSString **)error {
    _buf = [NSMutableData data];
    _timedOut = NO;

    // iOS 6 не умеет «happy eyeballs»: если у хоста есть IPv6-адрес, а сети IPv6 нет,
    // получаем «Network is down» (POSIX 50). Поэтому подключаемся строго по IPv4.
    NSString *ip = [self resolveIPv4:host];
    if (!ip) {
        _transient = YES;
        if (error) *error = [NSString stringWithFormat:
            L(@"Не удалось найти сервер %@ (DNS). Проверьте подключение к интернету."), host];
        return NO;
    }

    CFReadStreamRef r = NULL; CFWriteStreamRef w = NULL;
    CFStreamCreatePairWithSocketToHost(NULL, (__bridge CFStringRef)ip, port, &r, &w);
    if (!r || !w) { if (error) *error = L(@"Не удалось создать соединение"); return NO; }
    _in = (__bridge_transfer NSInputStream *)r;
    _out = (__bridge_transfer NSOutputStream *)w;

    [_in setProperty:NSStreamSocketSecurityLevelNegotiatedSSL forKey:NSStreamSocketSecurityLevelKey];
    [_out setProperty:NSStreamSocketSecurityLevelNegotiatedSSL forKey:NSStreamSocketSecurityLevelKey];
    // Проверяем сертификат по имени хоста, а не по IP
    NSDictionary *ssl = @{(__bridge id)kCFStreamSSLPeerName: host};
    CFReadStreamSetProperty((__bridge CFReadStreamRef)_in, kCFStreamPropertySSLSettings, (__bridge CFTypeRef)ssl);
    CFWriteStreamSetProperty((__bridge CFWriteStreamRef)_out, kCFStreamPropertySSLSettings, (__bridge CFTypeRef)ssl);

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

    NSString *greeting = [self readLine];
    if (![greeting hasPrefix:@"* OK"]) {
        [self markTransientIfNetworkError];
        if (error) *error = greeting ? [L(@"Неожиданный ответ сервера: ") stringByAppendingString:greeting] : [self lastError];
        return NO;
    }
    return YES;
}

- (BOOL)loginWithUser:(NSString *)user password:(NSString *)password error:(NSString **)error {
    NSString *cmd = [NSString stringWithFormat:@"LOGIN \"%@\" \"%@\"", [self quote:user], [self quote:password]];
    BOOL ok = NO;
    NSArray *res = [self command:cmd ok:&ok];
    if (!ok && error) {
        NSString *last = [res lastObject];
        *error = [last isKindOfClass:[NSString class]]
            ? [L(@"Сервер отклонил вход: ") stringByAppendingString:last] : [self lastError];
    }
    return ok;
}

- (NSArray *)fetchLatest:(int)count inFolder:(NSString *)path error:(NSString **)error {
    BOOL ok = NO;
    NSArray *sel = [self command:[NSString stringWithFormat:@"SELECT \"%@\"", [self quote:path]] ok:&ok];
    if (!ok) { if (error) *error = [self lastError]; return nil; }
    int exists = 0;
    for (id it in sel) {
        int n;
        if ([it isKindOfClass:[NSString class]] && sscanf([it UTF8String], "* %d EXISTS", &n) == 1) exists = n;
    }
    if (exists == 0) return @[];

    int from = MAX(1, exists - count + 1);
    NSString *cmd = [NSString stringWithFormat:
        @"FETCH %d:%d (UID FLAGS BODY.PEEK[HEADER.FIELDS (FROM SUBJECT DATE)] BODY.PEEK[1]<0.400>)", from, exists];
    NSArray *items = [self command:cmd ok:&ok];
    if (!ok) { if (error) *error = [self lastError]; return nil; }

    NSMutableArray *msgs = [NSMutableArray array];
    NSMutableDictionary *cur = nil;
    NSString *last = @"";
    NSRegularExpression *uidRe = [NSRegularExpression regularExpressionWithPattern:@"UID (\\d+)" options:0 error:NULL];
    for (id it in items) {
        if ([it isKindOfClass:[NSString class]]) {
            int n;
            if (sscanf([it UTF8String], "* %d FETCH", &n) == 1) {
                cur = [NSMutableDictionary dictionary];
                cur[@"seq"] = @(n);
                cur[@"seen"] = @NO;
                cur[@"preview"] = @"";
                cur[@"subject"] = L(@"(без темы)");
                cur[@"from"] = @"";
                [msgs addObject:cur];
            }
            if (cur && [it rangeOfString:@"FLAGS ("].location != NSNotFound)
                cur[@"seen"] = @([it rangeOfString:@"\\Seen"].location != NSNotFound);
            if (cur && !cur[@"uid"]) {
                NSTextCheckingResult *um = [uidRe firstMatchInString:it options:0 range:NSMakeRange(0, [it length])];
                if (um) cur[@"uid"] = [it substringWithRange:[um rangeAtIndex:1]];
            }
            last = it;
        } else if (cur) {
            if ([last rangeOfString:@"BODY[HEADER"].location != NSNotFound) {
                NSDictionary *h = ParseHeaders(it);
                if ([h[@"subject"] length]) cur[@"subject"] = h[@"subject"];
                cur[@"from"] = SenderName(h[@"from"]);
                NSDate *d = ParseDate(h[@"date"]);
                if (d) cur[@"date"] = d;
            } else if ([last rangeOfString:@"BODY[1]"].location != NSNotFound) {
                cur[@"preview"] = MakePreview(it);
            }
        }
    }
    return [[msgs reverseObjectEnumerator] allObjects];
}

- (NSArray *)listFolders:(NSString **)error {
    BOOL ok = NO;
    NSArray *items = [self command:@"LIST \"\" \"*\"" ok:&ok];
    if (!ok) { if (error) *error = [self lastError]; return nil; }
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:
        @"^\\* LIST \\(([^)]*)\\) (?:\"((?:[^\"\\\\]|\\\\.)*)\"|NIL) (.+)$" options:0 error:NULL];
    NSDictionary *map = @{@"\\sent": @"sent", @"\\drafts": @"drafts", @"\\trash": @"trash",
                          @"\\junk": @"junk", @"\\archive": @"archive", @"\\all": @"all", @"\\flagged": @"flagged"};
    NSMutableArray *out = [NSMutableArray array];
    for (id it in items) {
        if (![it isKindOfClass:[NSString class]]) continue;
        NSTextCheckingResult *m = [re firstMatchInString:it options:0 range:NSMakeRange(0, [it length])];
        if (!m) continue;
        NSString *flags = [[it substringWithRange:[m rangeAtIndex:1]] lowercaseString];
        NSString *delim = [m rangeAtIndex:2].location != NSNotFound ? [it substringWithRange:[m rangeAtIndex:2]] : @"";
        NSString *name = [[it substringWithRange:[m rangeAtIndex:3]]
                          stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([name hasPrefix:@"{"]) continue;
        if (name.length >= 2 && [name hasPrefix:@"\""] && [name hasSuffix:@"\""]) {
            name = [name substringWithRange:NSMakeRange(1, name.length - 2)];
            name = [name stringByReplacingOccurrencesOfString:@"\\\"" withString:@"\""];
            name = [name stringByReplacingOccurrencesOfString:@"\\\\" withString:@"\\"];
        }
        if ([flags rangeOfString:@"\\noselect"].location != NSNotFound ||
            [flags rangeOfString:@"\\nonexistent"].location != NSNotFound) continue;
        NSString *special = @"";
        for (NSString *k in map) {
            if ([flags rangeOfString:k].location != NSNotFound) { special = map[k]; break; }
        }
        NSString *last = delim.length ? [[name componentsSeparatedByString:delim] lastObject] : name;
        [out addObject:@{@"path": name, @"displayName": DecodeMUTF7(last), @"special": special}];
    }
    return out;
}

- (NSDictionary *)fetchMessageUID:(NSString *)uid inFolder:(NSString *)path markSeen:(BOOL)mark error:(NSString **)error {
    BOOL ok = NO;
    [self command:[NSString stringWithFormat:@"SELECT \"%@\"", [self quote:path]] ok:&ok];
    if (!ok) { if (error) *error = [self lastError]; return nil; }

    NSString *cmd = [NSString stringWithFormat:
        @"UID FETCH %@ (BODYSTRUCTURE BODY.PEEK[HEADER.FIELDS (FROM TO CC SUBJECT DATE REPLY-TO MESSAGE-ID REFERENCES)])", uid];
    NSArray *items = [self command:cmd ok:&ok];
    if (!ok) { if (error) *error = [self lastError]; return nil; }

    NSData *hdr = nil;
    NSString *bs = nil;
    for (id it in items) {
        if ([it isKindOfClass:[NSData class]]) { if (!hdr) hdr = it; continue; }
        NSRange r = [it rangeOfString:@"BODYSTRUCTURE "];
        if (r.location != NSNotFound && !bs) bs = [it substringFromIndex:r.location + r.length];
    }
    NSDictionary *h = hdr ? ParseHeaders(hdr) : @{};

    NSMutableArray *parts = [NSMutableArray array];
    if (bs) {
        NSUInteger pos = 0;
        id root = ParseSexp(bs, &pos);
        if ([root isKindOfClass:[NSArray class]]) CollectParts(root, @"", parts);
    }

    // Выбираем тело: HTML в приоритете, иначе простой текст
    NSDictionary *html = nil, *plain = nil;
    NSMutableArray *atts = [NSMutableArray array];
    for (NSDictionary *p in parts) {
        BOOL text = [p[@"type"] isEqualToString:@"text"];
        BOOL att = [p[@"disposition"] isEqualToString:@"attachment"];
        if (text && !att && [p[@"subtype"] isEqualToString:@"html"] && !html) html = p;
        else if (text && !att && [p[@"subtype"] isEqualToString:@"plain"] && !plain) plain = p;
        else {
            NSString *name = [p[@"filename"] length] ? p[@"filename"]
                           : [NSString stringWithFormat:@"%@/%@", p[@"type"], p[@"subtype"]];
            [atts addObject:@{@"name": name, @"size": p[@"size"]}];
        }
    }
    NSDictionary *chosen = html ?: plain;
    if (!chosen && !parts.count)
        chosen = @{@"part": @"1", @"subtype": @"plain", @"encoding": @"", @"charset": @""};

    NSString *body = @"";
    if (chosen) {
        NSString *c2 = [NSString stringWithFormat:@"UID FETCH %@ (BODY.PEEK[%@]<0.600000>)", uid, chosen[@"part"]];
        NSArray *bi = [self command:c2 ok:&ok];
        NSData *raw = nil;
        for (id it in bi) if ([it isKindOfClass:[NSData class]]) { raw = it; break; }
        if (raw) body = DecodeBody(raw, chosen[@"encoding"], chosen[@"charset"]);
    }

    if (mark) {
        BOOL ok2 = NO;
        [self command:[NSString stringWithFormat:@"UID STORE %@ +FLAGS.SILENT (\\Seen)", uid] ok:&ok2];
    }

    NSMutableDictionary *res = [NSMutableDictionary dictionary];
    res[@"from"] = SenderName(h[@"from"] ?: @"");
    res[@"fromAddress"] = AddrOnly(h[@"from"] ?: @"");
    res[@"to"] = AddressNames(h[@"to"]);
    res[@"cc"] = AddressNames(h[@"cc"]);
    res[@"subject"] = h[@"subject"] ?: L(@"(без темы)");
    NSDate *d = ParseDate(h[@"date"]);
    if (d) res[@"date"] = d;
    res[@"body"] = body;
    res[@"html"] = @(chosen && html != nil);
    NSArray *rt = AddressEmails(h[@"reply-to"]);
    res[@"replyTo"] = rt.count ? rt[0] : @"";
    res[@"toAddrs"] = AddressEmails(h[@"to"]);
    res[@"ccAddrs"] = AddressEmails(h[@"cc"]);
    res[@"messageId"] = [h[@"message-id"] ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    res[@"references"] = h[@"references"] ?: @"";
    res[@"text"] = (chosen && html != nil) ? HTMLToText(body) : body;
    res[@"attachments"] = atts;
    return res;
}

- (void)disconnect {
    if (_out && ![self broken] && [_out hasSpaceAvailable]) {
        NSData *d = [@"A999 LOGOUT\r\n" dataUsingEncoding:NSUTF8StringEncoding];
        [_out write:d.bytes maxLength:d.length];
    }
    if (_loop) {
        [_in removeFromRunLoop:_loop forMode:NSDefaultRunLoopMode];
        [_out removeFromRunLoop:_loop forMode:NSDefaultRunLoopMode];
    }
    [_in close]; [_out close];
    _in = nil; _out = nil;
}

#pragma mark - Low level

- (NSString *)lastError {
    NSError *e = _in.streamError ?: _out.streamError;
    if (e) {
        if ([e.domain isEqualToString:NSPOSIXErrorDomain] &&
            (e.code == ENETDOWN || e.code == ENETUNREACH || e.code == EHOSTUNREACH))
            return [NSString stringWithFormat:L(@"Нет доступа к сети (%@ %ld). Проверьте Wi-Fi или мобильный интернет и режим полёта."),
                    e.domain, (long)e.code];
        return [NSString stringWithFormat:L(@"Ошибка соединения: %@ (%@ %ld)"),
                e.localizedDescription, e.domain, (long)e.code];
    }
    if (_timedOut) return L(@"Сервер не отвечает (тайм-аут). Проверьте интернет; возможно, TLS-совместимость iOS 6.");
    return L(@"Соединение закрыто сервером");
}

- (BOOL)broken {
    NSStreamStatus s = _in.streamStatus;
    return s == NSStreamStatusError || s == NSStreamStatusClosed || s == NSStreamStatusAtEnd
        || _out.streamStatus == NSStreamStatusError;
}

// Крутит run loop короткими кусками, пока условие не выполнится или не истечёт время.
- (BOOL)waitUntil:(BOOL (^)(void))cond timeout:(NSTimeInterval)t {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:t];
    while (!cond()) {
        if ([deadline timeIntervalSinceNow] <= 0) return NO;
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    return YES;
}

- (NSString *)quote:(NSString *)s {
    s = [s stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    return [s stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
}

- (NSArray *)command:(NSString *)cmd ok:(BOOL *)ok {
    NSString *tag = [NSString stringWithFormat:@"A%03d", ++_tag];
    NSData *line = [[NSString stringWithFormat:@"%@ %@\r\n", tag, cmd] dataUsingEncoding:NSUTF8StringEncoding];
    if (ok) *ok = NO;
    if (![self writeAll:line]) return @[];

    NSMutableArray *items = [NSMutableArray array];
    while (YES) {
        NSString *l = [self readLine];
        if (!l) return items;
        if ([l hasPrefix:[tag stringByAppendingString:@" "]]) {
            if (ok) *ok = [l hasPrefix:[tag stringByAppendingString:@" OK"]];
            [items addObject:l];
            return items;
        }
        [items addObject:l];
        NSRange b = [l rangeOfString:@"{" options:NSBackwardsSearch];
        if ([l hasSuffix:@"}"] && b.location != NSNotFound) {
            NSInteger n = [[l substringWithRange:NSMakeRange(b.location + 1, l.length - b.location - 2)] integerValue];
            NSData *lit = [self readData:n];
            if (!lit) return items;
            [items addObject:lit];
        }
    }
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

- (NSData *)readData:(NSInteger)n {
    while ((NSInteger)_buf.length < n) {
        if (![self fill]) return nil;
    }
    NSData *d = [_buf subdataWithRange:NSMakeRange(0, n)];
    [_buf replaceBytesInRange:NSMakeRange(0, n) withBytes:NULL length:0];
    return d;
}

@end
