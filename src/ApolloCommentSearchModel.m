#import "ApolloCommentSearch.h"

NSDictionary *ApolloCommentSearchTerms(NSString *query) {
    NSMutableDictionary *terms = [NSMutableDictionary dictionary];
    NSMutableString *text = [query mutableCopy];
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"(?:^|\\s)(author|subreddit):([A-Za-z0-9_-]+)" options:NSRegularExpressionCaseInsensitive error:nil];
    for (NSTextCheckingResult *match in [[regex matchesInString:query options:0 range:NSMakeRange(0,query.length)] reverseObjectEnumerator]) {
        terms[[[query substringWithRange:[match rangeAtIndex:1]] lowercaseString]] = [query substringWithRange:[match rangeAtIndex:2]];
        [text replaceCharactersInRange:match.range withString:@" "];
    }
    NSArray *words = [text componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    terms[@"text"] = [[words filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]] componentsJoinedByString:@" "];
    return terms;
}
NSInteger ApolloCommentSearchRelevance(NSString *body, NSString *query) {
    NSInteger score = 0;
    for (NSString *word in [[query.lowercaseString stringByReplacingOccurrencesOfString:@"\"" withString:@""] componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]) {
        if (word.length && [body.lowercaseString containsString:word]) score++;
    }
    return score;
}
NSArray *ApolloCommentSearchSorted(NSArray *rows, NSString *sort, NSString *text) {
    return [rows sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        double av = [a[@"created_utc"] doubleValue], bv = [b[@"created_utc"] doubleValue];
        if ([sort isEqual:@"top"]) { av = [a[@"score"] doubleValue]; bv = [b[@"score"] doubleValue]; }
        else if ([sort isEqual:@"relevance"]) { av = ApolloCommentSearchRelevance(a[@"body"],text); bv = ApolloCommentSearchRelevance(b[@"body"],text); }
        if (av != bv) return ([sort isEqual:@"old"] ? av < bv : av > bv) ? NSOrderedAscending : NSOrderedDescending;
        return [a[@"name"] compare:b[@"name"]];
    }];
}
