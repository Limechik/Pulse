#import <UIKit/UIKit.h>

@interface MessageCell : UITableViewCell
+ (CGFloat)height;
+ (CGFloat)heightWithPreview:(BOOL)preview;
@property (nonatomic) BOOL showPreview;
- (void)configureWithMessage:(NSDictionary *)m;
@end
