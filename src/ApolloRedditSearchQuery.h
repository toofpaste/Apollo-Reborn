#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, ApolloSearchNSFWFilter) {
    ApolloSearchNSFWAll,
    ApolloSearchNSFWExclude,
    ApolloSearchNSFWOnly,
};

FOUNDATION_EXPORT NSURL *ApolloRedditSearchURL(NSString *query, BOOL communities,
    NSString *sort, NSString *time, ApolloSearchNSFWFilter filter, NSString *after, BOOL oauth);
FOUNDATION_EXPORT BOOL ApolloRedditSearchAcceptsNSFW(NSDictionary *data, ApolloSearchNSFWFilter filter);
FOUNDATION_EXPORT NSURL *ApolloRedditSearchPreviewURL(NSDictionary *data);
FOUNDATION_EXPORT BOOL ApolloRedditSearchIsMedia(NSDictionary *data);
