#import "ApolloCommentSearch.h"
#import <math.h>
#import <dispatch/dispatch.h>

static NSString *String(id value) {
    return [value isKindOfClass:NSString.class] ? value : @"";
}

static NSString *Fold(NSString *text) {
    static NSRegularExpression *whitespace;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        whitespace = [NSRegularExpression regularExpressionWithPattern:@"\\s+" options:0 error:NULL];
    });
    NSString *singleSpaced = [whitespace stringByReplacingMatchesInString:text options:0 range:NSMakeRange(0, text.length) withTemplate:@" "];
    return singleSpaced.lowercaseString;
}

NSDictionary *ApolloCommentSearchTerms(NSString *query) {
    NSMutableDictionary *terms = [NSMutableDictionary dictionary];
    NSMutableArray *text = [NSMutableArray array];
    NSMutableArray *needles = [NSMutableArray array];
    NSRegularExpression *tokens = [NSRegularExpression regularExpressionWithPattern:
        @"\"([^\"]+)\"|(?<!\\S)(author:|subreddit:|u/|r/)([A-Za-z0-9_-]+)(?=\\s|$)|\\S+"
        options:NSRegularExpressionCaseInsensitive error:NULL];
    for (NSTextCheckingResult *match in [tokens matchesInString:query options:0 range:NSMakeRange(0, query.length)]) {
        if ([match rangeAtIndex:2].location != NSNotFound) {
            NSString *prefix = [[query substringWithRange:[match rangeAtIndex:2]] lowercaseString];
            NSString *key = [@[@"author:", @"u/"] containsObject:prefix] ? @"author" : @"subreddit";
            terms[key] = [query substringWithRange:[match rangeAtIndex:3]];
            continue;
        }
        NSString *token = [query substringWithRange:match.range];
        NSString *needle = [token stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\""]];
        if (needle.length) {
            [text addObject:token];
            [needles addObject:Fold(needle)];
        }
    }
    terms[@"text"] = [text componentsJoinedByString:@" "];
    terms[@"needles"] = needles;
    terms[@"phrase"] = [needles componentsJoinedByString:@" "];
    return terms;
}

NSNumber *ApolloCommentSearchTimestamp(id value) {
    double seconds = 0;
    if ([value isKindOfClass:NSNumber.class]) seconds = [value doubleValue];
    else if ([value isKindOfClass:NSString.class]) {
        NSScanner *scanner = [NSScanner scannerWithString:value];
        if (![scanner scanDouble:&seconds] || !scanner.isAtEnd) return nil;
    }
    return isfinite(seconds) && seconds > 0 ? @(seconds) : nil;
}

static NSString *BareID(id value, NSString *prefix) {
    NSString *identifier = String(value).lowercaseString;
    if ([identifier hasPrefix:prefix]) identifier = [identifier substringFromIndex:prefix.length];
    static NSCharacterSet *invalid;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        invalid = [[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789"] invertedSet];
    });
    return [identifier rangeOfCharacterFromSet:invalid].location == NSNotFound ? identifier : @"";
}

