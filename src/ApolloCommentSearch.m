#import "ApolloCommentSearch.h"
#import "ApolloState.h"
#import "ApolloGoogleSearch.h"

static NSString *const Recent = @"Recent comments";
static NSString *const Related = @"Related communities";
static NSString *const Threads = @"Threads";
static NSString *const PullPush = @"PullPush";
static NSString *const Arctic = @"Arctic Shift";
static const NSUInteger BatchLimit = 10;
static const NSTimeInterval Day = 24 * 60 * 60;

static NSString *String(id value) { return [value isKindOfClass:NSString.class] ? value : @""; }

static NSString *ResponseError(NSInteger status) {
    if (!status) return @"network error";
    if (status >= 200 && status < 300) return @"invalid response";
    return [NSString stringWithFormat:@"unavailable (%ld)", (long)status];
}

static NSArray *Children(id listing) {
    id data = [listing isKindOfClass:NSDictionary.class] ? listing[@"data"] : nil;
    return [data isKindOfClass:NSDictionary.class] && [data[@"children"] isKindOfClass:NSArray.class] ? data[@"children"] : nil;
}

static NSDictionary *ChildData(id child, NSString *kind) {
    return [child isKindOfClass:NSDictionary.class] && [child[@"kind"] isEqual:kind] && [child[@"data"] isKindOfClass:NSDictionary.class] ? child[@"data"] : nil;
}

@interface ApolloCommentSearch ()
@property(nonatomic, strong) NSMutableArray<NSURLSessionDataTask *> *tasks;
@property(nonatomic, strong) NSMutableDictionary *items, *statuses, *cursors, *posts;
@property(nonatomic, strong) NSMutableSet *active, *exhausted, *scannedPosts;
@property(nonatomic, strong) NSMutableSet *checkedTitles, *checkedArchiveTitles;
@property(nonatomic, copy) NSDictionary *terms;
@property(nonatomic, copy) NSString *sort, *token;
@property(nonatomic, copy) NSArray<NSString *> *relatedSubs;
@property(nonatomic, copy) NSArray<NSString *> *arcticScopes;
@property(nonatomic, strong) NSMutableSet *finishedArchiveScopes, *arcticListingScopes;
@property(nonatomic, copy) NSArray<NSDictionary *> *olderPullPushRows;
@property(nonatomic) NSTimeInterval newestPullPushMatch;
@property(nonatomic) NSTimeInterval after;
@property(nonatomic) NSUInteger generation, pages;
@property(nonatomic) BOOL loadingTitles;
@property(nonatomic) BOOL waitingForArchiveScope;
@property(nonatomic) BOOL triedArchiveCommunity, arcticUnavailable;
@end

@implementation ApolloCommentSearch
- (void)cancel {
    self.generation++;
    for (NSURLSessionDataTask *task in self.tasks) [task cancel];
    [self.tasks removeAllObjects];
    [self.active removeAllObjects];
}

- (void)search:(NSString *)query sort:(NSString *)sort time:(NSString *)time {
    [self cancel];
    self.tasks = [NSMutableArray array];
    self.items = [NSMutableDictionary dictionary];
    self.statuses = [NSMutableDictionary dictionary];
    self.cursors = [NSMutableDictionary dictionary];
    self.posts = [NSMutableDictionary dictionary];
    self.exhausted = [NSMutableSet set];
    self.scannedPosts = [NSMutableSet set];
    self.checkedTitles = [NSMutableSet set];
    self.checkedArchiveTitles = [NSMutableSet set];
    self.loadingTitles = NO;
    self.waitingForArchiveScope = NO;
    self.triedArchiveCommunity = NO;
    self.arcticUnavailable = NO;
    self.arcticScopes = nil;
    self.finishedArchiveScopes = [NSMutableSet set];
    self.arcticListingScopes = [NSMutableSet set];
    self.olderPullPushRows = nil;
    self.newestPullPushMatch = 0;
    self.pages = 0;
    self.terms = ApolloCommentSearchTerms(query);
    if (![self.terms[@"text"] length] && !self.terms[@"subreddit"] && !self.terms[@"author"]) {
        if (self.updated) self.updated(@[], @"Enter a keyword, subreddit or author.", NO, NO);
        return;
    }
    self.sort = sort;
    self.token = ApolloActiveAccountRedditBearerToken();
    self.relatedSubs = nil;
    NSDictionary *windows = @{@"hour": @3600, @"day": @86400, @"week": @604800, @"month": @2592000, @"year": @31536000};
    self.after = windows[time] ? NSDate.date.timeIntervalSince1970 - [windows[time] doubleValue] : 0;
    if (self.terms[@"subreddit"] || self.terms[@"author"]) [self.exhausted addObject:Related];
    if (![self.terms[@"text"] length] || self.terms[@"author"]) [self.exhausted addObject:Threads];
    [self loadMore];
}

