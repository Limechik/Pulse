#import "DrawerViewController.h"
#import "MessageListViewController.h"
#import "SettingsViewController.h"
#import "AppDelegate.h"
#import "Theme.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat kDrawerWidth = 270;

@implementation DrawerViewController {
    FolderMenuViewController *_menu;
    MessageListViewController *_list;
    UINavigationController *_nav;
    UIView *_contentView, *_overlay;
    CGFloat _panStart;
}

- (id)initWithMenu:(FolderMenuViewController *)menu list:(MessageListViewController *)list {
    self = [super init];
    if (self) { _menu = menu; _list = list; }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [Theme menuColor];
    CGRect b = self.view.bounds;

    [self addChildViewController:_menu];
    _menu.view.frame = CGRectMake(0, 0, kDrawerWidth, b.size.height);
    _menu.view.autoresizingMask = UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_menu.view];
    [_menu didMoveToParentViewController:self];
    _menu.delegate = self;

    _contentView = [[UIView alloc] initWithFrame:b];
    _contentView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _contentView.backgroundColor = [UIColor whiteColor];
    _contentView.layer.shadowColor = [UIColor blackColor].CGColor;
    _contentView.layer.shadowOpacity = 0.45;
    _contentView.layer.shadowRadius = 8;
    _contentView.layer.shadowOffset = CGSizeMake(-3, 0);
    _contentView.layer.shadowPath = [UIBezierPath bezierPathWithRect:
        CGRectMake(0, 0, b.size.width, 2000)].CGPath;
    [self.view addSubview:_contentView];

    _nav = [[UINavigationController alloc] initWithRootViewController:_list];
    [self addChildViewController:_nav];
    _nav.view.frame = _contentView.bounds;
    _nav.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_contentView addSubview:_nav.view];
    [_nav didMoveToParentViewController:self];
    _list.drawer = self;

    // Невидимый слой поверх контента, пока шторка открыта: тап закрывает её
    _overlay = [[UIView alloc] initWithFrame:_contentView.bounds];
    _overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _overlay.backgroundColor = [UIColor clearColor];
    _overlay.hidden = YES;
    [_overlay addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(closeTap)]];
    [_contentView addSubview:_overlay];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];
    pan.delegate = self;
    [_contentView addGestureRecognizer:pan];

    [self setOffset:0];
}

- (BOOL)isOpen { return _contentView.frame.origin.x > kDrawerWidth / 2; }

- (void)setOffset:(CGFloat)x {
    CGRect f = _contentView.frame;
    f.origin.x = x;
    _contentView.frame = f;
    CGFloat p = x / kDrawerWidth;
    CGRect m = _menu.view.frame;
    m.origin.x = -60 * (1 - p);       // лёгкий параллакс меню
    _menu.view.frame = m;
    _menu.view.alpha = 0.4 + 0.6 * p;
}

- (void)setOpen:(BOOL)open animated:(BOOL)animated {
    _overlay.hidden = !open;
    void (^change)(void) = ^{ [self setOffset:open ? kDrawerWidth : 0]; };
    if (open) [self.view endEditing:YES];
    if (animated)
        [UIView animateWithDuration:0.25 delay:0
                            options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
                         animations:change completion:nil];
    else change();
}

- (void)toggleDrawer { [self setOpen:!self.isOpen animated:YES]; }
- (void)closeTap { [self setOpen:NO animated:YES]; }

- (void)pan:(UIPanGestureRecognizer *)g {
    CGFloat dx = [g translationInView:self.view].x;
    switch (g.state) {
        case UIGestureRecognizerStateBegan:
            _panStart = _contentView.frame.origin.x;
            [self.view endEditing:YES];
            break;
        case UIGestureRecognizerStateChanged:
            [self setOffset:MAX(0, MIN(kDrawerWidth, _panStart + dx))];
            break;
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled: {
            CGFloat v = [g velocityInView:self.view].x;
            BOOL open = (v > 300) || (v > -300 && _contentView.frame.origin.x > kDrawerWidth / 2);
            [self setOpen:open animated:YES];
            break;
        }
        default: break;
    }
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g {
    if (![g isKindOfClass:[UIPanGestureRecognizer class]]) return YES;
    CGPoint v = [(UIPanGestureRecognizer *)g velocityInView:self.view];
    if (fabs(v.x) < fabs(v.y)) return NO;
    return self.isOpen ? YES : v.x > 0;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)a shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)b {
    return YES;
}

#pragma mark - FolderMenuDelegate

- (void)folderMenu:(FolderMenuViewController *)m didSelectFolder:(NSDictionary *)folder {
    [_nav popToRootViewControllerAnimated:NO];
    [_list showFolder:folder];
    [self setOpen:NO animated:YES];
}

- (void)openSettingsAnimated:(BOOL)animated {
    [_nav popToRootViewControllerAnimated:NO];
    [_nav pushViewController:[[SettingsViewController alloc] init] animated:animated];
}

- (void)folderMenuDidRequestSettings:(FolderMenuViewController *)m {
    [self setOpen:NO animated:YES];
    [self openSettingsAnimated:YES];
}

- (void)folderMenuDidSwitchAccount:(FolderMenuViewController *)m {
    [(AppDelegate *)[UIApplication sharedApplication].delegate showMailbox];
}

- (void)folderMenuDidRequestAddAccount:(FolderMenuViewController *)m {
    [(AppDelegate *)[UIApplication sharedApplication].delegate presentAddAccountFrom:self];
}

- (void)folderMenuDidRequestLogout:(FolderMenuViewController *)m {
    [(AppDelegate *)[UIApplication sharedApplication].delegate logout];
}

@end
