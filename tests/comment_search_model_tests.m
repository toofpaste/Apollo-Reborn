#import <Foundation/Foundation.h>
#import "ApolloCommentSearch.h"
static int failures;
#define CHECK(x) do { if (!(x)) { fprintf(stderr,"FAIL %d: %s\n",__LINE__,#x); failures++; } } while (0)
int main(void) {
    @autoreleasepool {
        NSDictionary *terms=ApolloCommentSearchTerms(@"subreddit:apolloapp search author:example-user");
        CHECK([terms[@"subreddit"] isEqual:@"apolloapp"]);
        CHECK([terms[@"author"] isEqual:@"example-user"]);
        CHECK([terms[@"text"] isEqual:@"search"]);
        CHECK([ApolloCommentSearchTerms(@"ordinary search")[@"text"] isEqual:@"ordinary search"]);
        CHECK([ApolloCommentSearchTerms(@"  apollo \n search\t subreddit:apolloapp ")[@"text"] isEqual:@"apollo search"]);
        CHECK(ApolloCommentSearchRelevance(@"Search in APOLLO",@"apollo search")==2);
        NSArray *rows=@[
            @{@"name":@"t1_a",@"body":@"apollo search",@"score":@1,@"created_utc":@20},
            @{@"name":@"t1_b",@"body":@"apollo",@"score":@90,@"created_utc":@10},
            @{@"name":@"t1_c",@"body":@"unrelated",@"score":@4,@"created_utc":@30}];
        CHECK([ApolloCommentSearchSorted(rows,@"relevance",@"apollo search").firstObject[@"name"] isEqual:@"t1_a"]);
        CHECK([ApolloCommentSearchSorted(rows,@"top",@"").firstObject[@"name"] isEqual:@"t1_b"]);
        CHECK([ApolloCommentSearchSorted(rows,@"new",@"").firstObject[@"name"] isEqual:@"t1_c"]);
        CHECK([ApolloCommentSearchSorted(rows,@"old",@"").firstObject[@"name"] isEqual:@"t1_b"]);
        CHECK(ApolloCommentSearchSorted(@[],@"new",@"").count==0);
        printf("Comment search model: %d failures\n",failures);
    }
    return failures ? 1 : 0;
}
