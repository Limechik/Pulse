#import <UIKit/UIKit.h>

@interface MessageViewController : UIViewController <UIWebViewDelegate, UIActionSheetDelegate>
// messages — те же словари, что в списке (uid, from, subject, date, seen)
- (id)initWithMessages:(NSArray *)messages index:(NSInteger)index folderPath:(NSString *)path;
@property (nonatomic, copy) void (^onRead)(void);   // письмо стало прочитанным
@end
