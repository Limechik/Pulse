#import "MessageCell.h"
#import <QuartzCore/QuartzCore.h>
#import "Theme.h"
#import "Localization.h"

@implementation MessageCell {
    UIView *_dot;
    UILabel *_from, *_date, *_subject, *_preview;
}

+ (CGFloat)height { return 84; }
+ (CGFloat)heightWithPreview:(BOOL)preview { return preview ? 84 : 58; }

- (UILabel *)label:(UIFont *)font color:(UIColor *)color {
    UILabel *l = [[UILabel alloc] init];
    l.font = font;
    l.textColor = color;
    l.highlightedTextColor = [UIColor whiteColor];
    l.backgroundColor = [UIColor clearColor];
    l.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.contentView addSubview:l];
    return l;
}

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:rid];
    if (!self) return nil;
    self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

    // Синяя глянцевая точка непрочитанного
    _dot = [[UIView alloc] initWithFrame:CGRectMake(8, 13, 12, 12)];
    _dot.layer.cornerRadius = 6;
    _dot.layer.masksToBounds = YES;
    CAGradientLayer *g = [CAGradientLayer layer];
    g.frame = _dot.bounds;
    g.colors = @[(id)[UIColor colorWithRed:0.55 green:0.74 blue:1.0 alpha:1].CGColor,
                 (id)[UIColor colorWithRed:0.0 green:0.30 blue:0.90 alpha:1].CGColor];
    [_dot.layer addSublayer:g];
    [self.contentView addSubview:_dot];

    _from    = [self label:[UIFont boldSystemFontOfSize:17] color:[UIColor blackColor]];
    _date    = [self label:[UIFont systemFontOfSize:14] color:[UIColor grayColor]];
    _date.textAlignment = NSTextAlignmentRight;
    _subject = [self label:[UIFont systemFontOfSize:15] color:[UIColor blackColor]];
    _preview = [self label:[UIFont systemFontOfSize:15] color:[UIColor colorWithWhite:0.55 alpha:1]];
    _preview.numberOfLines = 2;
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width, x = 26;
    _date.frame    = CGRectMake(w - 78, 6, 72, 18);
    _from.frame    = CGRectMake(x, 4, w - x - 82, 22);
    _subject.frame = CGRectMake(x, 26, w - x - 8, 20);
    _preview.frame = CGRectMake(x, 46, w - x - 8, 36);
}

+ (NSString *)stringForDate:(NSDate *)d {
    if (!d) return @"";
    static NSDateFormatter *df;
    if (!df) df = [[NSDateFormatter alloc] init];
    df.locale = PulseLocale();
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDate *s1 = nil, *s2 = nil;
    [cal rangeOfUnit:NSDayCalendarUnit startDate:&s1 interval:NULL forDate:d];
    [cal rangeOfUnit:NSDayCalendarUnit startDate:&s2 interval:NULL forDate:[NSDate date]];
    NSInteger days = [cal components:NSDayCalendarUnit fromDate:s1 toDate:s2 options:0].day;
    if (days <= 0) { df.dateFormat = nil; df.timeStyle = NSDateFormatterShortStyle; df.dateStyle = NSDateFormatterNoStyle; }
    else if (days == 1) return L(@"Вчера");
    else if (days < 7) { df.timeStyle = NSDateFormatterNoStyle; df.dateStyle = NSDateFormatterNoStyle; df.dateFormat = @"EEEE"; }
    else { df.dateFormat = nil; df.timeStyle = NSDateFormatterNoStyle; df.dateStyle = NSDateFormatterShortStyle; }
    return [df stringFromDate:d];
}

- (void)configureWithMessage:(NSDictionary *)m {
    BOOL unread = ![m[@"seen"] boolValue];
    _dot.hidden = !unread;
    _from.text = m[@"from"];
    _subject.text = m[@"subject"];
    _preview.text = m[@"preview"];
    _date.text = [MessageCell stringForDate:m[@"date"]];
    _from.textColor = [Theme textPrimary];
    _subject.textColor = [Theme textPrimary];
    _preview.textColor = [Theme textSecondary];
    _preview.hidden = !self.showPreview;
    _date.textColor = unread ? [Theme accent] : [Theme textSecondary];
}

@end
