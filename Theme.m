#import "Theme.h"
#import "AppSettings.h"

static void Poly(CGContextRef g, const CGPoint *p, int n, BOOL close) {
    CGContextBeginPath(g);
    CGContextMoveToPoint(g, p[0].x, p[0].y);
    for (int i = 1; i < n; i++) CGContextAddLineToPoint(g, p[i].x, p[i].y);
    if (close) CGContextClosePath(g);
    CGContextStrokePath(g);
}
#define POLY(close, ...) do { CGPoint _p[] = {__VA_ARGS__}; Poly(g, _p, (int)(sizeof(_p) / sizeof(_p[0])), close); } while (0)

@implementation Theme

+ (UIColor *)lime     { return [UIColor colorWithRed:0.66 green:0.85 blue:0.20 alpha:1]; }
+ (UIColor *)limeDark { return [UIColor colorWithRed:0.36 green:0.55 blue:0.05 alpha:1]; }
+ (UIColor *)ink      { return [UIColor colorWithRed:0.07 green:0.09 blue:0.08 alpha:1]; }
+ (UIColor *)menuColor{ return [UIColor colorWithRed:0.16 green:0.17 blue:0.19 alpha:1]; }

+ (UIColor *)avatarColorForString:(NSString *)s {
    static NSArray *palette;
    if (!palette) palette = @[
        [UIColor colorWithRed:0.20 green:0.60 blue:0.86 alpha:1], [UIColor colorWithRed:0.91 green:0.30 blue:0.24 alpha:1],
        [UIColor colorWithRed:0.15 green:0.68 blue:0.38 alpha:1], [UIColor colorWithRed:0.61 green:0.35 blue:0.71 alpha:1],
        [UIColor colorWithRed:0.90 green:0.49 blue:0.13 alpha:1], [UIColor colorWithRed:0.10 green:0.74 blue:0.61 alpha:1],
        [UIColor colorWithRed:0.20 green:0.29 blue:0.37 alpha:1], [UIColor colorWithRed:0.83 green:0.33 blue:0.55 alpha:1]];
    NSUInteger sum = 0;
    for (NSUInteger i = 0; i < s.length; i++) sum += [s characterAtIndex:i];
    return palette[sum % palette.count];
}

+ (UIImage *)icon:(PulseIcon)kind color:(UIColor *)color size:(CGFloat)size {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0);
    CGContextRef g = UIGraphicsGetCurrentContext();
    CGContextScaleCTM(g, size / 24.0, size / 24.0);
    CGContextSetStrokeColorWithColor(g, color.CGColor);
    CGContextSetFillColorWithColor(g, color.CGColor);
    CGContextSetLineWidth(g, 2.0);
    CGContextSetLineCap(g, kCGLineCapRound);
    CGContextSetLineJoin(g, kCGLineJoinRound);

    switch (kind) {
        case PulseIconMenu:
            POLY(NO, {3,6},{21,6}); POLY(NO, {3,12},{21,12}); POLY(NO, {3,18},{21,18}); break;
        case PulseIconSearch:
            CGContextStrokeEllipseInRect(g, CGRectMake(4, 4, 12, 12)); POLY(NO, {14,14},{20,20}); break;
        case PulseIconClose:
            POLY(NO, {5,5},{19,19}); POLY(NO, {19,5},{5,19}); break;
        case PulseIconCompose:
            POLY(YES, {16,3},{21,8},{8,21},{3,21},{3,16}); POLY(NO, {13,6},{18,11}); break;
        case PulseIconInbox:
            POLY(YES, {3,13},{6,5},{18,5},{21,13},{21,19},{3,19});
            POLY(NO, {3,13},{8,13},{9.5,16},{14.5,16},{16,13},{21,13}); break;
        case PulseIconSent:
            POLY(YES, {3,11},{21,3},{14,21},{11,13}); POLY(NO, {11,13},{21,3}); break;
        case PulseIconDrafts:
            CGContextStrokeRect(g, CGRectMake(5, 3, 14, 18));
            POLY(NO, {8,9},{16,9}); POLY(NO, {8,13},{16,13}); POLY(NO, {8,17},{13,17}); break;
        case PulseIconTrash:
            POLY(NO, {4,6},{20,6}); POLY(NO, {9,6},{9,3},{15,3},{15,6});
            POLY(NO, {6,6},{7,21},{17,21},{18,6}); POLY(NO, {10,10},{10,17}); POLY(NO, {14,10},{14,17}); break;
        case PulseIconSpam:
            CGContextStrokeEllipseInRect(g, CGRectMake(3, 3, 18, 18)); POLY(NO, {12,7},{12,13});
            CGContextFillEllipseInRect(g, CGRectMake(10.9, 15.4, 2.2, 2.2)); break;
        case PulseIconArchive:
            CGContextStrokeRect(g, CGRectMake(3, 4, 18, 5));
            POLY(NO, {5,9},{5,20},{19,20},{19,9}); POLY(NO, {10,13},{14,13}); break;
        case PulseIconFolder:
            POLY(YES, {3,6},{10,6},{12,8},{21,8},{21,19},{3,19}); break;
        case PulseIconLogout:
            POLY(NO, {10,4},{4,4},{4,20},{10,20}); POLY(NO, {9,12},{20,12}); POLY(NO, {16,8},{20,12},{16,16}); break;
        case PulseIconUp:   POLY(NO, {5,15},{12,8},{19,15}); break;
        case PulseIconDown: POLY(NO, {5,9},{12,16},{19,9}); break;
        case PulseIconSettings: {
            CGContextStrokeEllipseInRect(g, CGRectMake(9, 9, 6, 6));
            CGContextStrokeEllipseInRect(g, CGRectMake(5, 5, 14, 14));
            for (int k = 0; k < 8; k++) {
                double a = k * M_PI / 4;
                CGPoint t[] = {{(CGFloat)(12 + 7 * cos(a)), (CGFloat)(12 + 7 * sin(a))},
                               {(CGFloat)(12 + 10.5 * cos(a)), (CGFloat)(12 + 10.5 * sin(a))}};
                Poly(g, t, 2, NO);
            }
            break;
        }
        case PulseIconAdd: POLY(NO, {12,5},{12,19}); POLY(NO, {5,12},{19,12}); break;
    }
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

