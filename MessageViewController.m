#import "MessageViewController.h"
#import "MailService.h"
#import "AccountStore.h"
#import "Localization.h"
#import "ComposeViewController.h"
#import "Theme.h"

@implementation MessageViewController {
    NSArray *_messages;
    NSInteger _index;
    NSString *_path;
    int _token;
    UIWebView *_web;
    UIView *_header;
    UILabel *_errorLabel;
    UIActivityIndicatorView *_spinner;
    UISegmentedControl *_seg;
    CGFloat _headerHeight;
    NSDictionary *_full;
    UIBarButtonItem *_replyItem;
}

- (id)initWithMessages:(NSArray *)messages index:(NSInteger)index folderPath:(NSString *)path {
    self = [super init];
    if (self) { _messages = messages; _index = index; _path = [path copy]; }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [Theme bg];

    _web = [[UIWebView alloc] initWithFrame:self.view.bounds];
    _web.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _web.delegate = self;
    _web.scalesPageToFit = YES;
    _web.backgroundColor = [Theme bg];
    _web.dataDetectorTypes = UIDataDetectorTypeLink;
    [self.view addSubview:_web];

    _header = [[UIView alloc] init];
    _header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _header.backgroundColor = [Theme headerBg];
    [_web.scrollView addSubview:_header];

    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    _spinner.center = CGPointMake(self.view.bounds.size.width / 2, 230);
    _spinner.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    [self.view addSubview:_spinner];

    _errorLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 200, self.view.bounds.size.width - 40, 100)];
    _errorLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _errorLabel.numberOfLines = 0;
    _errorLabel.textAlignment = NSTextAlignmentCenter;
    _errorLabel.textColor = [Theme textSecondary];
    _errorLabel.font = [UIFont systemFontOfSize:14];
    _errorLabel.backgroundColor = [UIColor clearColor];
    _errorLabel.hidden = YES;
    [self.view addSubview:_errorLabel];

    // Стрелки «предыдущее / следующее», как в Mail iOS 6
    _seg = [[UISegmentedControl alloc] initWithItems:@[
        [Theme icon:PulseIconUp color:[UIColor whiteColor] size:22],
        [Theme icon:PulseIconDown color:[UIColor whiteColor] size:22]]];
    _seg.segmentedControlStyle = UISegmentedControlStyleBar;
    _seg.momentary = YES;
    _seg.frame = CGRectMake(0, 0, 88, 30);
    [_seg addTarget:self action:@selector(segTapped:) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:_seg];

    // Нижняя панель: ответить / написать
    _replyItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemReply
                                                               target:self action:@selector(replyTapped)];
    _replyItem.enabled = NO;
    UIBarButtonItem *flex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    self.toolbarItems = @[_replyItem, flex,
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCompose target:self action:@selector(composeNew)]];

    [self loadCurrent];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setToolbarHidden:NO animated:animated];
}

- (void)segTapped:(UISegmentedControl *)s {
    NSInteger ni = _index + (s.selectedSegmentIndex == 0 ? -1 : 1);
    if (ni < 0 || ni >= (NSInteger)_messages.count) return;
    _index = ni;
    [self loadCurrent];
}

#pragma mark - Загрузка

- (void)loadCurrent {
    NSDictionary *m = _messages[_index];
    self.title = [NSString stringWithFormat:L(@"%ld из %lu"), (long)_index + 1, (unsigned long)_messages.count];
    [_seg setEnabled:_index > 0 forSegmentAtIndex:0];
    [_seg setEnabled:_index < (NSInteger)_messages.count - 1 forSegmentAtIndex:1];
    _errorLabel.hidden = YES;
    _full = nil;
    _replyItem.enabled = NO;

    // Сразу показываем шапку из списка, пока грузится тело
    [self applyHeaderHeight:[self buildHeader:m]];
    [_web loadHTMLString:@"<html><body></body></html>" baseURL:nil];

    NSString *uid = m[@"uid"];
    if (!uid.length) { [self showError:L(@"У письма нет UID — обновите список.")]; return; }

    [_spinner startAnimating];
    int token = ++_token;
    [[MailService shared] loadMessageUID:uid inFolder:_path completion:^(NSDictionary *full, NSString *err) {
        if (token != _token) return;       // уже открыли другое письмо
        [_spinner stopAnimating];
        if (!full) { [self showError:err ?: L(@"Не удалось загрузить письмо")]; return; }

        if ([m isKindOfClass:[NSMutableDictionary class]] && ![m[@"seen"] boolValue]) {
            [(NSMutableDictionary *)m setObject:@YES forKey:@"seen"];
            if (self.onRead) self.onRead();
        }
        _full = full;
        _replyItem.enabled = YES;
        [self applyHeaderHeight:[self buildHeader:full]];
        [_web loadHTMLString:[self htmlFor:full] baseURL:nil];
    }];
}

