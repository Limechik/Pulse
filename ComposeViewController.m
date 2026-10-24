#import "ComposeViewController.h"
#import "Localization.h"
#import "MailService.h"
#import "Theme.h"
#import <AddressBook/AddressBook.h>

static const CGFloat kRowH = 44;

@implementation ComposeViewController {
    NSString *_ttl, *_initialTo, *_initialCc, *_initialSubject, *_initialBody, *_inReplyTo, *_references;
    UITextView *_text;
    UIView *_header;
    UITextField *_to, *_cc, *_subject, *_pickTarget;
    UIBarButtonItem *_sendItem, *_cancelItem;
}

+ (UINavigationController *)navigationWithTitle:(NSString *)title to:(NSString *)to cc:(NSString *)cc
                                        subject:(NSString *)subject body:(NSString *)body
                                      inReplyTo:(NSString *)irt references:(NSString *)refs {
    ComposeViewController *vc = [[ComposeViewController alloc] initWithTitle:title to:to cc:cc subject:subject
                                                                        body:body inReplyTo:irt references:refs];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    [Theme styleNavigationController:nav];
    return nav;
}

- (id)initWithTitle:(NSString *)title to:(NSString *)to cc:(NSString *)cc subject:(NSString *)subject
               body:(NSString *)body inReplyTo:(NSString *)irt references:(NSString *)refs {
    self = [super init];
    if (self) {
        _ttl = [title copy];
        _initialTo = to ?: @""; _initialCc = cc ?: @""; _initialSubject = subject ?: @""; _initialBody = body ?: @"";
        _inReplyTo = [irt copy]; _references = [refs copy];
    }
    return self;
}

