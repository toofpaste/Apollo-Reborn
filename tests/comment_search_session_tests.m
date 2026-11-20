#import "ApolloCommentSearch.h"

static int failures;
#define CHECK(...) do { if (!(__VA_ARGS__)) { fprintf(stderr, "FAIL %d: %s\n", __LINE__, #__VA_ARGS__); failures++; } } while (0)

// The host harness replaces only network I/O and Apollo's app-only helpers.
NSString *sUserAgent;
NSString *ApolloActiveAccountRedditBearerToken(void) { return nil; }
NSString *ApolloGoogleSearchPlainTextFromMarkdown(NSString *text) { return text; }

@interface FixtureSearch : ApolloCommentSearch
@property(nonatomic, copy) id (^response)(NSURL *, NSDictionary *);
@property(nonatomic, strong) NSMutableArray *requests;
- (void)deliver;
@end

@implementation FixtureSearch
- (instancetype)init {
    if ((self = [super init])) _requests = [NSMutableArray array];
    return self;
}
- (void)get:(NSURL *)url completion:(void (^)(id, NSInteger))completion {
    id (^response)(NSURL *, NSDictionary *) = self.response;
    [self.requests addObject:[^{
        NSMutableDictionary *params = [NSMutableDictionary dictionary];
        for (NSURLQueryItem *item in [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO].queryItems) params[item.name] = item.value;
        id result = response(url, params);
        if ([result isKindOfClass:NSNumber.class]) completion(nil, [result integerValue]);
        else completion(result, result ? 200 : 503);
    } copy]];
}
- (void)deliver {
    for (NSUInteger n = 0; self.requests.count && n < 100; n++) {
        void (^next)(void) = self.requests.firstObject;
        [self.requests removeObjectAtIndex:0];
        next();
    }
    CHECK(!self.requests.count);
}
@end

static NSDictionary *Listing(NSArray *children, NSString *after) {
    return @{@"data": @{@"children": children, @"after": after ?: NSNull.null}};
}
static NSDictionary *Thing(NSString *kind, NSDictionary *data) {
    return @{@"kind": kind, @"data": data};
}