- (NSURL *)url:(NSString *)base params:(NSDictionary *)params {
    NSURLComponents *url = [NSURLComponents componentsWithString:base];
    NSMutableArray *items = [NSMutableArray array];
    for (NSString *key in params) {
        NSString *value = [params[key] description];
        if (value.length) [items addObject:[NSURLQueryItem queryItemWithName:key value:value]];
    }
    url.queryItems = items;
    // Reddit decodes query parameters as form data. Preserve literal '+' in keywords.
    url.percentEncodedQuery = [url.percentEncodedQuery stringByReplacingOccurrencesOfString:@"+" withString:@"%2B"];
    return url.URL;
}

- (NSString *)reddit {
    return self.token.length ? @"https://oauth.reddit.com" : @"https://www.reddit.com";
}

- (void)get:(NSURL *)url completion:(void (^)(id, NSInteger))completion {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:20];
    [NSURLProtocol setProperty:@YES forKey:@"ApolloSearchOwnsFilters" inRequest:request];
    BOOL reddit = [url.host isEqual:@"oauth.reddit.com"] || [url.host isEqual:@"www.reddit.com"];
    if ([url.host isEqual:@"oauth.reddit.com"] && self.token.length) [request setValue:[@"Bearer " stringByAppendingString:self.token] forHTTPHeaderField:@"Authorization"];
    [request setValue:reddit ? (sUserAgent ?: @"ApolloReborn") : @"ApolloReborn" forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    NSUInteger generation = self.generation;
    __weak typeof(self) weakSelf = self;
    __block __weak NSURLSessionDataTask *weakTask;
    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
        id json = data && !error && status >= 200 && status < 300 ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!weakSelf || weakSelf.generation != generation) return;
            [weakSelf.tasks removeObject:weakTask];
            completion(json, error ? 0 : status);
        });
    }];
    weakTask = task;
    [self.tasks addObject:task];
    [task resume];
}

- (void)rememberPost:(NSDictionary *)post {
    NSString *identifier = String(post[@"id"]);
    NSString *title = String(post[@"title"]);
    if (identifier.length && title.length) self.posts[identifier] = @{@"title": title, @"subreddit": String(post[@"subreddit"])};
}

// Resolve missing parent titles in batches. Only IDs already supplied by an
// archive are eligible for an archive lookup if Reddit omits the parent.
- (void)lookupTitles:(NSArray *)ids archive:(BOOL)archive {
    self.loadingTitles = YES;
    NSMutableSet *checked = archive ? self.checkedArchiveTitles : self.checkedTitles;
    [checked addObjectsFromArray:ids];
    NSString *base = archive ? @"https://arctic-shift.photon-reddit.com/api/posts/ids" : [[self reddit] stringByAppendingString:@"/api/info.json"];
    NSMutableArray *names = [NSMutableArray array];
    for (NSString *identifier in ids) [names addObject:archive ? identifier : [@"t3_" stringByAppendingString:identifier]];
    NSString *joined = [names componentsJoinedByString:@","];
    NSDictionary *params = archive ? @{@"ids": joined, @"fields": @"id,title,subreddit"} : @{@"id": joined, @"raw_json": @1};
    [self get:[self url:base params:params] completion:^(id json, NSInteger status) {
        if (status >= 200 && status < 300 && json) {
            if (archive) {
                NSArray *posts = [json isKindOfClass:NSDictionary.class] && [json[@"data"] isKindOfClass:NSArray.class] ? json[@"data"] : nil;
                for (id post in posts) if ([post isKindOfClass:NSDictionary.class]) [self rememberPost:post];
            } else {
                for (id child in Children(json)) [self rememberPost:ChildData(child, @"t3")];
            }
        }
        self.loadingTitles = NO;
        [self publish];
    }];
}