- (UITextField *)addRow:(int)i label:(NSString *)label picker:(BOOL)picker {
    CGFloat w = self.view.bounds.size.width, y = i * kRowH;
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(12, y + 12, 56, 20)];
    l.backgroundColor = [UIColor clearColor];
    l.font = [UIFont systemFontOfSize:15];
    l.textColor = [Theme textSecondary];
    l.text = label;
    [_header addSubview:l];

    UITextField *t = [[UITextField alloc] initWithFrame:CGRectMake(68, y + 8, w - 68 - (picker ? 44 : 12), 28)];
    t.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    t.font = [UIFont systemFontOfSize:16];
    t.textColor = [Theme textPrimary];
    t.autocapitalizationType = UITextAutocapitalizationTypeNone;
    t.autocorrectionType = UITextAutocorrectionTypeNo;
    t.keyboardAppearance = [Theme isDark] ? UIKeyboardAppearanceAlert : UIKeyboardAppearanceDefault;
    t.returnKeyType = UIReturnKeyNext;
    t.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    t.delegate = self;
    [_header addSubview:t];

    if (picker) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeContactAdd];
        b.frame = CGRectMake(w - 40, y + 6, 32, 32);
        b.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        b.tag = i;
        [b addTarget:self action:@selector(pickContact:) forControlEvents:UIControlEventTouchUpInside];
        [_header addSubview:b];
    }
    UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(0, y + kRowH - 1, w, 1)];
    sep.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    sep.backgroundColor = [Theme separator];
    [_header addSubview:sep];
    return t;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = _ttl ?: L(@"Новое сообщение");
    self.view.backgroundColor = [Theme bg];

    _cancelItem = [[UIBarButtonItem alloc] initWithTitle:L(@"Отмена") style:UIBarButtonItemStyleBordered
                                                  target:self action:@selector(cancel)];
    _sendItem = [[UIBarButtonItem alloc] initWithTitle:L(@"Отправить") style:UIBarButtonItemStyleDone
                                                target:self action:@selector(send)];
    self.navigationItem.leftBarButtonItem = _cancelItem;
    self.navigationItem.rightBarButtonItem = _sendItem;

    CGFloat w = self.view.bounds.size.width, headerH = kRowH * 3;
    _text = [[UITextView alloc] initWithFrame:self.view.bounds];
    _text.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _text.font = [UIFont systemFontOfSize:16];
    _text.backgroundColor = [Theme bg];
    _text.textColor = [Theme textPrimary];
    _text.alwaysBounceVertical = YES;
    _text.keyboardAppearance = [Theme isDark] ? UIKeyboardAppearanceAlert : UIKeyboardAppearanceDefault;
    _text.delegate = self;
    _text.contentInset = UIEdgeInsetsMake(headerH, 0, 0, 0);
    [self.view addSubview:_text];

    _header = [[UIView alloc] initWithFrame:CGRectMake(0, -headerH, w, headerH)];
    _header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [_text addSubview:_header];
    _to = [self addRow:0 label:L(@"Кому:") picker:YES];
    _to.keyboardType = UIKeyboardTypeEmailAddress;
    _cc = [self addRow:1 label:L(@"Копия:") picker:YES];
    _cc.keyboardType = UIKeyboardTypeEmailAddress;
    _subject = [self addRow:2 label:L(@"Тема:") picker:NO];
    _subject.autocapitalizationType = UITextAutocapitalizationTypeSentences;
    _subject.autocorrectionType = UITextAutocorrectionTypeDefault;
    [_to addTarget:self action:@selector(recipientChanged) forControlEvents:UIControlEventEditingChanged];

    _to.text = _initialTo; _cc.text = _initialCc; _subject.text = _initialSubject;
    _text.text = _initialBody;
    _text.selectedRange = NSMakeRange(0, 0);
    _text.contentOffset = CGPointMake(0, -headerH);
    [self recipientChanged];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(kbShow:) name:UIKeyboardWillShowNotification object:nil];
    [nc addObserver:self selector:@selector(kbHide:) name:UIKeyboardWillHideNotification object:nil];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!_to.text.length) [_to becomeFirstResponder]; else [_text becomeFirstResponder];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)kbShow:(NSNotification *)n {
    CGRect kb = [[n.userInfo objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    UIEdgeInsets in = UIEdgeInsetsMake(kRowH * 3, 0, kb.size.height, 0);
    _text.contentInset = in;
    _text.scrollIndicatorInsets = in;
}

- (void)kbHide:(NSNotification *)n {
    UIEdgeInsets in = UIEdgeInsetsMake(kRowH * 3, 0, 0, 0);
    _text.contentInset = in;
    _text.scrollIndicatorInsets = in;
}

#pragma mark - Поля

- (BOOL)textFieldShouldReturn:(UITextField *)f {
    if (f == _to) [_cc becomeFirstResponder];
    else if (f == _cc) [_subject becomeFirstResponder];
    else [_text becomeFirstResponder];
    return NO;
}

- (void)recipientChanged {
    _sendItem.enabled = [[_to.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] length] > 0;
}

- (NSArray *)parseAddresses:(NSString *)s {
    NSMutableArray *out = [NSMutableArray array];
    NSString *norm = [[s stringByReplacingOccurrencesOfString:@";" withString:@","]
                      stringByReplacingOccurrencesOfString:@"\n" withString:@","];
    for (NSString *p in [norm componentsSeparatedByString:@","]) {
        NSString *t = [p stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!t.length) continue;
        NSRange a = [t rangeOfString:@"<"], b = [t rangeOfString:@">" options:NSBackwardsSearch];
        if (a.location != NSNotFound && b.location != NSNotFound && b.location > a.location)
            t = [t substringWithRange:NSMakeRange(a.location + 1, b.location - a.location - 1)];
        [out addObject:t];
    }
    return out;
}

- (BOOL)isValidAddress:(NSString *)a {
    return [a rangeOfString:@"^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$" options:NSRegularExpressionSearch].location != NSNotFound;
}

#pragma mark - Контакты

- (void)pickContact:(UIButton *)b {
    _pickTarget = (b.tag == 1) ? _cc : _to;
    [self.view endEditing:YES];
    ABPeoplePickerNavigationController *p = [[ABPeoplePickerNavigationController alloc] init];
    p.peoplePickerDelegate = self;
    p.displayedProperties = @[@(kABPersonEmailProperty)];
    [self presentViewController:p animated:YES completion:nil];
}

- (BOOL)peoplePickerNavigationController:(ABPeoplePickerNavigationController *)p shouldContinueAfterSelectingPerson:(ABRecordRef)person {
    return YES;     // показать адреса контакта
}

- (BOOL)peoplePickerNavigationController:(ABPeoplePickerNavigationController *)p
      shouldContinueAfterSelectingPerson:(ABRecordRef)person property:(ABPropertyID)property
                              identifier:(ABMultiValueIdentifier)identifier {
    ABMultiValueRef emails = ABRecordCopyValue(person, kABPersonEmailProperty);
    if (emails) {
        CFIndex idx = ABMultiValueGetIndexForIdentifier(emails, identifier);
        NSString *email = (idx >= 0) ? (__bridge_transfer NSString *)ABMultiValueCopyValueAtIndex(emails, idx) : nil;
        CFRelease(emails);
        if (email.length) {
            NSString *cur = [_pickTarget.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            _pickTarget.text = cur.length ? [NSString stringWithFormat:@"%@, %@", cur, email] : email;
            [self recipientChanged];
        }
    }
    [self dismissViewControllerAnimated:YES completion:nil];
    return NO;
}

- (void)peoplePickerNavigationControllerDidCancel:(ABPeoplePickerNavigationController *)p {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Отмена / отправка

- (void)alert:(NSString *)title message:(NSString *)msg {
    [[[UIAlertView alloc] initWithTitle:title message:msg delegate:nil
                      cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
}

- (void)cancel {
    [self.view endEditing:YES];
    BOOL dirty = _to.text.length || _cc.text.length ||
        ![_subject.text isEqualToString:_initialSubject] || ![_text.text isEqualToString:_initialBody];
    if (!dirty) { [self dismissViewControllerAnimated:YES completion:nil]; return; }
    UIActionSheet *s = [[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:L(@"Продолжить")
                                     destructiveButtonTitle:L(@"Удалить черновик") otherButtonTitles:nil];
    [s showInView:self.view];
}

- (void)actionSheet:(UIActionSheet *)s clickedButtonAtIndex:(NSInteger)i {
    if (i == s.destructiveButtonIndex) [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)send {
    [self.view endEditing:YES];
    NSArray *to = [self parseAddresses:_to.text], *cc = [self parseAddresses:_cc.text];
    if (!to.count) { [self alert:L(@"Нет получателя") message:L(@"Укажите адрес в поле «Кому».")]; return; }
    for (NSString *a in [to arrayByAddingObjectsFromArray:cc]) {
        if (![self isValidAddress:a]) {
            [self alert:L(@"Неверный адрес") message:[NSString stringWithFormat:L(@"«%@» не похож на email."), a]];
            return;
        }
    }

    UIActivityIndicatorView *sp = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    [sp startAnimating];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:sp];
    _cancelItem.enabled = NO;
    self.view.userInteractionEnabled = NO;
    self.title = L(@"Отправка…");

    [[MailService shared] sendTo:to cc:cc subject:_subject.text body:_text.text
                       inReplyTo:_inReplyTo references:_references
                      completion:^(BOOL ok, NSString *err) {
        if (ok) {
            [self dismissViewControllerAnimated:YES completion:nil];
            return;
        }
        self.title = _ttl ?: L(@"Новое сообщение");
        self.navigationItem.rightBarButtonItem = _sendItem;
        _cancelItem.enabled = YES;
        self.view.userInteractionEnabled = YES;
        [self alert:L(@"Не удалось отправить") message:err];
    }];
}

@end
