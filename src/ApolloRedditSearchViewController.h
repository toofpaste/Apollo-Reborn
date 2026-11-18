#import <UIKit/UIKit.h>

// Reddit-mode results. Suggestions and external engines retain their existing hosts.
@interface ApolloRedditSearchViewController : UIViewController
- (instancetype)initWithQuery:(NSString *)query;
@end