- (void)publish {
    NSMutableArray *rows = [NSMutableArray arrayWithCapacity:self.items.count];
    NSMutableOrderedSet *missing = [NSMutableOrderedSet orderedSet], *archiveMissing = [NSMutableOrderedSet orderedSet];
    for (NSDictionary *item in self.items.allValues) {
        NSString *postID = item[@"link_id"];
        NSDictionary *post = self.posts[postID];
        NSDictionary *row = item;
        if (post && (![item[@"link_title"] length] || ![item[@"subreddit"] length])) {
            NSMutableDictionary *withPost = [item mutableCopy];
            if (![item[@"link_title"] length]) withPost[@"link_title"] = post[@"title"];
            if (![item[@"subreddit"] length]) withPost[@"subreddit"] = post[@"subreddit"];
            row = withPost;
        }
        if (postID.length && ![row[@"link_title"] length]) {
            if (![self.checkedTitles containsObject:postID]) [missing addObject:postID];
            else if (![self.checkedArchiveTitles containsObject:postID] &&
                     ([row[@"sources"] containsObject:PullPush] || [row[@"sources"] containsObject:Arctic])) [archiveMissing addObject:postID];
        }
        [rows addObject:row];
    }
    if (!self.loadingTitles && (missing.count || archiveMissing.count)) {
        NSArray *ids = missing.count ? missing.array : archiveMissing.array;
        [self lookupTitles:[ids subarrayWithRange:NSMakeRange(0, MIN(ids.count, 100))] archive:!missing.count];
    }
    NSMutableArray *labels = [NSMutableArray array];
    for (NSString *source in @[Recent, Related, Threads, PullPush, Arctic]) {
        if (self.statuses[source]) [labels addObject:[NSString stringWithFormat:@"%@: %@", source, self.statuses[source]]];
    }
    BOOL more = self.olderPullPushRows.count || (self.pages < BatchLimit && self.exhausted.count < 5);
    if (!self.active.count && self.olderPullPushRows.count) [labels addObject:@"Older archive matches available"];
    if (self.updated) self.updated(ApolloCommentSearchSorted(rows, self.sort), [labels componentsJoinedByString:@" • "], self.active.count > 0, more);
}

- (void)finish:(NSString *)source status:(NSString *)status {
    self.statuses[source] = status;
    [self.active removeObject:source];
    if (self.waitingForArchiveScope && [source isEqual:PullPush]) {
        self.waitingForArchiveScope = NO;
        [self startScopedSources];
    }
    if (!self.active.count && self.olderPullPushRows.count) {
        BOOL foundNewer = NO;
        for (NSDictionary *row in self.items.allValues) {
            if ([row[@"created_utc"] doubleValue] > self.newestPullPushMatch) { foundNewer = YES; break; }
        }
        if (!foundNewer && ![self searchAnotherArchiveCommunity]) [self includeOlderPullPushRows];
    }
    [self publish];
}

- (void)addRow:(NSDictionary *)row source:(NSString *)source {
    NSString *name = row[@"name"];
    NSMutableDictionary *merged = [ApolloCommentSearchMerge(self.items[name], row, source) mutableCopy];
    merged[@"excerpt"] = ApolloCommentSearchExcerpt(ApolloGoogleSearchPlainTextFromMarkdown(merged[@"body"]), self.terms);
    self.items[name] = merged;
    if ([row[@"link_title"] length] && [row[@"link_id"] length] && !self.posts[row[@"link_id"]]) {
        self.posts[row[@"link_id"]] = @{@"title": row[@"link_title"], @"subreddit": row[@"subreddit"]};
    }
}

- (BOOL)add:(NSDictionary *)raw post:(NSDictionary *)post source:(NSString *)source {
    NSDictionary *row = ApolloCommentSearchRow(raw, post, self.terms, self.after);
    if (!row) return NO;
    [self addRow:row source:source];
    return YES;
}

- (void)includeOlderPullPushRows {
    for (NSDictionary *row in self.olderPullPushRows) [self addRow:row source:PullPush];
    self.olderPullPushRows = nil;
}