int main(void) {
    @autoreleasepool {
        FixtureSearch *session = [FixtureSearch new];
        __block NSArray *rows = nil;
        __block BOOL busy = YES, more = YES;
        session.updated = ^(NSArray *results, NSString *status, BOOL loading, BOOL hasMore) {
            (void)status;
            rows = results; busy = loading; more = hasMore;
        };
        NSNumber *now = @(NSDate.date.timeIntervalSince1970);
        NSDictionary *live = @{@"id": @"abc", @"link_id": @"t3_123", @"subreddit": @"one", @"body": @"I use C++ today", @"created_utc": now};
        NSDictionary *archived = @{@"id": @"def", @"link_id": @"t3_456", @"subreddit": @"two", @"body": @"C++ yesterday", @"created_utc": now};
        NSDictionary *parent = @{@"id": @"123", @"title": @"A ten-year-old discussion", @"subreddit": @"one", @"created_utc": @1};
        NSDictionary *reply = @{@"id": @"ghi", @"body": @"C++ nested reply", @"created_utc": now};
        NSMutableDictionary *nested = [live mutableCopy];
        nested[@"replies"] = Listing(@[Thing(@"t1", reply)], nil);
        __block NSUInteger threadReads = 0, recentPages = 0, relatedReads = 0, titleReads = 0, archiveTitleReads = 0;
        session.response = ^id(NSURL *url, NSDictionary *params) {
            NSString *path = url.path;
            if ([path isEqual:@"/r/all/comments.json"]) {
                recentPages++;
                if (!params[@"after"]) return Listing(@[Thing(@"t1", @{@"body": @"other", @"created_utc": now})], @"t1_next");
                CHECK([params[@"after"] isEqual:@"t1_next"]);
                return Listing(@[Thing(@"t1", live)], nil);
            }
            if ([path isEqual:@"/search.json"]) {
                CHECK([params[@"q"] isEqual:@"C++"] && !params[@"t"]);
                // Both discovery sorts return the same old post.
                return Listing(@[Thing(@"t3", parent)], nil);
            }
            if ([path isEqual:@"/r/one/comments.json"]) { relatedReads++; return Listing(@[], nil); }
            if ([path isEqual:@"/comments/123.json"]) {
                threadReads++;
                CHECK([params[@"sort"] isEqual:@"new"]);
                return @[Listing(@[Thing(@"t3", parent)], nil), Listing(@[Thing(@"t1", nested)], nil)];
            }
            if ([url.host isEqual:@"api.pullpush.io"]) return @{@"data": @[live, archived]};
            if ([path isEqual:@"/api/comments/search"]) {
                CHECK([params[@"subreddit"] isEqual:@"one"]);
                return nil; // The other providers must still finish.
            }
            if ([path isEqual:@"/api/info.json"]) {
                titleReads++;
                return Listing(@[Thing(@"t3", parent)], nil);
            }
            if ([path isEqual:@"/api/posts/ids"]) {
                archiveTitleReads++;
                CHECK([params[@"ids"] isEqual:@"456"]);
                return @{@"data": @[@{@"id": @"456", @"title": @"Archived title", @"subreddit": @"two"}]};
            }
            CHECK(NO);
            return nil;
        };
        [session search:@"C++" sort:@"relevance" time:@"hour"];
        CHECK(busy);
        [session deliver];
        CHECK(!busy && more); // The archive error can be retried.
        CHECK(rows.count == 3 && recentPages == 2 && relatedReads == 1 && threadReads == 1);
        CHECK(titleReads == 1 && archiveTitleReads == 1);
        for (NSDictionary *row in rows) {
            CHECK([row[@"created_utc"] isEqual:now] && [row[@"subreddit"] length]);
            if ([row[@"name"] isEqual:@"t1_def"]) CHECK([row[@"link_title"] isEqual:@"Archived title"]);
            else CHECK([row[@"link_title"] isEqual:parent[@"title"]]);
            if ([row[@"name"] isEqual:@"t1_abc"]) CHECK([row[@"sources"] isEqual:@[@"PullPush", @"Reddit"]]);
        }
        session.response = ^id(NSURL *url, NSDictionary *params) {
            CHECK([url.path isEqual:@"/api/comments/search"] && [params[@"subreddit"] isEqual:@"one"]);
            return @{@"data": @[]};
        };
        [session loadMore];
        [session deliver];
        CHECK(!busy && !more && rows.count == 3);

        // A scoped query finds recent comments even when their parent doesn't
        // match the keyword. Each feed resumes with its own comment cursor.
        __block NSUInteger userPages = 0;
        session.response = ^id(NSURL *url, NSDictionary *params) {
            if ([url.path isEqual:@"/user/example/comments.json"]) {
                userPages++;
                if (userPages == 1) {
                    CHECK(!params[@"after"]);
                    NSMutableDictionary *fromUser = [live mutableCopy];
                    fromUser[@"author"] = @"example";
                    fromUser[@"link_title"] = @"Unrelated post title";
                    return Listing(@[Thing(@"t1", fromUser)], @"t1_abc");
                }
                CHECK([params[@"after"] isEqual:@"t1_abc"]);
                return Listing(@[], @"t1_abc");
            }
            CHECK([params[@"author"] isEqual:@"example"] && [params[@"subreddit"] isEqual:@"one"]);
            return @{@"data": @[]};
        };
        [session search:@"author:example subreddit:one C++" sort:@"new" time:@"hour"];
        [session deliver];
        CHECK(!busy && more && userPages == 1 && rows.count == 1);
        CHECK([rows.firstObject[@"link_title"] isEqual:@"Unrelated post title"]);
        [session loadMore];
        [session deliver];
        CHECK(!busy && !more && userPages == 2 && rows.count == 1);

        // Both post searches finish empty before the global archive returns.
        // Its matching community can still reveal a brand-new reply. A busy
        // Arctic Shift index can serve a chronological page for local filtering.
        __block BOOL triedIndex = NO, triedListing = NO, foundCommunity = NO;
        session.response = ^id(NSURL *url, NSDictionary *params) {
            if ([url.host isEqual:@"api.pullpush.io"]) return @{@"data": @[archived]};
            if ([url.path isEqual:@"/api/info.json"]) return Listing(@[Thing(@"t3", @{@"id": @"456", @"title": @"Found via comment body"})], nil);
            if ([url.path isEqual:@"/api/comments/search"]) {
                CHECK([params[@"subreddit"] isEqual:@"two"]);
                if (params[@"body"]) { triedIndex = YES; return @422; }
                triedListing = YES;
                return @{@"data": @[archived, @{@"id": @"bad", @"body": @"other", @"link_id": @"456"}]};
            }
            if ([url.path isEqual:@"/r/two/comments.json"]) {
                foundCommunity = YES;
                NSMutableDictionary *fresh = [archived mutableCopy];
                fresh[@"id"] = @"fresh";
                return Listing(@[Thing(@"t1", fresh)], nil);
            }
            return Listing(@[], nil);
        };
        [session search:@"C++" sort:@"new" time:@"hour"];
        CHECK(session.requests.count == 4);
        if (session.requests.count == 4) [session.requests exchangeObjectAtIndex:1 withObjectAtIndex:3];
        [session deliver];
        CHECK(!busy && !more && rows.count == 2);
        CHECK(triedIndex && triedListing && foundCommunity);
        printf("Comment search session: %d failures\n", failures);
    }
    return failures ? 1 : 0;
}
