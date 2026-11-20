#import <UIKit/UIKit.h>

// Reddit-mode results. Suggestions and external engines retain their existing hosts.
@interface ApolloRedditSearchViewController : UIViewController
@property(nonatomic) NSInteger initialKind;
- (instancetype)initWithQuery:(NSString *)query;
@end
