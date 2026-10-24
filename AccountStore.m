#import "AccountStore.h"
#import "KeychainStore.h"

static NSString *const kAccounts = @"accounts";
static NSString *const kActive = @"activeAccount";

@implementation AccountStore

+ (NSArray *)accounts {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (![d objectForKey:kAccounts]) {      // перенос из старой версии с одним аккаунтом
        NSString *legacy = [d stringForKey:@"email"];
        if (legacy.length) {
            [d setObject:@[@{@"email": legacy, @"providerIndex": @([d integerForKey:@"providerIndex"])}] forKey:kAccounts];
            [d setInteger:0 forKey:kActive];
        }
        [d removeObjectForKey:@"email"];
        [d removeObjectForKey:@"providerIndex"];
        [d synchronize];
    }
    return [d arrayForKey:kAccounts] ?: @[];
}

+ (NSInteger)activeIndex {
    NSArray *a = [self accounts];
    NSInteger i = [[NSUserDefaults standardUserDefaults] integerForKey:kActive];
    return (i >= 0 && i < (NSInteger)a.count) ? i : 0;
}

+ (NSDictionary *)activeAccount {
    NSArray *a = [self accounts];
    return a.count ? a[[self activeIndex]] : nil;
}

+ (NSString *)activeEmail { return [self activeAccount][@"email"]; }
+ (NSInteger)activeProviderIndex { return [[self activeAccount][@"providerIndex"] integerValue]; }

+ (void)setActiveIndex:(NSInteger)index {
    [[NSUserDefaults standardUserDefaults] setInteger:index forKey:kActive];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

+ (void)addAccount:(NSString *)email providerIndex:(NSInteger)providerIndex {
    NSMutableArray *a = [[self accounts] mutableCopy];
    NSInteger found = NSNotFound;
    for (NSUInteger i = 0; i < a.count; i++)
        if ([a[i][@"email"] caseInsensitiveCompare:email] == NSOrderedSame) { found = i; break; }
    NSDictionary *acc = @{@"email": email, @"providerIndex": @(providerIndex)};
    if (found != NSNotFound) a[found] = acc;
    else { [a addObject:acc]; found = a.count - 1; }
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setObject:a forKey:kAccounts];
    [d setInteger:found forKey:kActive];
    [d synchronize];
}

+ (void)removeActiveAccount {
    NSMutableArray *a = [[self accounts] mutableCopy];
    if (!a.count) return;
    NSInteger i = [self activeIndex];
    [KeychainStore deletePasswordForAccount:a[i][@"email"]];
    [a removeObjectAtIndex:i];
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setObject:a forKey:kAccounts];
    [d setInteger:0 forKey:kActive];
    [d synchronize];
}

@end
