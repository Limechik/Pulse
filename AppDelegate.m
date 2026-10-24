#import "AppDelegate.h"
#import "LoginViewController.h"
#import "DrawerViewController.h"
#import "FolderMenuViewController.h"
#import "MessageListViewController.h"
#import "AccountStore.h"
#import "Theme.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)opts {
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.backgroundColor = [UIColor blackColor];
    [Theme updateStatusBar];
    if ([AccountStore activeAccount]) [self showMailbox]; else [self showLogin];
    [self.window makeKeyAndVisible];
    return YES;
}

- (void)setRoot:(UIViewController *)vc {
    if (!self.window.rootViewController) { self.window.rootViewController = vc; return; }
    [UIView transitionWithView:self.window duration:0.3 options:UIViewAnimationOptionTransitionCrossDissolve
                    animations:^{ self.window.rootViewController = vc; } completion:nil];
}

- (DrawerViewController *)makeDrawer {
    return [[DrawerViewController alloc] initWithMenu:[[FolderMenuViewController alloc] init]
                                                 list:[[MessageListViewController alloc] init]];
}

- (void)showMailbox { [self setRoot:[self makeDrawer]]; }

- (void)showLogin {
    [self setRoot:[[UINavigationController alloc] initWithRootViewController:[[LoginViewController alloc] init]]];
}

- (void)logout {
    [AccountStore removeActiveAccount];
    if ([AccountStore activeAccount]) [self showMailbox]; else [self showLogin];
}

- (void)presentAddAccountFrom:(UIViewController *)presenter {
    LoginViewController *vc = [[LoginViewController alloc] init];
    vc.addingAccount = YES;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    [Theme styleNavigationController:nav];
    [presenter presentViewController:nav animated:YES completion:nil];
}

- (void)reloadInterfaceOpeningSettings {
    DrawerViewController *d = [self makeDrawer];
    [self setRoot:d];
    [d view];                                  // загрузить, чтобы появился _nav
    [d openSettingsAnimated:NO];
}

@end
