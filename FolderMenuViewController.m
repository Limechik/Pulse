#import "FolderMenuViewController.h"
#import "Localization.h"
#import "MailService.h"
#import "AccountStore.h"
#import "Providers.h"
#import "Theme.h"

static PulseIcon IconFor(NSString *special) {
    if ([special isEqualToString:@"inbox"])   return PulseIconInbox;
    if ([special isEqualToString:@"sent"])    return PulseIconSent;
    if ([special isEqualToString:@"drafts"])  return PulseIconDrafts;
    if ([special isEqualToString:@"trash"])   return PulseIconTrash;
    if ([special isEqualToString:@"junk"])    return PulseIconSpam;
    if ([special isEqualToString:@"archive"] || [special isEqualToString:@"all"]) return PulseIconArchive;
    return PulseIconFolder;
}

@implementation FolderMenuViewController {
    NSArray *_folders;
    NSString *_selectedPath;
    UITableView *_table;
    UIImageView *_chevron;
    BOOL _showAccounts;
}

- (UIButton *)bottomButton:(NSString *)title icon:(PulseIcon)icon y:(CGFloat)y action:(SEL)action {
    UIColor *gray = [UIColor colorWithWhite:0.75 alpha:1];
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = CGRectMake(0, y, 270, 50);
    b.autoresizingMask = UIViewAutoresizingFlexibleTopMargin;
    b.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    b.contentEdgeInsets = UIEdgeInsetsMake(0, 15, 0, 0);
    b.titleEdgeInsets = UIEdgeInsetsMake(0, 12, 0, 0);
    b.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [b setTitleColor:gray forState:UIControlStateNormal];
    [b setTitle:title forState:UIControlStateNormal];
    [b setImage:[Theme icon:icon color:gray size:20] forState:UIControlStateNormal];
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    UIView *line = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 270, 1)];
    line.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1];
    [b addSubview:line];
    [self.view addSubview:b];
    return b;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [Theme menuColor];
    _selectedPath = @"INBOX";
    _folders = @[@{@"path": @"INBOX", @"name": L(@"Входящие"), @"special": @"inbox"}];

    // Шапка с активным аккаунтом; тап раскрывает список аккаунтов
    UILabel *prov = [[UILabel alloc] initWithFrame:CGRectMake(15, 14, 210, 22)];
    prov.backgroundColor = [UIColor clearColor];
    prov.font = [UIFont boldSystemFontOfSize:18];
    prov.textColor = [UIColor whiteColor];
    prov.shadowColor = [UIColor blackColor];
    prov.shadowOffset = CGSizeMake(0, -1);
    prov.text = [Providers all][[AccountStore activeProviderIndex]][@"name"];
    [self.view addSubview:prov];

    UILabel *em = [[UILabel alloc] initWithFrame:CGRectMake(15, 37, 210, 18)];
    em.backgroundColor = [UIColor clearColor];
    em.font = [UIFont systemFontOfSize:13];
    em.textColor = [UIColor colorWithWhite:0.62 alpha:1];
    em.text = [AccountStore activeEmail];
    [self.view addSubview:em];

    _chevron = [[UIImageView alloc] initWithImage:[Theme icon:PulseIconDown color:[UIColor colorWithWhite:0.7 alpha:1] size:20]];
    _chevron.frame = CGRectMake(270 - 36, 24, 20, 20);
    [self.view addSubview:_chevron];

    UIButton *hdr = [UIButton buttonWithType:UIButtonTypeCustom];
    hdr.frame = CGRectMake(0, 0, 270, 68);
    [hdr addTarget:self action:@selector(toggleAccounts) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:hdr];

    CGFloat h = self.view.bounds.size.height;
    _table = [[UITableView alloc] initWithFrame:CGRectMake(0, 68, 270, h - 68 - 100) style:UITableViewStylePlain];
    _table.autoresizingMask = UIViewAutoresizingFlexibleHeight;
    _table.backgroundColor = [UIColor clearColor];
    _table.separatorColor = [UIColor colorWithWhite:0.08 alpha:1];
    _table.rowHeight = 44;
    _table.dataSource = self;
    _table.delegate = self;
    [self.view addSubview:_table];

    [self bottomButton:L(@"Настройки") icon:PulseIconSettings y:h - 100 action:@selector(settingsTapped)];
    [self bottomButton:L(@"Удалить аккаунт") icon:PulseIconLogout y:h - 50 action:@selector(logoutTapped)];

    [self reloadFolders];
}