NSDictionary *ApolloCommentSearchRow(NSDictionary *raw, NSDictionary *post, NSDictionary *terms, NSTimeInterval after) {
    NSString *identifier = BareID(raw[@"id"] ?: raw[@"name"], @"t1_");
    NSString *body = String(raw[@"body"]);
    if (!identifier.length || !body.length || [body isEqual:@"[deleted]"] || [body isEqual:@"[removed]"]) return nil;
    NSNumber *created = ApolloCommentSearchTimestamp(raw[@"created_utc"]);
    if (created.doubleValue < after) return nil;
    NSString *author = String(raw[@"author"]);
    if (terms[@"author"] && [author caseInsensitiveCompare:terms[@"author"]] != NSOrderedSame) return nil;

    NSString *path = String(raw[@"permalink"]);
    if ([path hasPrefix:@"https://"]) {
        NSURL *url = [NSURL URLWithString:path];
        NSString *host = url.host.lowercaseString;
        path = ([host isEqual:@"reddit.com"] || [host hasSuffix:@".reddit.com"]) ? url.path : @"";
    }
    if (![path hasPrefix:@"/"] || [path hasPrefix:@"//"]) path = @"";
    NSArray *parts = path.pathComponents;
    NSUInteger comments = [parts indexOfObject:@"comments"];
    NSString *postID = BareID(raw[@"link_id"], @"t3_");
    if (!postID.length) postID = BareID(post[@"id"], @"t3_");
    if (!postID.length && comments != NSNotFound && comments + 1 < parts.count) postID = BareID(parts[comments + 1], @"t3_");
    NSString *subreddit = String(raw[@"subreddit"]);
    if (!subreddit.length) subreddit = String(post[@"subreddit"]);
    if (!subreddit.length && parts.count > 2 && [parts[1] isEqual:@"r"]) subreddit = parts[2];
    if (terms[@"subreddit"] && [subreddit caseInsensitiveCompare:terms[@"subreddit"]] != NSOrderedSame) return nil;
    if (!path.length && postID.length) path = [NSString stringWithFormat:@"/comments/%@/_/%@/", postID, identifier];
    if (!path.length) return nil;

    NSInteger relevance = 0;
    if ([terms[@"needles"] count]) {
        NSString *folded = Fold(body);
        for (NSString *needle in terms[@"needles"]) {
            NSRange match = [folded rangeOfString:needle options:NSDiacriticInsensitiveSearch];
            if (match.location == NSNotFound) return nil;
            NSCharacterSet *letters = NSCharacterSet.alphanumericCharacterSet;
            BOOL start = match.location == 0 || ![letters characterIsMember:[folded characterAtIndex:match.location - 1]];
            BOOL end = NSMaxRange(match) == folded.length || ![letters characterIsMember:[folded characterAtIndex:NSMaxRange(match)]];
            if (start && end) relevance++;
        }
        if ([folded rangeOfString:terms[@"phrase"] options:NSDiacriticInsensitiveSearch].location != NSNotFound) relevance += [terms[@"needles"] count] + 1;
    }
    NSString *title = String(raw[@"link_title"]);
    if (!title.length) title = String(post[@"title"]);
    NSMutableDictionary *row = [@{@"name": [@"t1_" stringByAppendingString:identifier], @"body": body,
                                   @"author": author, @"subreddit": subreddit, @"permalink": path,
                                   @"link_id": postID, @"link_title": title, @"relevance": @(relevance)} mutableCopy];
    if (created) row[@"created_utc"] = created;
    if ([raw[@"score"] isKindOfClass:NSNumber.class]) row[@"score"] = raw[@"score"];
    return row;
}

NSDictionary *ApolloCommentSearchMerge(NSDictionary *previous, NSDictionary *row, NSString *source) {
    NSMutableOrderedSet *sources = [NSMutableOrderedSet orderedSetWithArray:previous[@"sources"] ?: @[]];
    BOOL keepLive = [sources containsObject:@"Reddit"] && ![source isEqual:@"Reddit"];
    NSMutableDictionary *merged = [(keepLive ? previous : row) mutableCopy];
    NSDictionary *other = keepLive ? row : previous;
    for (NSString *field in @[@"link_id", @"link_title", @"subreddit", @"author", @"created_utc", @"score"]) {
        if ((!merged[field] || [merged[field] isEqual:@""]) && other[field]) merged[field] = other[field];
    }
    [sources addObject:source];
    merged[@"sources"] = [sources.array sortedArrayUsingSelector:@selector(compare:)];
    return merged;
}

NSString *ApolloCommentSearchExcerpt(NSString *plainText, NSDictionary *terms) {
    if (!plainText.length) return @"";
    // Keep a matching passage visible even when it is far down a long reply.
    NSStringCompareOptions options = NSCaseInsensitiveSearch;
    NSString *phrase = terms[@"phrase"];
    NSRange match = phrase.length ? [plainText rangeOfString:phrase options:options] : NSMakeRange(NSNotFound, 0);
    if (match.location == NSNotFound) {
        for (NSString *needle in terms[@"needles"]) {
            NSRange word = [plainText rangeOfString:needle options:options];
            if (word.location < match.location) match = word;
        }
    }
    NSUInteger start = match.location != NSNotFound && match.location > 75 ? match.location - 36 : 0;
    NSRange range = [plainText rangeOfComposedCharacterSequencesForRange:NSMakeRange(start, MIN(400, plainText.length - start))];
    NSString *snippet = [plainText substringWithRange:range];
    return [NSString stringWithFormat:@"%@%@%@", range.location ? @"…" : @"", snippet, NSMaxRange(range) < plainText.length ? @"…" : @""];
}

NSArray *ApolloCommentSearchSorted(NSArray *rows, NSString *sort) {
    NSString *rank = [sort isEqual:@"top"] ? @"score" : ([sort isEqual:@"relevance"] ? @"relevance" : nil);
    BOOL oldestFirst = [sort isEqual:@"old"];
    return [rows sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        if (rank) {
            NSComparisonResult order = [(b[rank] ?: @0) compare:(a[rank] ?: @0)];
            if (order != NSOrderedSame) return order;
        }
        NSNumber *left = a[@"created_utc"], *right = b[@"created_utc"];
        if (!left && right) return NSOrderedDescending;
        if (left && !right) return NSOrderedAscending;
        NSComparisonResult date = oldestFirst ? [left compare:right] : [right compare:left];
        return date == NSOrderedSame ? [a[@"name"] compare:b[@"name"]] : date;
    }];
}