- (void)showError:(NSString *)msg {
    _errorLabel.text = msg;
    _errorLabel.hidden = NO;
}

#pragma mark - Шапка

- (UILabel *)labelWithText:(NSString *)t font:(UIFont *)f color:(UIColor *)c frame:(CGRect)fr {
    UILabel *l = [[UILabel alloc] initWithFrame:fr];
    l.backgroundColor = [UIColor clearColor];
    l.font = f;
    l.textColor = c;
    l.text = t;
    l.numberOfLines = 0;
    [_header addSubview:l];
    return l;
}

- (CGFloat)buildHeader:(NSDictionary *)info {
    for (UIView *v in [_header.subviews copy]) [v removeFromSuperview];
    CGFloat w = _web.bounds.size.width > 1 ? _web.bounds.size.width : 320;
    CGFloat y = 10, lx = 8, lw = 50, vx = 62, vw = w - vx - 10;
    UIFont *vf = [UIFont boldSystemFontOfSize:15], *lf = [UIFont systemFontOfSize:15];
    UIColor *gray = [Theme textSecondary];

    NSArray *rows = @[@[L(@"От:"),   info[@"from"] ?: @"", info[@"fromAddress"] ?: @""],
                      @[L(@"Кому:"), info[@"to"] ?: @"",   @""],
                      @[L(@"Копия:"), info[@"cc"] ?: @"",  @""]];
    for (NSArray *r in rows) {
        NSString *val = r[1];
        if (!val.length) continue;
        CGSize sz = [val sizeWithFont:vf constrainedToSize:CGSizeMake(vw, 80) lineBreakMode:NSLineBreakByTruncatingTail];
        UILabel *l = [self labelWithText:r[0] font:lf color:gray frame:CGRectMake(lx, y, lw, 18)];
        l.textAlignment = NSTextAlignmentRight;
        [self labelWithText:val font:vf color:[Theme textPrimary] frame:CGRectMake(vx, y, vw, sz.height)];
        y += sz.height + 2;
        NSString *addr = r[2];
        if (addr.length && ![addr isEqualToString:val]) {
            [self labelWithText:addr font:[UIFont systemFontOfSize:12] color:gray frame:CGRectMake(vx, y, vw, 15)];
            y += 16;
        }
        y += 4;
    }

    UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(10, y, w - 10, 1)];
    sep.backgroundColor = [Theme separator];
    [_header addSubview:sep];
    y += 9;

    NSString *subj = info[@"subject"] ?: @"";
    CGSize ss = [subj sizeWithFont:[UIFont boldSystemFontOfSize:17] constrainedToSize:CGSizeMake(w - 20, 110)
                     lineBreakMode:NSLineBreakByWordWrapping];
    [self labelWithText:subj font:[UIFont boldSystemFontOfSize:17] color:[Theme textPrimary]
                  frame:CGRectMake(10, y, w - 20, ss.height)];
    y += ss.height + 3;

    NSDate *date = info[@"date"];
    if (date) {
        NSDateFormatter *df = [[NSDateFormatter alloc] init];
        df.locale = PulseLocale();
        df.dateStyle = NSDateFormatterMediumStyle;
        df.timeStyle = NSDateFormatterShortStyle;
        [self labelWithText:[df stringFromDate:date] font:[UIFont systemFontOfSize:13] color:gray
                      frame:CGRectMake(10, y, w - 20, 17)];
        y += 21;
    }

    for (NSDictionary *a in info[@"attachments"]) {
        int kb = MAX(1, [a[@"size"] intValue] / 1024);
        NSString *size = kb >= 1024 ? [NSString stringWithFormat:L(@"%.1f МБ"), kb / 1024.0]
                                    : [NSString stringWithFormat:L(@"%d КБ"), kb];
        [self labelWithText:[NSString stringWithFormat:L(@"Вложение: %@ (%@)"), a[@"name"], size]
                       font:[UIFont systemFontOfSize:13] color:[Theme fieldColor]
                      frame:CGRectMake(10, y, w - 20, 17)];
        y += 20;
    }
    y += 8;

    UIView *line = [[UIView alloc] initWithFrame:CGRectMake(0, y - 1, w, 1)];
    line.backgroundColor = [Theme separator];
    [_header addSubview:line];
    return y;
}

