#import <UIKit/UIKit.h>

@class FolderMenuViewController;

@protocol FolderMenuDelegate <NSObject>
- (void)folderMenu:(FolderMenuViewController *)menu didSelectFolder:(NSDictionary *)folder;
- (void)folderMenuDidRequestLogout:(FolderMenuViewController *)menu;
- (void)folderMenuDidRequestSettings:(FolderMenuViewController *)menu;
- (void)folderMenuDidSwitchAccount:(FolderMenuViewController *)menu;
- (void)folderMenuDidRequestAddAccount:(FolderMenuViewController *)menu;
@end

@interface FolderMenuViewController : UIViewController <UITableViewDataSource, UITableViewDelegate, UIActionSheetDelegate>
@property (nonatomic, weak) id<FolderMenuDelegate> delegate;
@end
