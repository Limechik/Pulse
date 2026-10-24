#import <UIKit/UIKit.h>
#import <AddressBookUI/AddressBookUI.h>

// Экран «Новое сообщение». Показывать модально внутри UINavigationController.
@interface ComposeViewController : UIViewController <UITextViewDelegate, UITextFieldDelegate,
                                                     UIActionSheetDelegate, ABPeoplePickerNavigationControllerDelegate>
- (id)initWithTitle:(NSString *)title to:(NSString *)to cc:(NSString *)cc subject:(NSString *)subject
               body:(NSString *)body inReplyTo:(NSString *)inReplyTo references:(NSString *)references;

// Готовый модальный контроллер с применённой темой
+ (UINavigationController *)navigationWithTitle:(NSString *)title to:(NSString *)to cc:(NSString *)cc
                                        subject:(NSString *)subject body:(NSString *)body
                                      inReplyTo:(NSString *)inReplyTo references:(NSString *)references;
@end