- (BOOL)searchAnotherArchiveCommunity {
    if (self.triedArchiveCommunity || self.arcticUnavailable || self.terms[@"subreddit"] || self.terms[@"author"]) return NO;
    // Post search can point at communities where the keyword is in post titles
    // only. Try the most frequent unsearched community in actual comment hits.
    NSCountedSet *counts = [NSCountedSet set];
    NSString *best = nil;
    for (NSDictionary *row in self.olderPullPushRows) {
        NSString *sub = [row[@"subreddit"] lowercaseString];
        if (!sub.length || [self.arcticScopes containsObject:sub]) continue;
        [counts addObject:sub];
        if (!best || [counts countForObject:sub] > [counts countForObject:best]) best = sub;
    }
    if (!best) return NO;
    self.triedArchiveCommunity = YES;
    self.arcticScopes = [(self.arcticScopes ?: @[]) arrayByAddingObject:best];
    [self.exhausted removeObject:Arctic];
    [self.active addObject:Arctic];
    self.statuses[Arctic] = [NSString stringWithFormat:@"checking r/%@", best];
    [self archive:Arctic scopes:@[best] index:0 summaries:[NSMutableArray array]];
    return YES;
}

- (BOOL)shouldDeferPullPushRows:(NSArray *)rows {
    if (self.pages != 1 || !([self.sort isEqual:@"relevance"] || [self.sort isEqual:@"new"])) return NO;
    if (rows.count < 10 || self.newestPullPushMatch <= 0 || self.newestPullPushMatch > NSDate.date.timeIntervalSince1970 - 7 * Day) return NO;
    NSUInteger nearNewest = 0;
    for (NSDictionary *row in rows) {
        if ([row[@"created_utc"] doubleValue] > self.newestPullPushMatch - Day) nearNewest++;
    }
    return nearNewest * 2 > rows.count;
}

static NSString *ArchiveCursorKey(NSString *source, NSString *scope) {
    return [NSString stringWithFormat:@"%@/%@", source, scope.lowercaseString];
}

- (void)fetchArchive:(NSString *)source scope:(NSString *)scope completion:(void (^)(NSString *, NSInteger))completion {
    BOOL arctic = [source isEqual:Arctic];
    BOOL ascending = [self.sort isEqual:@"old"];
    NSString *key = ArchiveCursorKey(source, scope);
    NSUInteger limit = arctic ? 100 / MAX((NSUInteger)1, self.arcticScopes.count) : 100;
    NSMutableDictionary *params = [@{arctic ? @"body" : @"q": self.terms[@"text"], arctic ? @"limit" : @"size": @(limit), @"sort": ascending ? @"asc" : @"desc"} mutableCopy];
    if (arctic) params[@"body"] = [self.arcticListingScopes containsObject:key] ? nil : [self.terms[@"text"] stringByReplacingOccurrencesOfString:@"\"" withString:@""];
    else params[@"sort_type"] = @"created_utc";
    if (scope.length) params[@"subreddit"] = scope;
    if (self.terms[@"author"]) params[@"author"] = self.terms[@"author"];
    if (self.after) params[@"after"] = @((long long)self.after);
    if (self.cursors[key]) params[ascending ? @"after" : @"before"] = self.cursors[key];
    NSString *base = arctic ? @"https://arctic-shift.photon-reddit.com/api/comments/search" : @"https://api.pullpush.io/reddit/search/comment/";
    [self get:[self url:base params:params] completion:^(id json, NSInteger status) {
        // Busy communities can reject Arctic Shift's body index. Its scoped
        // chronological listing still accepts the date range and cursor.
        if (arctic && [params[@"body"] length] && (status == 400 || status == 422)) {
            [self.arcticListingScopes addObject:key];
            [self fetchArchive:source scope:scope completion:completion];
            return;
        }
        NSArray *data = [json isKindOfClass:NSDictionary.class] && [json[@"data"] isKindOfClass:NSArray.class] ? json[@"data"] : nil;
        id message = data ? json[@"error"] : nil;
        if (!data || ([message isKindOfClass:NSString.class] && [message length]) ||
            ([message isKindOfClass:NSDictionary.class] && [message count])) {
            completion(ResponseError(status), status);
            return;
        }
        NSNumber *edge = nil;
        NSMutableArray *matches = [NSMutableArray array];
        for (id raw in data) {
            if (![raw isKindOfClass:NSDictionary.class]) continue;
            NSDictionary *row = ApolloCommentSearchRow(raw, nil, self.terms, self.after);
            if (row) {
                [matches addObject:row];
                if (!arctic && !ascending) self.newestPullPushMatch = MAX(self.newestPullPushMatch, [row[@"created_utc"] doubleValue]);
            }
            NSNumber *created = ApolloCommentSearchTimestamp(raw[@"created_utc"]);
            if (created && (!edge || (ascending ? created.doubleValue > edge.doubleValue : created.doubleValue < edge.doubleValue))) edge = created;
        }
        if (!arctic && [self shouldDeferPullPushRows:matches]) {
            // Show a real hit immediately, even when the fresher sources are slow.
            NSArray *ordered = ApolloCommentSearchSorted(matches, self.sort);
            [self addRow:ordered.firstObject source:source];
            self.olderPullPushRows = [ordered subarrayWithRange:NSMakeRange(1, ordered.count - 1)];
        } else {
            for (NSDictionary *row in matches) [self addRow:row source:source];
        }
        NSNumber *last = self.cursors[key];
        if (data.count < limit || !edge || (last && (ascending ? edge.doubleValue <= last.doubleValue : edge.doubleValue >= last.doubleValue))) [self.finishedArchiveScopes addObject:key];
        else self.cursors[key] = @(edge.longLongValue);
        NSString *summary = [NSString stringWithFormat:@"%lu scanned", (unsigned long)data.count];
        if (!arctic && self.newestPullPushMatch > 0) {
            NSString *date = [NSDateFormatter localizedStringFromDate:[NSDate dateWithTimeIntervalSince1970:self.newestPullPushMatch]
                                                           dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterNoStyle];
            summary = [summary stringByAppendingFormat:@", latest match %@", date];
        }
        completion(summary, status);
    }];
}

