#import <UIKit/UIKit.h>

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (strong, nonatomic) UIWindow *window;
- (void)showMailbox;                                       // пересобрать главный интерфейс для активного аккаунта
- (void)showLogin;
- (void)logout;                                            // удалить активный аккаунт
- (void)presentAddAccountFrom:(UIViewController *)presenter;
- (void)reloadInterfaceOpeningSettings;                    // после смены языка
@end
