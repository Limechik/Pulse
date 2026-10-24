#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

typedef NS_ENUM(NSInteger, PulseIcon) {
    PulseIconMenu, PulseIconSearch, PulseIconClose, PulseIconCompose,
    PulseIconInbox, PulseIconSent, PulseIconDrafts, PulseIconTrash,
    PulseIconSpam, PulseIconArchive, PulseIconFolder, PulseIconLogout, PulseIconUp, PulseIconDown, PulseIconSettings, PulseIconAdd
};

@interface Theme : NSObject
+ (UIColor *)lime;       // акцент
+ (UIColor *)limeDark;   // акцент для текста на белом
+ (UIColor *)ink;        // тёмная верхняя панель
+ (UIColor *)menuColor;  // фон боковой шторки
+ (UIColor *)avatarColorForString:(NSString *)s;
+ (UIImage *)icon:(PulseIcon)kind color:(UIColor *)color size:(CGFloat)size;

// ---- Тема (светлая / тёмная) ----
+ (BOOL)isDark;
+ (void)setDark:(BOOL)dark;                       // сохраняет и обновляет статус-бар
+ (void)updateStatusBar;
+ (void)styleNavigationController:(UINavigationController *)nav;   // панель + тулбар
+ (UIColor *)bg;               // фон списков и страниц
+ (UIColor *)groupedBackground;
+ (UIColor *)cellBg;
+ (UIColor *)headerBg;
+ (UIColor *)textPrimary;
+ (UIColor *)textSecondary;
+ (UIColor *)separator;
+ (UIColor *)accent;           // даты, ссылки
+ (UIColor *)fieldColor;       // значения в полях ввода
+ (void)styleGroupedCell:(UITableViewCell *)cell;
+ (UIView *)groupedHeader:(NSString *)text;
+ (UIView *)groupedFooter:(NSString *)text width:(CGFloat)w;
+ (CGFloat)groupedFooterHeight:(NSString *)text width:(CGFloat)w;
@end
