#import <Foundation/Foundation.h>
@interface ApolloCommentSearch : NSObject
@property(nonatomic, copy) void (^updated)(NSArray<NSDictionary *> *results, NSString *status, BOOL loading, BOOL more);
- (void)search:(NSString *)query sort:(NSString *)sort time:(NSString *)time;
- (void)loadMore;
- (void)cancel;
@end
FOUNDATION_EXPORT NSDictionary *ApolloCommentSearchTerms(NSString *query);
FOUNDATION_EXPORT NSNumber *ApolloCommentSearchTimestamp(id value);
FOUNDATION_EXPORT NSDictionary *ApolloCommentSearchRow(NSDictionary *raw, NSDictionary *post, NSDictionary *terms, NSTimeInterval after);
FOUNDATION_EXPORT NSDictionary *ApolloCommentSearchMerge(NSDictionary *previous, NSDictionary *row, NSString *source);
FOUNDATION_EXPORT NSString *ApolloCommentSearchExcerpt(NSString *plainText, NSDictionary *terms);
FOUNDATION_EXPORT NSArray *ApolloCommentSearchSorted(NSArray *rows, NSString *sort);