// One Arctic request at a time. Each community keeps its own keyword/listing
// fallback, timestamp cursor and exhaustion state across user-requested pages.
- (void)archive:(NSString *)source scopes:(NSArray<NSString *> *)scopes index:(NSUInteger)index summaries:(NSMutableArray *)summaries {
    while (index < scopes.count && [self.finishedArchiveScopes containsObject:ArchiveCursorKey(source, scopes[index])]) index++;
    if (index == scopes.count) {
        BOOL done = YES;
        NSArray *allScopes = [source isEqual:Arctic] ? self.arcticScopes : scopes;
        for (NSString *scope in allScopes) if (![self.finishedArchiveScopes containsObject:ArchiveCursorKey(source, scope)]) done = NO;
        if (done) [self.exhausted addObject:source];
        [self finish:source status:[summaries componentsJoinedByString:@", "]];
        return;
    }
    NSString *scope = scopes[index];
    [self fetchArchive:source scope:scope completion:^(NSString *summary, NSInteger status) {
        [summaries addObject:([source isEqual:Arctic] && scope.length) ? [NSString stringWithFormat:@"r/%@ %@", scope, summary] : summary];
        if ([source isEqual:Arctic] && (!status || status == 429 || status >= 500)) self.arcticUnavailable = YES;
        if (status == 429) { [self finish:source status:[summaries componentsJoinedByString:@", "]]; return; }
        if (index + 1 < scopes.count) [self publish];
        [self archive:source scopes:scopes index:index + 1 summaries:summaries];
    }];
}

// Only advance a listing with its own next cursor. Search and comment feeds
// use different fullname types, and the related-community list is frozen per search.
- (BOOL)advance:(NSString *)key listing:(NSDictionary *)listing {
    NSString *next = String(listing[@"data"][@"after"]);
    if (!next.length || [self.cursors[key] isEqual:next]) return NO;
    self.cursors[key] = next;
    return YES;
}

- (void)recent:(NSString *)source path:(NSString *)path pagesLeft:(NSUInteger)pagesLeft scanned:(NSUInteger)scanned {
    NSMutableDictionary *params = [@{@"limit": @100, @"sort": @"new", @"raw_json": @1} mutableCopy];
    if (self.cursors[source]) params[@"after"] = self.cursors[source];
    [self get:[self url:[[self reddit] stringByAppendingString:path] params:params] completion:^(id json, NSInteger status) {
        NSArray *children = Children(json);
        if (!children) { [self finish:source status:ResponseError(status)]; return; }
        NSUInteger matches = 0;
        double newest = 0;
        for (id child in children) {
            NSDictionary *raw = ChildData(child, @"t1");
            if (!raw) continue;
            newest = MAX(newest, ApolloCommentSearchTimestamp(raw[@"created_utc"]).doubleValue);
            if ([self add:raw post:nil source:@"Reddit"]) matches++;
        }
        NSUInteger total = scanned + children.count;
        if (![self advance:source listing:json] || (newest > 0 && newest < self.after)) [self.exhausted addObject:source];
        else if (!matches && pagesLeft > 1) {
            [self recent:source path:path pagesLeft:pagesLeft - 1 scanned:total];
            return;
        }
        [self finish:source status:[NSString stringWithFormat:@"%lu scanned", (unsigned long)total]];
    }];
}

