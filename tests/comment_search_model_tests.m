#import <Foundation/Foundation.h>
#import "ApolloCommentSearch.h"

static int failures;
#define CHECK(...) do { if (!(__VA_ARGS__)) { fprintf(stderr, "FAIL %d: %s\n", __LINE__, #__VA_ARGS__); failures++; } } while (0)

int main(void) {
    @autoreleasepool {
        NSDictionary *terms = ApolloCommentSearchTerms(@"  subreddit:ApolloApp APOLLO \n search\t author:example-user ");
        CHECK([terms[@"subreddit"] isEqual:@"ApolloApp"]);
        CHECK([terms[@"author"] isEqual:@"example-user"]);
        CHECK([terms[@"text"] isEqual:@"APOLLO search"]);
        CHECK([ApolloCommentSearchTerms(@"ordinary search")[@"text"] isEqual:@"ordinary search"]);
        CHECK([ApolloCommentSearchTerms(@"r/apolloapp u/example-user")[@"text"] isEqual:@""]);
        CHECK([ApolloCommentSearchTerms(@"\"r/apolloapp\"")[@"needles"] isEqual:@[@"r/apolloapp"]]);
        CHECK([ApolloCommentSearchTerms(@"C++")[@"text"] isEqual:@"C++"]);

        NSDictionary *scoped = ApolloCommentSearchTerms(@"r/apolloapp u/EXAMPLE-user \"apollo search\"");
        NSDictionary *post = @{@"id": @"pq", @"title": @"Old discussion", @"subreddit": @"apolloapp", @"created_utc": @4};
        NSMutableDictionary *raw = [@{@"id": @"t1_abc", @"author": @"example-user", @"body": @"Apollo\nSEARCH works!",
                                      @"created_utc": @"200.5", @"score": @0} mutableCopy];
        NSDictionary *live = ApolloCommentSearchRow(raw, post, scoped, 200);
        CHECK([live[@"name"] isEqual:@"t1_abc"]);
        CHECK([live[@"link_title"] isEqual:@"Old discussion"]);
        CHECK([live[@"link_id"] isEqual:@"pq"]);
        CHECK([live[@"subreddit"] isEqual:@"apolloapp"]);
        CHECK([live[@"permalink"] isEqual:@"/comments/pq/_/abc/"]);
        CHECK([live[@"created_utc"] isEqual:@200.5]);
        CHECK(!ApolloCommentSearchRow(raw, post, scoped, 201));
        CHECK(!ApolloCommentSearchRow(raw, post, ApolloCommentSearchTerms(@"u/somebody"), 0));
        CHECK(!ApolloCommentSearchRow(raw, post, ApolloCommentSearchTerms(@"r/another"), 0));
        raw[@"body"] = @"Search now works in Apollo";
        CHECK(!ApolloCommentSearchRow(raw, post, scoped, 0));
        NSDictionary *scattered = ApolloCommentSearchRow(raw, post, terms, 0);
        CHECK(scattered);
        raw[@"body"] = @"APOLLO search";
        CHECK([ApolloCommentSearchRow(raw, post, terms, 0)[@"relevance"] integerValue] > [scattered[@"relevance"] integerValue]);
        raw[@"body"] = @"[removed]";
        CHECK(!ApolloCommentSearchRow(raw, post, terms, 0));
        raw[@"body"] = @"APOLLO SEARCH in an archive";
        raw[@"permalink"] = @"https://www.reddit.com/r/apolloapp/comments/pq/old_discussion/abc/";
        raw[@"score"] = @99;
        NSDictionary *archive = ApolloCommentSearchRow(raw, nil, scoped, 0);
        CHECK([archive[@"link_id"] isEqual:@"pq"]);
        CHECK([archive[@"subreddit"] isEqual:@"apolloapp"]);
        CHECK([[archive[@"permalink"] stringByStandardizingPath] isEqual:@"/r/apolloapp/comments/pq/old_discussion/abc"]);
        for (NSNumber *liveFirst in @[@YES, @NO]) {
            NSDictionary *row = liveFirst.boolValue ? ApolloCommentSearchMerge(nil, live, @"Reddit") : ApolloCommentSearchMerge(nil, archive, @"PullPush");
            row = liveFirst.boolValue ? ApolloCommentSearchMerge(row, archive, @"PullPush") : ApolloCommentSearchMerge(row, live, @"Reddit");
            CHECK([row[@"body"] isEqual:live[@"body"]]);
            CHECK([row[@"score"] isEqual:@0]);
            CHECK([row[@"link_title"] isEqual:post[@"title"]]);
            CHECK([row[@"sources"] isEqual:@[@"PullPush", @"Reddit"]]);
        }
        raw[@"link_title"] = @"From the comment listing";
        NSDictionary *older = @{@"name": @"t1_abc", @"created_utc": @100};
        NSDictionary *newer = @{@"name": @"t1_abc", @"created_utc": @200};
        for (NSNumber *olderFirst in @[@YES, @NO]) {
            NSDictionary *row = olderFirst.boolValue ? ApolloCommentSearchMerge(nil, older, @"PullPush") : ApolloCommentSearchMerge(nil, newer, @"Arctic Shift");
            row = olderFirst.boolValue ? ApolloCommentSearchMerge(row, newer, @"Arctic Shift") : ApolloCommentSearchMerge(row, older, @"PullPush");
            CHECK([row[@"created_utc"] isEqual:@200] && [row[@"sources"] count] == 2);
            CHECK([ApolloCommentSearchMerge(row, live, @"Reddit")[@"created_utc"] isEqual:live[@"created_utc"]]);
        }
        raw[@"created_utc"] = NSNull.null;
        archive = ApolloCommentSearchRow(raw, nil, terms, 0);
        CHECK(!archive[@"created_utc"]);
        CHECK([archive[@"link_title"] isEqual:raw[@"link_title"]]);
        CHECK(!ApolloCommentSearchRow(raw, nil, terms, 1));
        CHECK(!ApolloCommentSearchTimestamp(@"42 seconds"));
        CHECK(!ApolloCommentSearchTimestamp(@0));

        NSArray *rows = @[
            @{@"name": @"t1_a", @"relevance": @3, @"score": @1, @"created_utc": @20},
            @{@"name": @"t1_z", @"relevance": @3, @"score": @1, @"created_utc": @30},
            @{@"name": @"t1_b", @"relevance": @1, @"score": @90, @"created_utc": @50},
            @{@"name": @"t1_x"}];
        CHECK([ApolloCommentSearchSorted(rows, @"relevance").firstObject[@"name"] isEqual:@"t1_z"]);
        CHECK([ApolloCommentSearchSorted(rows, @"top").firstObject[@"name"] isEqual:@"t1_b"]);
        CHECK([ApolloCommentSearchSorted(rows, @"new").firstObject[@"name"] isEqual:@"t1_b"]);
        CHECK([ApolloCommentSearchSorted(rows, @"old").firstObject[@"name"] isEqual:@"t1_a"]);
        CHECK([ApolloCommentSearchSorted(rows, @"old").lastObject[@"name"] isEqual:@"t1_x"]);
        CHECK(!ApolloCommentSearchSorted(@[], @"new").count);
        NSString *longText = [[@"Earlier. " stringByPaddingToLength:720 withString:@"Earlier. " startingAtIndex:0] stringByAppendingString:@"Apollo Search is here."];
        NSString *preview = ApolloCommentSearchExcerpt(longText, terms);
        CHECK([preview hasPrefix:@"…"] && [preview containsString:@"Apollo Search"]);
        CHECK([ApolloCommentSearchExcerpt(@"Hello", terms) isEqual:@"Hello"]);
        printf("Comment search model: %d failures\n", failures);
    }
    return failures ? 1 : 0;
}
