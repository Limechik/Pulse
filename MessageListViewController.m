#import "MessageListViewController.h"
#import "Localization.h"
#import "DrawerViewController.h"
#import "MessageCell.h"
#import "AppSettings.h"
#import "ComposeViewController.h"
#import "MessageViewController.h"
#import "MailService.h"
#import "Theme.h"

@implementation MessageListViewController {
    NSDictionary *_folder;
    NSArray *_messages, *_filtered;
    NSString *_query;
    UILabel *_status;
    UISearchBar *_search;
    int _loadedCount;
}

- (id)init {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        _folder = @{@"path": @"INBOX", @"name": L(@"Входящие"), @"special": @"inbox"};
        _messages = @[]; _filtered = @[];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = _folder[@"name"];
    self.tableView.rowHeight = [MessageCell height];

    // Кнопка шторки — обычный UIBarButtonItem
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithImage:[Theme icon:PulseIconMenu color:[UIColor whiteColor] size:22]
                                         style:UIBarButtonItemStyleBordered
                                        target:self action:@selector(menuTapped)];

    _search = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, 320, 44)];
    _search.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _search.delegate = self;
    _search.placeholder = L(@"Поиск");
    self.tableView.tableHeaderView = _search;
    self.tableView.contentOffset = CGPointMake(0, 44);

    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];

    // Нижняя панель как в Mail: обновить / статус / написать
    _status = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 190, 40)];
    _status.numberOfLines = 2;
    _status.textAlignment = NSTextAlignmentCenter;
    _status.font = [UIFont boldSystemFontOfSize:11];
    _status.textColor = [UIColor whiteColor];
    _status.shadowColor = [UIColor colorWithWhite:0 alpha:0.5];
    _status.shadowOffset = CGSizeMake(0, -1);
    _status.backgroundColor = [UIColor clearColor];
    UIBarButtonItem *flex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    self.toolbarItems = @[
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(reload)],
        flex,
        [[UIBarButtonItem alloc] initWithCustomView:_status],
        flex,
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCompose target:self action:@selector(compose)]];

    [self reload];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setToolbarHidden:NO animated:animated];
    [self applyTheme];
    if (_loadedCount && _loadedCount != [AppSettings messageCount]) [self reload];   // изменили «Писем в списке»
}

- (void)applyTheme {
    [Theme styleNavigationController:self.navigationController];
    self.tableView.backgroundColor = [Theme bg];
    self.tableView.separatorColor = [Theme separator];
    self.tableView.rowHeight = [MessageCell heightWithPreview:[AppSettings showPreview]];
    _search.barStyle = [Theme isDark] ? UIBarStyleBlack : UIBarStyleDefault;
    [self.tableView reloadData];
}

- (void)tableView:(UITableView *)tv willDisplayCell:(UITableViewCell *)c forRowAtIndexPath:(NSIndexPath *)ip {
    c.backgroundColor = [Theme cellBg];
}

- (void)menuTapped { [self.drawer toggleDrawer]; }

- (void)compose {
    [self presentViewController:[ComposeViewController navigationWithTitle:L(@"Новое сообщение") to:nil cc:nil
                                                                   subject:nil body:nil inReplyTo:nil references:nil]
                       animated:YES completion:nil];
}

- (void)showFolder:(NSDictionary *)folder {
    _folder = folder;
    self.title = folder[@"name"];
    _messages = @[]; _filtered = @[];
    _query = nil;
    _search.text = @"";
    [_search resignFirstResponder];
    [self.tableView reloadData];
    [self.tableView setContentOffset:CGPointMake(0, 0) animated:NO];
    [self reload];
}

#pragma mark - Данные

- (void)updateStatus {
    int unread = 0;
    for (NSDictionary *m in _messages) if (![m[@"seen"] boolValue]) unread++;
    _status.text = [NSString stringWithFormat:L(@"Обновлено только что\n%d непрочитанных"), unread];
}

- (void)reload {
    NSString *path = _folder[@"path"];
    _loadedCount = [AppSettings messageCount];
    _status.text = L(@"Проверка почты…");
    [[MailService shared] loadMessagesInFolder:path count:_loadedCount completion:^(NSArray *msgs, NSString *err) {
        if (![path isEqualToString:_folder[@"path"]]) return;   // папку уже сменили
        [self.refreshControl endRefreshing];
        if (msgs) {
            _messages = msgs;
            [self updateStatus];
            [self applyFilter];
        } else {
            _status.text = L(@"Не удалось обновить");
            [[[UIAlertView alloc] initWithTitle:L(@"Ошибка") message:err ?: L(@"Неизвестная ошибка")
                                       delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
        }
    }];
}

- (void)applyFilter {
    if (_query.length) {
        NSPredicate *pr = [NSPredicate predicateWithFormat:
            @"from CONTAINS[cd] %@ OR subject CONTAINS[cd] %@ OR preview CONTAINS[cd] %@", _query, _query, _query];
        _filtered = [_messages filteredArrayUsingPredicate:pr];
    } else {
        _filtered = _messages;
    }
    [self.tableView reloadData];
}

- (void)searchBar:(UISearchBar *)sb textDidChange:(NSString *)text { _query = text; [self applyFilter]; }
- (void)searchBarSearchButtonClicked:(UISearchBar *)sb { [sb resignFirstResponder]; }

#pragma mark - Таблица

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return _filtered.count; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    MessageCell *cell = [tv dequeueReusableCellWithIdentifier:@"msg"];
    if (!cell) cell = [[MessageCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"msg"];
    cell.showPreview = [AppSettings showPreview];
    [cell configureWithMessage:_filtered[ip.row]];
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    MessageViewController *vc = [[MessageViewController alloc]
        initWithMessages:_filtered index:ip.row folderPath:_folder[@"path"]];
    vc.onRead = ^{
        [self updateStatus];
        [self.tableView reloadData];
    };
    [self.navigationController pushViewController:vc animated:YES];
}

@end
