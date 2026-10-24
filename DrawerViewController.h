#import <UIKit/UIKit.h>
#import "FolderMenuViewController.h"

@class MessageListViewController;

@interface DrawerViewController : UIViewController <FolderMenuDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, readonly) BOOL isOpen;
- (id)initWithMenu:(FolderMenuViewController *)menu list:(MessageListViewController *)list;
- (void)toggleDrawer;
- (void)openSettingsAnimated:(BOOL)animated;
- (void)setOpen:(BOOL)open animated:(BOOL)animated;
@end
