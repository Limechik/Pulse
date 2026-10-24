#import "KeychainStore.h"
#import <Security/Security.h>

static NSString *const kService = @"com.lime.pulse";

@implementation KeychainStore

+ (NSMutableDictionary *)baseQuery:(NSString *)account {
    NSMutableDictionary *q = [NSMutableDictionary dictionary];
    [q setObject:(__bridge id)kSecClassGenericPassword forKey:(__bridge id)kSecClass];
    [q setObject:kService forKey:(__bridge id)kSecAttrService];
    [q setObject:account forKey:(__bridge id)kSecAttrAccount];
    return q;
}

#pragma mark - Запасной файл

+ (NSString *)fallbackPath:(NSString *)account {
    NSString *lib = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES)[0];
    NSString *dir = [lib stringByAppendingPathComponent:@"Pulse"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES
                                               attributes:nil error:NULL];
    NSString *safe = [[account componentsSeparatedByCharactersInSet:
        [[NSCharacterSet alphanumericCharacterSet] invertedSet]] componentsJoinedByString:@"_"];
    return [dir stringByAppendingPathComponent:[safe stringByAppendingString:@".pw"]];
}

#pragma mark - API

+ (BOOL)savePassword:(NSString *)password forAccount:(NSString *)account {
    [self deletePasswordForAccount:account];
    NSData *pw = [password dataUsingEncoding:NSUTF8StringEncoding];

    NSMutableDictionary *q = [self baseQuery:account];
    [q setObject:pw forKey:(__bridge id)kSecValueData];
    [q setObject:(__bridge id)kSecAttrAccessibleAfterFirstUnlock forKey:(__bridge id)kSecAttrAccessible];
    OSStatus st = SecItemAdd((__bridge CFDictionaryRef)q, NULL);
    if (st == errSecSuccess) return YES;

    NSLog(@"Pulse: Keychain недоступен (OSStatus %d), использую запасной файл", (int)st);
    return [pw writeToFile:[self fallbackPath:account]
                   options:NSDataWritingAtomic | NSDataWritingFileProtectionComplete error:NULL];
}

+ (NSString *)passwordForAccount:(NSString *)account {
    NSMutableDictionary *q = [self baseQuery:account];
    [q setObject:(__bridge id)kCFBooleanTrue forKey:(__bridge id)kSecReturnData];
    [q setObject:(__bridge id)kSecMatchLimitOne forKey:(__bridge id)kSecMatchLimit];
    CFTypeRef result = NULL;
    NSData *data = nil;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)q, &result) == errSecSuccess && result)
        data = (__bridge_transfer NSData *)result;
    if (!data) data = [NSData dataWithContentsOfFile:[self fallbackPath:account]];
    return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
}

+ (void)deletePasswordForAccount:(NSString *)account {
    SecItemDelete((__bridge CFDictionaryRef)[self baseQuery:account]);
    [[NSFileManager defaultManager] removeItemAtPath:[self fallbackPath:account] error:NULL];
}

@end