- (void)applyHeaderHeight:(CGFloat)h {
    _headerHeight = h;
    _header.frame = CGRectMake(0, -h, _web.bounds.size.width, h);
    _web.scrollView.contentInset = UIEdgeInsetsMake(h, 0, 0, 0);
    _web.scrollView.scrollIndicatorInsets = UIEdgeInsetsMake(h, 0, 0, 0);
    _web.scrollView.contentOffset = CGPointMake(0, -h);
}

#pragma mark - Тело письма

- (NSString *)htmlFor:(NSDictionary *)full {
    NSString *body = full[@"body"] ?: @"";
    if ([full[@"html"] boolValue]) {
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"<script[^>]*>.*?</script>"
            options:NSRegularExpressionCaseInsensitive | NSRegularExpressionDotMatchesLineSeparators error:NULL];
        body = [re stringByReplacingMatchesInString:body options:0 range:NSMakeRange(0, body.length) withTemplate:@""];
    } else {
        body = [body stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"];
        body = [body stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"];
        body = [body stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"];
        body = [NSString stringWithFormat:@"<div style=\"white-space:pre-wrap\">%@</div>", body];
    }
    if (!body.length) body = L(@"<p style=\"color:#999\">(пустое письмо)</p>");
    // Простой текст следует теме; HTML-письма остаются на светлом фоне
    BOOL isHTML = [full[@"html"] boolValue], dark = [Theme isDark];
    NSString *fg = (!isHTML && dark) ? @"#ececec" : @"#000";
    NSString *bg = (!isHTML && dark) ? @"#121212" : @"#fff";
    _web.backgroundColor = (!isHTML && dark) ? [Theme bg] : [UIColor whiteColor];
    return [NSString stringWithFormat:
        @"<html><head><meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0, minimum-scale=0.25, maximum-scale=3.0\">"
        @"<style>html{-webkit-text-size-adjust:none}body{margin:0;padding:12px;font:16px/1.4 Helvetica,Arial,sans-serif;"
        @"word-wrap:break-word;color:%@;background:%@}img{max-width:100%%;height:auto}</style></head><body>%@</body></html>", fg, bg, body];
}

#pragma mark - Ответ / пересылка

- (void)composeNew {
    [self presentViewController:[ComposeViewController navigationWithTitle:L(@"Новое сообщение") to:nil cc:nil
                                                                   subject:nil body:nil inReplyTo:nil references:nil]
                       animated:YES completion:nil];
}

- (void)replyTapped {
    UIActionSheet *s = [[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:nil
                                     destructiveButtonTitle:nil
                                          otherButtonTitles:L(@"Ответить"), L(@"Ответить всем"), L(@"Переслать"), nil];
    s.cancelButtonIndex = [s addButtonWithTitle:L(@"Отмена")];
    [s showFromToolbar:self.navigationController.toolbar];
}

- (void)actionSheet:(UIActionSheet *)s clickedButtonAtIndex:(NSInteger)i {
    if (i == s.cancelButtonIndex) return;
    [self composeKind:i];
}

static BOOL HasPrefix(NSString *s, NSArray *prefixes) {
    NSString *l = [s lowercaseString];
    for (NSString *p in prefixes) if ([l hasPrefix:p]) return YES;
    return NO;
}

// kind: 0 — ответить, 1 — ответить всем, 2 — переслать
- (void)composeKind:(NSInteger)kind {
    NSDictionary *f = _full;
    if (!f) return;
    NSString *me = [[AccountStore activeEmail] lowercaseString] ?: @"";
    NSString *subj = f[@"subject"] ?: @"";
    NSString *text = f[@"text"] ?: @"";
    NSString *name = [f[@"from"] length] ? f[@"from"] : (f[@"fromAddress"] ?: @"");
    NSString *dateStr = @"";
    if (f[@"date"]) {
        NSDateFormatter *df = [[NSDateFormatter alloc] init];
        df.locale = PulseLocale();
        df.dateStyle = NSDateFormatterMediumStyle;
        df.timeStyle = NSDateFormatterShortStyle;
        dateStr = [df stringFromDate:f[@"date"]];
    }
    NSString *mid = f[@"messageId"] ?: @"";
    NSString *refs = [f[@"references"] length] ? [NSString stringWithFormat:@"%@ %@", f[@"references"], mid] : mid;

    NSString *to = @"", *cc = @"", *newSubj, *body, *title;
    if (kind == 2) {
        title = L(@"Пересылка");
        newSubj = HasPrefix(subj, @[@"fwd:", @"fw:"]) ? subj : [@"Fwd: " stringByAppendingString:subj];
        body = [NSString stringWithFormat:
            L(@"\n\n---------- Пересланное сообщение ----------\nОт: %@\nДата: %@\nТема: %@\nКому: %@\n\n%@"),
            name, dateStr, subj, f[@"to"] ?: @"", text];
    } else {
        title = L(@"Ответ");
        NSString *ra = [f[@"replyTo"] length] ? f[@"replyTo"] : f[@"fromAddress"];
        NSMutableArray *toList = [NSMutableArray array], *ccList = [NSMutableArray array];
        NSMutableSet *seen = [NSMutableSet setWithObject:me];
        if (ra.length) { [toList addObject:ra]; [seen addObject:[ra lowercaseString]]; }
        if (kind == 1) {
            for (NSString *a in f[@"toAddrs"]) if (![seen containsObject:[a lowercaseString]]) {
                [toList addObject:a]; [seen addObject:[a lowercaseString]];
            }
            for (NSString *a in f[@"ccAddrs"]) if (![seen containsObject:[a lowercaseString]]) {
                [ccList addObject:a]; [seen addObject:[a lowercaseString]];
            }
        }
        to = [toList componentsJoinedByString:@", "];
        cc = [ccList componentsJoinedByString:@", "];
        newSubj = HasPrefix(subj, @[@"re:", @"отв:"]) ? subj : [@"Re: " stringByAppendingString:subj];
        NSMutableArray *quoted = [NSMutableArray array];
        NSArray *lines = [text componentsSeparatedByString:@"\n"];
        for (NSUInteger i = 0; i < lines.count && i < 200; i++)
            [quoted addObject:[@"> " stringByAppendingString:lines[i]]];
        body = [NSString stringWithFormat:L(@"\n\n\n%@, %@ написал(а):\n%@"), dateStr, name,
                [quoted componentsJoinedByString:@"\n"]];
    }
    [self presentViewController:[ComposeViewController navigationWithTitle:title to:to cc:cc subject:newSubj
                                                                      body:body inReplyTo:(kind == 2 ? nil : mid)
                                                                references:(kind == 2 ? nil : refs)]
                       animated:YES completion:nil];
}

#pragma mark - UIWebViewDelegate

- (BOOL)webView:(UIWebView *)wv shouldStartLoadWithRequest:(NSURLRequest *)req navigationType:(UIWebViewNavigationType)type {
    if (type == UIWebViewNavigationTypeLinkClicked) {
        NSString *scheme = [req.URL.scheme lowercaseString];
        if ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"])
            [[UIApplication sharedApplication] openURL:req.URL];
        return NO;
    }
    return YES;
}

- (void)webViewDidFinishLoad:(UIWebView *)wv {
    if (wv.scrollView.contentOffset.y > -_headerHeight && wv.scrollView.contentOffset.y < 0)
        wv.scrollView.contentOffset = CGPointMake(0, -_headerHeight);
}

- (void)dealloc { _web.delegate = nil; }

@end