- (void)walk:(id)listing post:(NSDictionary *)post {
    for (id child in Children(listing)) {
        NSDictionary *raw = ChildData(child, @"t1");
        if (!raw) continue;
        [self add:raw post:post source:@"Reddit"];
        [self walk:raw[@"replies"] post:post];
    }
}

- (void)scanThreads:(NSArray *)posts index:(NSUInteger)index failed:(NSUInteger)failed discoveryError:(NSString *)discoveryError {
    if (index == posts.count) {
        NSString *status = [NSString stringWithFormat:@"%lu scanned%@", (unsigned long)(posts.count - failed), failed || discoveryError ? @" (partial)" : @""];
        [self finish:Threads status:posts.count ? status : (discoveryError ?: status)];
        return;
    }
    NSDictionary *post = posts[index];
    NSString *path = [NSString stringWithFormat:@"/comments/%@.json", post[@"id"]];
    NSString *sort = !self.after && [@[@"old", @"top"] containsObject:self.sort] ? self.sort : @"new";
    NSURL *url = [self url:[[self reddit] stringByAppendingString:path] params:@{@"limit": @100, @"depth": @8, @"sort": sort, @"raw_json": @1}];
    [self get:url completion:^(id json, NSInteger status) {
        BOOL valid = status == 200 && [json isKindOfClass:NSArray.class] && [json count] >= 2 && Children(json[1]);
        if (valid) {
            NSDictionary *parent = ChildData(Children(json[0]).firstObject, @"t3") ?: post;
            [self rememberPost:parent];
            [self walk:json[1] post:parent];
            [self.scannedPosts addObject:post[@"id"]];
            [self publish];
        }
        [self scanThreads:posts index:index + 1 failed:failed + !valid discoveryError:discoveryError];
    }];
}

- (void)startScopedSources {
    if (!self.relatedSubs.count && !self.terms[@"subreddit"] && !self.terms[@"author"]) {
        // A term may occur only in replies. Communities from matching archive
        // comments can still supply a targeted live feed when post search is empty.
        NSMutableOrderedSet *subs = [NSMutableOrderedSet orderedSet];
        for (NSDictionary *row in ApolloCommentSearchSorted(self.items.allValues, @"new")) {
            if ([row[@"sources"] containsObject:PullPush] && [row[@"subreddit"] length]) [subs addObject:row[@"subreddit"]];
            if (subs.count == 5) break;
        }
        for (NSDictionary *row in self.olderPullPushRows) {
            if (subs.count >= 5) break;
            if ([row[@"subreddit"] length]) [subs addObject:row[@"subreddit"]];
        }
        self.relatedSubs = subs.array;
        if (!subs.count && [self.active containsObject:PullPush]) {
            self.waitingForArchiveScope = YES;
            return;
        }
    }
    if ([self.active containsObject:Related]) {
        if (self.relatedSubs.count) {
            NSString *path = [NSString stringWithFormat:@"/r/%@/comments.json", [self.relatedSubs componentsJoinedByString:@"+"]];
            [self recent:Related path:path pagesLeft:3 scanned:0];
        } else {
            if ([self.exhausted containsObject:Threads] && [self.exhausted containsObject:PullPush]) [self.exhausted addObject:Related];
            [self finish:Related status:@"no community found"];
        }
    }
    if ([self.active containsObject:Arctic]) {
        if (self.terms[@"subreddit"] || self.terms[@"author"]) self.arcticScopes = @[self.terms[@"subreddit"] ?: @""];
        else if (!self.arcticScopes.count) {
            NSMutableOrderedSet *scopes = [NSMutableOrderedSet orderedSet];
            for (NSString *sub in self.relatedSubs) {
                [scopes addObject:sub.lowercaseString];
                if (scopes.count == 3) break;
            }
            self.arcticScopes = scopes.array;
        }
        if (self.arcticScopes.count) [self archive:Arctic scopes:self.arcticScopes index:0 summaries:[NSMutableArray array]];
        else {
            if ([self.exhausted containsObject:Threads] && [self.exhausted containsObject:PullPush]) [self.exhausted addObject:Arctic];
            [self finish:Arctic status:@"no community found"];
        }
    }
}

