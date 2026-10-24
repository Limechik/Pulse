#import "LoginViewController.h"
#import "Localization.h"
#import "AppDelegate.h"
#import "Providers.h"
#import "IMAPClient.h"
#import "KeychainStore.h"
#import "AccountStore.h"
#import "Theme.h"

@implementation LoginViewController {
    NSInteger _idx;
    UITextField *_email, *_pass;
    UIBarButtonItem *_next;
}

- (id)init { return [super initWithStyle:UITableViewStyleGrouped]; }

- (UITextField *)makeField:(NSString *)placeholder {
    UITextField *t = [[UITextField alloc] initWithFrame:CGRectMake(105, 11, 175, 22)];
    t.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    t.placeholder = placeholder;
    t.font = [UIFont systemFontOfSize:17];
    t.textColor = [UIColor colorWithRed:0.22 green:0.33 blue:0.53 alpha:1];
    t.autocapitalizationType = UITextAutocapitalizationTypeNone;
    t.autocorrectionType = UITextAutocorrectionTypeNo;
    t.clearButtonMode = UITextFieldViewModeWhileEditing;
    t.delegate = self;
    return t;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = L(@"Новая запись");
    if (self.addingAccount)
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:L(@"Отмена")
            style:UIBarButtonItemStyleBordered target:self action:@selector(cancelTapped)];
    _next = [[UIBarButtonItem alloc] initWithTitle:L(@"Далее") style:UIBarButtonItemStyleDone
                                            target:self action:@selector(login)];
    self.navigationItem.rightBarButtonItem = _next;
    _email = [self makeField:@"name@example.com"];
    _email.keyboardType = UIKeyboardTypeEmailAddress;
    _email.returnKeyType = UIReturnKeyNext;
    _pass = [self makeField:L(@"Пароль приложения")];
    _pass.secureTextEntry = YES;
    _pass.returnKeyType = UIReturnKeyGo;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [Theme styleNavigationController:self.navigationController];
    UIView *bv = [[UIView alloc] init];
    bv.backgroundColor = [Theme groupedBackground];
    self.tableView.backgroundView = bv;
    _email.textColor = [Theme fieldColor];
    _pass.textColor = [Theme fieldColor];
    [self.tableView reloadData];
}

- (BOOL)textFieldShouldReturn:(UITextField *)f {
    if (f == _email) [_pass becomeFirstResponder]; else [self login];
    return NO;
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 2; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return s == 0 ? [Providers all].count : 2;
}
- (UIView *)tableView:(UITableView *)tv viewForHeaderInSection:(NSInteger)s {
    return s == 0 ? [Theme groupedHeader:L(@"Почтовый сервис")] : nil;
}
- (CGFloat)tableView:(UITableView *)tv heightForHeaderInSection:(NSInteger)s { return s == 0 ? 34 : 12; }
- (UIView *)tableView:(UITableView *)tv viewForFooterInSection:(NSInteger)s {
    return s == 1 ? [Theme groupedFooter:L([Providers all][_idx][@"hint"]) width:tv.bounds.size.width] : nil;
}
- (CGFloat)tableView:(UITableView *)tv heightForFooterInSection:(NSInteger)s {
    return s == 1 ? [Theme groupedFooterHeight:L([Providers all][_idx][@"hint"]) width:tv.bounds.size.width] : 6;
}
- (void)tableView:(UITableView *)tv willDisplayCell:(UITableViewCell *)c forRowAtIndexPath:(NSIndexPath *)ip {
    [Theme styleGroupedCell:c];
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section == 0) {
        UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"p"];
        if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"p"];
        c.textLabel.text = [Providers all][ip.row][@"name"];
        c.accessoryType = (ip.row == _idx) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        return c;
    }
    UITableViewCell *c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    c.selectionStyle = UITableViewCellSelectionStyleNone;
    c.textLabel.font = [UIFont boldSystemFontOfSize:17];
    c.textLabel.text = ip.row == 0 ? @"Email" : L(@"Пароль");
    [c.contentView addSubview:(ip.row == 0 ? _email : _pass)];
    return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section != 0) return;
    _idx = ip.row;
    [tv reloadData];
}

#pragma mark - Login

- (void)alert:(NSString *)msg {
    [[[UIAlertView alloc] initWithTitle:L(@"Не удалось войти") message:msg delegate:nil
                      cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
}

- (void)cancelTapped { [self.navigationController dismissViewControllerAnimated:YES completion:nil]; }

- (void)finishLogin {
    AppDelegate *ad = (AppDelegate *)[UIApplication sharedApplication].delegate;
    UIViewController *presenter = self.navigationController.presentingViewController;
    if (presenter) [presenter dismissViewControllerAnimated:NO completion:^{ [ad showMailbox]; }];
    else [ad showMailbox];
}

- (void)login {
    [self.view endEditing:YES];
    NSString *email = [_email.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]].lowercaseString;
    NSString *pass = _pass.text;
    if (!email.length || !pass.length) { [self alert:L(@"Введите email и пароль приложения")]; return; }

    NSDictionary *p = [Providers all][_idx];
    NSInteger idx = _idx;
    UIActivityIndicatorView *sp = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    [sp startAnimating];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:sp];
    self.title = L(@"Проверка…");

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *err = nil;
        IMAPClient *c = [[IMAPClient alloc] init];
        BOOL ok = [c connectToHost:p[@"imapHost"] port:[p[@"imapPort"] intValue] error:&err]
               && [c loginWithUser:email password:pass error:&err];
        [c disconnect];

        dispatch_async(dispatch_get_main_queue(), ^{
            self.title = L(@"Новая запись");
            self.navigationItem.rightBarButtonItem = _next;
            if (ok && [KeychainStore savePassword:pass forAccount:email]) {
                [AccountStore addAccount:email providerIndex:idx];
                [self finishLogin];
            } else {
                [self alert:err ?: L(@"Не удалось сохранить пароль")];
            }
        });
    });
}

@end
