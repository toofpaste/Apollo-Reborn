#import "ApolloCommentSearch.h"
#import "ApolloState.h"
#import "ApolloGoogleSearch.h"
#include <float.h>

static NSString *String(id value) { return [value isKindOfClass:NSString.class] ? value : @""; }
@interface ApolloCommentSearch ()
@property(nonatomic, strong) NSMutableArray<NSURLSessionDataTask *> *tasks;
@property(nonatomic, strong) NSMutableDictionary *items;
@property(nonatomic, strong) NSMutableDictionary *statuses;
@property(nonatomic, strong) NSMutableDictionary *cursors;
@property(nonatomic, strong) NSMutableSet *exhausted;
@property(nonatomic, copy) NSDictionary *terms;
@property(nonatomic, copy) NSString *query;
@property(nonatomic, copy) NSString *sort;
@property(nonatomic, copy) NSString *token;
@property(nonatomic, copy) NSString *archiveScope;
@property(nonatomic) NSTimeInterval after;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) NSInteger pending;
@property(nonatomic) NSUInteger pages;
@end
@implementation ApolloCommentSearch
- (instancetype)init { if ((self=[super init])) { _tasks=[NSMutableArray array]; _items=[NSMutableDictionary dictionary]; _statuses=[NSMutableDictionary dictionary]; _cursors=[NSMutableDictionary dictionary]; _exhausted=[NSMutableSet set]; } return self; }
- (void)cancel { self.generation++; for (NSURLSessionDataTask *task in self.tasks) [task cancel]; [self.tasks removeAllObjects]; self.pending=0; }
- (void)search:(NSString *)query sort:(NSString *)sort time:(NSString *)time {
    [self cancel]; [self.items removeAllObjects]; [self.statuses removeAllObjects]; [self.cursors removeAllObjects]; [self.exhausted removeAllObjects]; self.pages=0;
    self.query=query; self.terms=ApolloCommentSearchTerms(query); self.archiveScope=self.terms[@"subreddit"]; self.sort=sort; self.token=ApolloActiveAccountRedditBearerToken();
    NSDictionary *windows=@{@"hour":@3600,@"day":@86400,@"week":@604800,@"month":@2592000,@"year":@31536000};
    self.after=windows[time] ? NSDate.date.timeIntervalSince1970-[windows[time] doubleValue] : 0;
    [self loadMore];
}
- (NSURL *)url:(NSString *)base params:(NSDictionary *)params {
    NSURLComponents *url=[NSURLComponents componentsWithString:base]; NSMutableArray *items=[NSMutableArray array];
    for (NSString *key in params) if ([params[key] description].length) [items addObject:[NSURLQueryItem queryItemWithName:key value:[params[key] description]]];
    url.queryItems=items; return url.URL;
}
- (NSString *)reddit { return self.token.length ? @"https://oauth.reddit.com" : @"https://www.reddit.com"; }
- (void)get:(NSURL *)url completion:(void (^)(id, NSString *))completion {
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:20];
    [NSURLProtocol setProperty:@YES forKey:@"ApolloSearchOwnsFilters" inRequest:request];
    if ([url.host hasSuffix:@"reddit.com"] && self.token.length) [request setValue:[@"Bearer " stringByAppendingString:self.token] forHTTPHeaderField:@"Authorization"];
    [request setValue:[url.host hasSuffix:@"reddit.com"] ? (sUserAgent ?: @"ApolloReborn") : @"ApolloReborn" forHTTPHeaderField:@"User-Agent"];
    NSUInteger generation=self.generation;
    __weak typeof(self) weakSelf=self;
    NSURLSessionDataTask *task=[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status=[response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
        id json=data && !error ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!weakSelf || weakSelf.generation!=generation) return;
            completion(json, error || status<200 || status>=300 || !json ? [NSString stringWithFormat:@"unavailable (%@)",error ? @"network" : @(status).stringValue] : nil);
        });
    }]; [self.tasks addObject:task]; [task resume];
}
- (void)publish {
    NSArray *sorted=ApolloCommentSearchSorted(self.items.allValues,self.sort,self.terms[@"text"]);
    NSMutableArray *labels=[NSMutableArray array];
    for (NSString *source in @[@"Reddit",@"PullPush",@"Arctic Shift"]) if (self.statuses[source]) [labels addObject:[NSString stringWithFormat:@"%@: %@",source,self.statuses[source]]];
    if (self.updated) self.updated(sorted,[[labels componentsJoinedByString:@" • "] stringByAppendingString:@"\nSort applies to loaded matches; archive coverage varies."],self.pending>0,self.pages<10 && self.exhausted.count<3);
}
- (void)add:(NSDictionary *)raw source:(NSString *)source {
    if (![raw isKindOfClass:NSDictionary.class]) return;
    NSString *body=String(raw[@"body"]), *identifier=String(raw[@"id"]);
    if (!identifier.length || !body.length || [@[@"[deleted]",@"[removed]"] containsObject:body]) return;
    NSString *text=[self.terms[@"text"] stringByReplacingOccurrencesOfString:@"\"" withString:@""];
    if (text.length && ![body.lowercaseString containsString:text.lowercaseString] && ApolloCommentSearchRelevance(body,text)<(NSInteger)[text componentsSeparatedByString:@" "].count) return;
    for (NSString *field in @[@"author",@"subreddit"]) if (self.terms[field] && [String(raw[field]) caseInsensitiveCompare:self.terms[field]]!=NSOrderedSame) return;
    NSNumber *created=[raw[@"created_utc"] isKindOfClass:NSNumber.class] ? raw[@"created_utc"] : @0;
    if (created.doubleValue<self.after) return;
    NSString *name=[@"t1_" stringByAppendingString:identifier];
    NSDictionary *previous=self.items[name];
    NSMutableOrderedSet *sources=[NSMutableOrderedSet orderedSetWithArray:previous[@"sources"] ?: @[]]; [sources addObject:source];
    if (previous && [previous[@"sources"] containsObject:@"Reddit"] && ![source isEqual:@"Reddit"]) { NSMutableDictionary *copy=[previous mutableCopy];copy[@"sources"]=sources.array;self.items[name]=copy;return; }
    NSString *post=String(raw[@"link_id"]); if ([post hasPrefix:@"t3_"]) post=[post substringFromIndex:3];
    NSString *permalink=String(raw[@"permalink"]); if (!permalink.length && post.length) permalink=[NSString stringWithFormat:@"/comments/%@/_/%@/",post,identifier];
    if (![permalink hasPrefix:@"/"]) return;
    self.items[name]=@{@"name":name,@"title":ApolloGoogleSearchPlainTextFromMarkdown(body),@"body":body,@"subreddit":String(raw[@"subreddit"]),@"author":String(raw[@"author"]),@"permalink":permalink,@"created_utc":created,@"score":[raw[@"score"] isKindOfClass:NSNumber.class] ? raw[@"score"] : @0,@"sources":sources.array};
}
- (void)archive:(NSString *)source scope:(NSString *)scope {
    BOOL arctic=[source isEqual:@"Arctic Shift"];
    BOOL ascending=[self.sort isEqual:@"old"];
    if (arctic && !scope.length && !self.terms[@"author"]) { self.statuses[source]=@"add subreddit: or author: to search archive"; [self.exhausted addObject:source]; self.pending--; [self publish]; return; }
    NSMutableDictionary *params=[@{arctic ? @"body":@"q":self.terms[@"text"], arctic ? @"limit":@"size":@100,@"sort":ascending ? @"asc" : @"desc"} mutableCopy];
    if (arctic) params[@"body"]=[self.terms[@"text"] stringByReplacingOccurrencesOfString:@"\"" withString:@""];
    if (!arctic) params[@"sort_type"]=@"created_utc";
    if (scope.length) params[@"subreddit"]=scope;
    if (self.terms[@"author"]) params[@"author"]=self.terms[@"author"];
    if (self.after) params[@"after"]=@((long long)self.after);
    if (self.cursors[source]) params[ascending ? @"after" : @"before"]=self.cursors[source];
    NSURL *url=[self url:arctic ? @"https://arctic-shift.photon-reddit.com/api/comments/search" : @"https://api.pullpush.io/reddit/search/comment/" params:params];
    [self get:url completion:^(id json, NSString *error) {
        NSArray *data=[json isKindOfClass:NSDictionary.class] && [json[@"data"] isKindOfClass:NSArray.class] ? json[@"data"] : nil;
        if (error || !data) self.statuses[source]=error ?: @"invalid response";
        else {
            double oldest=ascending ? 0 : DBL_MAX;
            for (id item in data) if ([item isKindOfClass:NSDictionary.class]) { [self add:item source:source]; if ([item[@"created_utc"] isKindOfClass:NSNumber.class]) oldest=ascending ? MAX(oldest,[item[@"created_utc"] doubleValue]) : MIN(oldest,[item[@"created_utc"] doubleValue]); }
            if (data.count<100 || oldest==DBL_MAX || oldest==0 || (self.cursors[source] && (ascending ? oldest<=[self.cursors[source] doubleValue] : oldest>=[self.cursors[source] doubleValue]))) [self.exhausted addObject:source];
            else self.cursors[source]=@((long long)oldest);
            self.statuses[source]=[NSString stringWithFormat:@"%lu scanned%@",(unsigned long)data.count, arctic && scope.length ? [@" in r/" stringByAppendingString:scope] : @""];
        }
        self.pending--; [self publish];
    }];
}
- (void)walk:(id)listing {
    if (![listing isKindOfClass:NSDictionary.class] || ![listing[@"data"] isKindOfClass:NSDictionary.class]) return;
    id children=listing[@"data"][@"children"]; if (![children isKindOfClass:NSArray.class]) return;
    for (id child in children) if ([child isKindOfClass:NSDictionary.class] && [child[@"kind"] isEqual:@"t1"] && [child[@"data"] isKindOfClass:NSDictionary.class]) { [self add:child[@"data"] source:@"Reddit"]; [self walk:child[@"data"][@"replies"]]; }
}
- (void)threads:(NSArray *)posts index:(NSUInteger)index failed:(NSUInteger)failed {
    if (index>=posts.count) { self.statuses[@"Reddit"]=[NSString stringWithFormat:@"%lu threads scanned%@",(unsigned long)(posts.count-failed),failed ? @" (some failed)":@""];self.pending--;[self publish];return; }
    NSString *identifier=String(posts[index][@"id"]);
    NSURL *url=[self url:[[self reddit] stringByAppendingFormat:@"/comments/%@.json",identifier] params:@{@"limit":@100,@"depth":@8,@"raw_json":@1,@"sort":[self.sort isEqual:@"new"] ? @"new":@"top"}];
    [self get:url completion:^(id json, NSString *error) {
        BOOL valid=[json isKindOfClass:NSArray.class] && [json count]>1;
        if (valid && !error) [self walk:json[1]];
        [self publish];[self threads:posts index:index+1 failed:failed+(error || !valid)];
    }];
}
- (void)loadMore {
    if (self.pending || self.pages>=10) return;
    [self.tasks removeAllObjects];self.pages++;self.pending=3;
    for (NSString *s in @[@"PullPush",@"Arctic Shift"]) {
        if ([self.exhausted containsObject:s]) { self.pending--;continue; }
        self.statuses[s]=@"searching";
        if ([s isEqual:@"Arctic Shift"] && !self.archiveScope.length && !self.terms[@"author"]) {
            self.statuses[s]=@"waiting for a matching community";
        } else [self archive:s scope:[s isEqual:@"Arctic Shift"] ? self.archiveScope : self.terms[@"subreddit"]];
    }
    if ([self.exhausted containsObject:@"Reddit"]) { self.pending--;[self publish];return; }
    self.statuses[@"Reddit"]=@"finding matching threads";
    NSMutableDictionary *params=[@{@"q":self.query,@"type":@"link",@"limit":@5,@"sort":@"relevance",@"raw_json":@1,@"include_over_18":@"on"} mutableCopy];
    if (self.cursors[@"Reddit"]) params[@"after"]=self.cursors[@"Reddit"];
    [self get:[self url:[[self reddit] stringByAppendingString:@"/search.json"] params:params] completion:^(id json, NSString *error) {
        id listing=[json isKindOfClass:NSDictionary.class] ? json[@"data"] : nil;
        NSArray *children=[listing isKindOfClass:NSDictionary.class] && [listing[@"children"] isKindOfClass:NSArray.class] ? listing[@"children"] : nil;
        if (error || !children) {
            self.statuses[@"Reddit"]=error ?: @"invalid response";self.pending--;
            if (!self.archiveScope.length && !self.terms[@"author"] && ![self.exhausted containsObject:@"Arctic Shift"]) [self archive:@"Arctic Shift" scope:nil];
            [self publish];return;
        }
        NSString *after=String(listing[@"after"]);if (!after.length || [after isEqual:self.cursors[@"Reddit"]]) [self.exhausted addObject:@"Reddit"]; else self.cursors[@"Reddit"]=after;
        NSMutableArray *posts=[NSMutableArray array];for (id child in children) if ([child isKindOfClass:NSDictionary.class] && [child[@"data"] isKindOfClass:NSDictionary.class] && String(child[@"data"][@"id"]).length) [posts addObject:child[@"data"]];
        if (!self.archiveScope.length && !self.terms[@"author"] && ![self.exhausted containsObject:@"Arctic Shift"]) {
            self.archiveScope=String([posts.firstObject objectForKey:@"subreddit"]);
            [self archive:@"Arctic Shift" scope:self.archiveScope];
        }
        [self threads:posts index:0 failed:0];
    }];[self publish];
}
- (void)dealloc { for (NSURLSessionDataTask *task in _tasks) [task cancel]; }
@end