- (void)reloadFolders {
    [[MailService shared] loadFolders:^(NSArray *folders, NSString *err) {
        if (folders.count) { _folders = folders; [_table reloadData]; }
    }];
}

- (void)toggleAccounts {
    _showAccounts = !_showAccounts;
    _chevron.image = [Theme icon:_showAccounts ? PulseIconUp : PulseIconDown
                           color:[UIColor colorWithWhite:0.7 alpha:1] size:20];
    [_table reloadData];
}

- (void)settingsTapped { [self.delegate folderMenuDidRequestSettings:self]; }

- (void)logoutTapped {
    NSString *email = [AccountStore activeEmail] ?: @"";
    UIActionSheet *s = [[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:L(@"Отмена")
                                     destructiveButtonTitle:[NSString stringWithFormat:L(@"Удалить %@"), email]
                                          otherButtonTitles:nil];
    [s showInView:self.view];
}

- (void)actionSheet:(UIActionSheet *)s clickedButtonAtIndex:(NSInteger)i {
    if (i == s.destructiveButtonIndex) [self.delegate folderMenuDidRequestLogout:self];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return _showAccounts ? [AccountStore accounts].count + 1 : _folders.count;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UIColor *gray = [UIColor colorWithWhite:0.75 alpha:1];
    if (_showAccounts) {
        NSArray *accs = [AccountStore accounts];
        UITableViewCell *c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
        c.selectionStyle = UITableViewCellSelectionStyleNone;
        c.textLabel.backgroundColor = [UIColor clearColor];
        c.detailTextLabel.backgroundColor = [UIColor clearColor];
        c.textLabel.font = [UIFont boldSystemFontOfSize:15];
        c.detailTextLabel.font = [UIFont systemFontOfSize:12];
        if (ip.row == (NSInteger)accs.count) {
            c.textLabel.text = L(@"Добавить почту");
            c.textLabel.textColor = gray;
            c.imageView.image = [Theme icon:PulseIconAdd color:gray size:22];
            return c;
        }
        BOOL active = ip.row == [AccountStore activeIndex];
        UIColor *col = active ? [UIColor whiteColor] : gray;
        c.textLabel.text = accs[ip.row][@"email"];
        c.textLabel.textColor = col;
        c.detailTextLabel.text = [Providers all][[accs[ip.row][@"providerIndex"] integerValue]][@"name"];
        c.detailTextLabel.textColor = [UIColor colorWithWhite:0.55 alpha:1];
        c.imageView.image = [Theme icon:PulseIconInbox color:col size:22];
        c.accessoryType = active ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        return c;
    }
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"f"];
    if (!c) {
        c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"f"];
        c.selectionStyle = UITableViewCellSelectionStyleNone;
        c.textLabel.backgroundColor = [UIColor clearColor];
        c.textLabel.font = [UIFont boldSystemFontOfSize:16];
    }
    NSDictionary *f = _folders[ip.row];
    BOOL sel = [f[@"path"] isEqualToString:_selectedPath];
    UIColor *col = sel ? [UIColor whiteColor] : gray;
    c.textLabel.text = f[@"name"];
    c.textLabel.textColor = col;
    c.imageView.image = [Theme icon:IconFor(f[@"special"]) color:col size:22];
    return c;
}

- (void)tableView:(UITableView *)tv willDisplayCell:(UITableViewCell *)c forRowAtIndexPath:(NSIndexPath *)ip {
    BOOL hl = _showAccounts ? (ip.row == [AccountStore activeIndex])
                            : [_folders[ip.row][@"path"] isEqualToString:_selectedPath];
    c.backgroundColor = hl ? [UIColor colorWithWhite:0.26 alpha:1] : [UIColor clearColor];
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    if (_showAccounts) {
        [tv deselectRowAtIndexPath:ip animated:YES];
        if (ip.row == (NSInteger)[AccountStore accounts].count) {
            [self.delegate folderMenuDidRequestAddAccount:self];
        } else if (ip.row != [AccountStore activeIndex]) {
            [AccountStore setActiveIndex:ip.row];
            [self.delegate folderMenuDidSwitchAccount:self];
        } else {
            [self toggleAccounts];
        }
        return;
    }
    NSDictionary *f = _folders[ip.row];
    _selectedPath = f[@"path"];
    [tv reloadData];
    [self.delegate folderMenu:self didSelectFolder:f];
}

@end
