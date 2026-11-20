#import <Foundation/Foundation.h>
@interface ApolloCommentSearch : NSObject
@property(nonatomic, copy) void (^updated)(NSArray<NSDictionary *> *results, NSString *status, BOOL loading, BOOL more);
- (void)search:(NSString *)query sort:(NSString *)sort time:(NSString *)time;
- (void)loadMore;
- (void)cancel;
@end
FOUNDATION_EXPORT NSDictionary *ApolloCommentSearchTerms(NSString *query);
FOUNDATION_EXPORT NSArray *ApolloCommentSearchSorted(NSArray *rows, NSString *sort, NSString *text);
FOUNDATION_EXPORT NSInteger ApolloCommentSearchRelevance(NSString *body, NSString *query);
