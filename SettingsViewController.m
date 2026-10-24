#import "SettingsViewController.h"
#import "AppDelegate.h"
#import "AppSettings.h"
#import "Theme.h"
#import "Localization.h"

enum { SecTheme = 0, SecLanguage, SecCount, SecList, SecTotal };

@implementation SettingsViewController

- (id)init { return [super initWithStyle:UITableViewStyleGrouped]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = L(@"Настройки");
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setToolbarHidden:YES animated:animated];
    [self applyTheme];
}

- (void)applyTheme {
    [Theme styleNavigationController:self.navigationController];
    UIView *bv = [[UIView alloc] init];
    bv.backgroundColor = [Theme groupedBackground];
    self.tableView.backgroundView = bv;
    [self.tableView reloadData];
}

- (NSArray *)counts { return @[@25, @50, @100]; }
- (NSArray *)languageCodes { return @[@"auto", @"ru", @"en"]; }

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return SecTotal; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    if (s == SecLanguage) return [self languageCodes].count;
    if (s == SecCount) return [self counts].count;
    return 1;
}

- (UIView *)tableView:(UITableView *)tv viewForHeaderInSection:(NSInteger)s {
    NSArray *t = @[L(@"Оформление"), L(@"Язык"), L(@"Писем в списке"), L(@"Список")];
    return [Theme groupedHeader:L(t[s])];
}
- (CGFloat)tableView:(UITableView *)tv heightForHeaderInSection:(NSInteger)s { return 34; }

- (NSString *)footerText:(NSInteger)s {
    if (s == SecTheme) return L(@"Тёмная тема меняет панели, списки и текст писем. HTML-письма остаются на светлом фоне, как задумал отправитель.");
    if (s == SecList) {
        NSString *v = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
        return [NSString stringWithFormat:@"Pulse %@", v ?: @""];
    }
    return nil;
}
- (UIView *)tableView:(UITableView *)tv viewForFooterInSection:(NSInteger)s {
    NSString *t = [self footerText:s];
    return t ? [Theme groupedFooter:t width:tv.bounds.size.width] : nil;
}
- (CGFloat)tableView:(UITableView *)tv heightForFooterInSection:(NSInteger)s {
    return [Theme groupedFooterHeight:[self footerText:s] width:tv.bounds.size.width];
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    if (ip.section == SecLanguage) {
        NSString *code = [self languageCodes][ip.row];
        NSArray *names = @[L(@"Авто (как в системе)"), L(@"Русский"), @"English"];
        c.textLabel.text = names[ip.row];
        c.accessoryType = [code isEqualToString:[AppSettings language]] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        return c;
    }
    if (ip.section == SecCount) {
        int n = [[self counts][ip.row] intValue];
        c.textLabel.text = [NSString stringWithFormat:@"%d", n];
        c.accessoryType = (n == [AppSettings messageCount]) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        return c;
    }
    c.selectionStyle = UITableViewCellSelectionStyleNone;
    UISwitch *sw = [[UISwitch alloc] init];
    if (ip.section == SecTheme) {
        c.textLabel.text = L(@"Тёмная тема");
        sw.on = [AppSettings darkTheme];
        [sw addTarget:self action:@selector(darkChanged:) forControlEvents:UIControlEventValueChanged];
    } else {
        c.textLabel.text = L(@"Показывать превью");
        sw.on = [AppSettings showPreview];
        [sw addTarget:self action:@selector(previewChanged:) forControlEvents:UIControlEventValueChanged];
    }
    c.accessoryView = sw;
    return c;
}

- (void)tableView:(UITableView *)tv willDisplayCell:(UITableViewCell *)c forRowAtIndexPath:(NSIndexPath *)ip {
    [Theme styleGroupedCell:c];
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == SecCount) {
        [AppSettings setMessageCount:[[self counts][ip.row] intValue]];
        [tv reloadData];
    } else if (ip.section == SecLanguage) {
        NSString *code = [self languageCodes][ip.row];
        if ([code isEqualToString:[AppSettings language]]) return;
        [AppSettings setLanguage:code];
        // Заголовки и кнопки выставляются при создании экранов — пересобираем интерфейс
        [(AppDelegate *)[UIApplication sharedApplication].delegate reloadInterfaceOpeningSettings];
    }
}

- (void)darkChanged:(UISwitch *)s {
    [Theme setDark:s.on];
    [self applyTheme];
}

- (void)previewChanged:(UISwitch *)s { [AppSettings setShowPreview:s.on]; }

@end