#pragma mark - Тема

+ (BOOL)isDark { return [AppSettings darkTheme]; }

+ (void)setDark:(BOOL)dark {
    [AppSettings setDarkTheme:dark];
    [self updateStatusBar];
}

+ (void)updateStatusBar {
    [[UIApplication sharedApplication] setStatusBarStyle:
        [self isDark] ? UIStatusBarStyleBlackOpaque : UIStatusBarStyleDefault];
}

+ (void)styleNavigationController:(UINavigationController *)nav {
    UIBarStyle st = [self isDark] ? UIBarStyleBlack : UIBarStyleDefault;
    nav.navigationBar.barStyle = st;
    nav.toolbar.barStyle = st;
    [self updateStatusBar];
}

+ (UIColor *)bg             { return [self isDark] ? [UIColor colorWithWhite:0.07 alpha:1] : [UIColor whiteColor]; }
+ (UIColor *)groupedBackground { return [self isDark] ? [UIColor colorWithWhite:0.07 alpha:1] : [UIColor groupTableViewBackgroundColor]; }
+ (UIColor *)cellBg         { return [self isDark] ? [UIColor colorWithWhite:0.13 alpha:1] : [UIColor whiteColor]; }
+ (UIColor *)headerBg       { return [self isDark] ? [UIColor colorWithWhite:0.12 alpha:1] : [UIColor colorWithWhite:0.97 alpha:1]; }
+ (UIColor *)textPrimary    { return [self isDark] ? [UIColor colorWithWhite:0.93 alpha:1] : [UIColor blackColor]; }
+ (UIColor *)textSecondary  { return [self isDark] ? [UIColor colorWithWhite:0.62 alpha:1] : [UIColor colorWithWhite:0.55 alpha:1]; }
+ (UIColor *)separator      { return [self isDark] ? [UIColor colorWithWhite:0.22 alpha:1] : [UIColor colorWithWhite:0.80 alpha:1]; }
+ (UIColor *)accent         { return [self isDark] ? [UIColor colorWithRed:0.38 green:0.64 blue:1.0 alpha:1]
                                                    : [UIColor colorWithRed:0.0 green:0.38 blue:0.85 alpha:1]; }
+ (UIColor *)fieldColor     { return [self isDark] ? [UIColor colorWithRed:0.50 green:0.70 blue:1.0 alpha:1]
                                                    : [UIColor colorWithRed:0.22 green:0.33 blue:0.53 alpha:1]; }

+ (void)styleGroupedCell:(UITableViewCell *)cell {
    cell.backgroundColor = [self cellBg];
    cell.textLabel.textColor = [self textPrimary];
    cell.detailTextLabel.textColor = [self textSecondary];
}

+ (UIColor *)groupedLabelColor {
    return [self isDark] ? [UIColor colorWithRed:0.65 green:0.67 blue:0.72 alpha:1]
                         : [UIColor colorWithRed:0.30 green:0.34 blue:0.42 alpha:1];
}

+ (UILabel *)groupedLabel:(CGRect)f font:(UIFont *)font text:(NSString *)t {
    UILabel *l = [[UILabel alloc] initWithFrame:f];
    l.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    l.backgroundColor = [UIColor clearColor];
    l.font = font;
    l.textColor = [self groupedLabelColor];
    l.shadowColor = [self isDark] ? [UIColor blackColor] : [UIColor whiteColor];
    l.shadowOffset = CGSizeMake(0, [self isDark] ? -1 : 1);
    l.text = t;
    return l;
}

+ (UIView *)groupedHeader:(NSString *)text {
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 34)];
    [v addSubview:[self groupedLabel:CGRectMake(20, 8, 280, 22) font:[UIFont boldSystemFontOfSize:17] text:text]];
    return v;
}

+ (CGFloat)groupedFooterHeight:(NSString *)text width:(CGFloat)w {
    if (!text.length) return 6;
    CGSize s = [text sizeWithFont:[UIFont systemFontOfSize:15] constrainedToSize:CGSizeMake(w - 40, 400)
                    lineBreakMode:NSLineBreakByWordWrapping];
    return s.height + 18;
}

+ (UIView *)groupedFooter:(NSString *)text width:(CGFloat)w {
    CGFloat h = [self groupedFooterHeight:text width:w];
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, h)];
    UILabel *l = [self groupedLabel:CGRectMake(20, 8, w - 40, h - 12) font:[UIFont systemFontOfSize:15] text:text];
    l.numberOfLines = 0;
    l.textAlignment = NSTextAlignmentCenter;
    [v addSubview:l];
    return v;
}

@end
