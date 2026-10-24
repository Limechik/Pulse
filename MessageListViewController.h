#import <UIKit/UIKit.h>

@class DrawerViewController;

@interface MessageListViewController : UITableViewController <UISearchBarDelegate>
@property (nonatomic, weak) DrawerViewController *drawer;
- (void)showFolder:(NSDictionary *)folder;   // path, name
@end