- (void)findThreads {
    // Query both the relevant and newest matching posts. A comment's date
    // filter must never exclude an old parent that has a new reply.
    NSArray *sorts = @[@"relevance", @"new"];
    NSMutableArray *open = [NSMutableArray array];
    for (NSString *sort in sorts) if (self.cursors[sort] != NSNull.null) [open addObject:sort];
    __block NSUInteger remaining = open.count;
    __block NSString *discoveryError = nil;
    NSMutableDictionary *pages = [NSMutableDictionary dictionary];
    for (NSString *sort in open) {
        NSString *scope = self.terms[@"subreddit"];
        NSString *path = scope.length ? [NSString stringWithFormat:@"/r/%@/search.json", scope] : @"/search.json";
        NSMutableDictionary *params = [@{@"q": self.terms[@"text"], @"type": @"link", @"limit": [sort isEqual:@"new"] ? @3 : @2,
                                         @"sort": sort, @"raw_json": @1, @"include_over_18": @"on"} mutableCopy];
        if (scope.length) params[@"restrict_sr"] = @"on";
        if (self.cursors[sort]) params[@"after"] = self.cursors[sort];
        [self get:[self url:[[self reddit] stringByAppendingString:path] params:params] completion:^(id json, NSInteger status) {
            NSArray *children = Children(json);
            if (!children) discoveryError = ResponseError(status);
            else {
                pages[sort] = children;
                if (![self advance:sort listing:json]) self.cursors[sort] = NSNull.null;
            }
            if (--remaining) return;
            if (self.cursors[@"relevance"] == NSNull.null && self.cursors[@"new"] == NSNull.null) [self.exhausted addObject:Threads];
            NSMutableArray *posts = [NSMutableArray array];
            NSMutableSet *ids = [self.scannedPosts mutableCopy];
            NSMutableOrderedSet *subs = [NSMutableOrderedSet orderedSet];
            for (NSString *order in sorts) {
                for (id child in pages[order]) {
                    NSDictionary *post = ChildData(child, @"t3");
                    NSString *identifier = String(post[@"id"]), *sub = String(post[@"subreddit"]);
                    if (!identifier.length) continue;
                    [self rememberPost:post];
                    if (sub.length && ![post[@"subreddit_type"] isEqual:@"private"]) [subs addObject:sub];
                    if ([ids containsObject:identifier]) continue;
                    [ids addObject:identifier];
                    [posts addObject:post];
                }
            }
            if (!self.terms[@"subreddit"] && !self.relatedSubs.count) {
                self.relatedSubs = subs.array;
                [self startScopedSources];
            }
            [self scanThreads:posts index:0 failed:0 discoveryError:discoveryError];
        }];
    }
}

- (void)loadMore {
    if (self.active.count) return;
    if (self.olderPullPushRows.count) {
        [self includeOlderPullPushRows];
        [self publish];
        return;
    }
    if (self.pages >= BatchLimit) return;
    self.active = [NSMutableSet setWithArray:@[Recent, Related, Threads, PullPush, Arctic]];
    [self.active minusSet:self.exhausted];
    if (!self.active.count) return;
    self.pages++;
    for (NSString *source in self.active) self.statuses[source] = @"searching";
    [self publish];
    if ([self.active containsObject:Recent]) {
        NSString *author = self.terms[@"author"];
        NSString *path = author ? [NSString stringWithFormat:@"/user/%@/comments.json", author] :
            [NSString stringWithFormat:@"/r/%@/comments.json", self.terms[@"subreddit"] ?: @"all"];
        [self recent:Recent path:path pagesLeft:3 scanned:0];
    }
    if ([self.active containsObject:PullPush]) [self archive:PullPush scopes:@[self.terms[@"subreddit"] ?: @""] index:0 summaries:[NSMutableArray array]];
    if (self.terms[@"subreddit"] || self.terms[@"author"] || self.relatedSubs.count || ![self.active containsObject:Threads]) [self startScopedSources];
    if ([self.active containsObject:Threads]) [self findThreads];
}

- (void)dealloc {
    for (NSURLSessionDataTask *task in _tasks) [task cancel];
}
@end
