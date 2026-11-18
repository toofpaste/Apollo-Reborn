#import <Foundation/Foundation.h>
#import "ApolloRedditSearchQuery.h"

static NSUInteger failures;
#define CHECK(value) do { if (!(value)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #value); failures++; } } while (0)

int main(void) {
    @autoreleasepool {
        NSURL *url = ApolloRedditSearchURL(@"author:example cats OR dogs & café", NO, @"top", @"hour", ApolloSearchNSFWOnly, @"t3_next", YES);
        NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
        for (NSURLQueryItem *item in [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO].queryItems) parameters[item.name] = item.value;
        CHECK([url.host isEqual:@"oauth.reddit.com"]);
        CHECK([parameters[@"q"] isEqual:@"(author:example cats OR dogs & café) AND nsfw:yes"]);
        CHECK([parameters[@"after"] isEqual:@"t3_next"]);
        CHECK([parameters[@"sort"] isEqual:@"top"]);
        CHECK([parameters[@"t"] isEqual:@"hour"]);
        CHECK([parameters[@"include_over_18"] isEqual:@"on"]);
        CHECK([parameters[@"type"] isEqual:@"link"]);
        url = ApolloRedditSearchURL(@"cats", YES, @"relevance", @"all", ApolloSearchNSFWExclude, nil, NO);
        CHECK([url.host isEqual:@"www.reddit.com"]);
        [parameters removeAllObjects];
        for (NSURLQueryItem *item in [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO].queryItems) parameters[item.name] = item.value;
        CHECK([parameters[@"type"] isEqual:@"sr"]);
        CHECK([parameters[@"include_over_18"] isEqual:@"off"]);
        CHECK(parameters[@"after"] == nil);
        CHECK(ApolloRedditSearchAcceptsNSFW(@{@"over_18": @YES}, ApolloSearchNSFWOnly));
        CHECK(!ApolloRedditSearchAcceptsNSFW(@{@"over_18": @NO}, ApolloSearchNSFWOnly));
        CHECK(!ApolloRedditSearchAcceptsNSFW(@{@"over_18": @YES}, ApolloSearchNSFWExclude));
        CHECK(ApolloRedditSearchAcceptsNSFW(@{@"over_18": @NO}, ApolloSearchNSFWExclude));
        CHECK(ApolloRedditSearchAcceptsNSFW(@{@"over18": @YES}, ApolloSearchNSFWOnly));
        CHECK(!ApolloRedditSearchAcceptsNSFW(@{}, ApolloSearchNSFWOnly));
        CHECK(!ApolloRedditSearchAcceptsNSFW(@{@"over_18": NSNull.null}, ApolloSearchNSFWExclude));
        CHECK(ApolloRedditSearchAcceptsNSFW(@{}, ApolloSearchNSFWAll));
        CHECK(ApolloRedditSearchIsMedia(@{@"is_video": @YES}));
        CHECK(ApolloRedditSearchIsMedia(@{@"is_gallery": @YES}));
        CHECK(ApolloRedditSearchIsMedia(@{@"post_hint": @"image"}));
        CHECK(!ApolloRedditSearchIsMedia(@{@"post_hint": @"link", @"thumbnail": @"https://example.com/image.jpg"}));
        CHECK(ApolloRedditSearchPreviewURL(@{@"thumbnail": @"nsfw"}) == nil);
        CHECK(ApolloRedditSearchPreviewURL(@{@"thumbnail": @"http://example.com/image.jpg"}) == nil);
        CHECK(ApolloRedditSearchPreviewURL(@{@"preview": NSNull.null, @"media_metadata": @42}) == nil);
        NSURL *preview = ApolloRedditSearchPreviewURL(@{@"preview": @{@"images": @[@{@"resolutions": @[
            @{@"width": @108, @"url": @"https://example.com/small"},
            @{@"width": @320, @"url": @"https://example.com/medium?a=1&amp;b=2"},
            @{@"width": @1080, @"url": @"https://example.com/large"}]}]}});
        CHECK([preview.absoluteString isEqual:@"https://example.com/medium?a=1&b=2"]);
        printf("Reddit search tests: %lu failures\n", (unsigned long)failures);
    }
    return failures ? 1 : 0;
}
