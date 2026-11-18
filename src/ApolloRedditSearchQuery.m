#import "ApolloRedditSearchQuery.h"

NSURL *ApolloRedditSearchURL(NSString *query, BOOL communities, NSString *sort,
    NSString *time, ApolloSearchNSFWFilter filter, NSString *after, BOOL oauth) {
    // Parentheses keep OR queries from escaping the explicit content filter.
    NSString *q = query;
    if (filter != ApolloSearchNSFWAll && !communities) {
        q = [NSString stringWithFormat:@"(%@) AND nsfw:%@", query,
             filter == ApolloSearchNSFWOnly ? @"yes" : @"no"];
    }
    NSURLComponents *url = [NSURLComponents componentsWithString:oauth
        ? @"https://oauth.reddit.com/search.json" : @"https://www.reddit.com/search.json"];
    NSMutableArray *items = [NSMutableArray array];
    NSDictionary *values = @{@"q": q, @"type": communities ? @"sr" : @"link",
        @"sort": sort, @"t": time, @"limit": @"50", @"raw_json": @"1",
        @"include_over_18": filter == ApolloSearchNSFWExclude ? @"off" : @"on"};
    for (NSString *key in values) [items addObject:[NSURLQueryItem queryItemWithName:key value:values[key]]];
    if (after.length) [items addObject:[NSURLQueryItem queryItemWithName:@"after" value:after]];
    url.queryItems = items;
    return url.URL;
}

BOOL ApolloRedditSearchAcceptsNSFW(NSDictionary *data, ApolloSearchNSFWFilter filter) {
    if (filter == ApolloSearchNSFWAll) return YES;
    id flag = data[@"over_18"] ?: data[@"over18"];
    // Unknown is not safe, and is not positively marked NSFW either.
    if (![flag isKindOfClass:NSNumber.class]) return NO;
    return [flag boolValue] == (filter == ApolloSearchNSFWOnly);
}

static NSURL *ApolloSearchImageURL(id value) {
    if (![value isKindOfClass:NSString.class]) return nil;
    NSURL *url = [NSURL URLWithString:[value stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"]];
    return [url.scheme.lowercaseString isEqualToString:@"https"] ? url : nil;
}

NSURL *ApolloRedditSearchPreviewURL(NSDictionary *data) {
    NSDictionary *preview = [data[@"preview"] isKindOfClass:NSDictionary.class] ? data[@"preview"] : nil;
    NSArray *images = [preview[@"images"] isKindOfClass:NSArray.class] ? preview[@"images"] : nil;
    NSDictionary *first = [images.firstObject isKindOfClass:NSDictionary.class] ? images.firstObject : nil;
    NSArray *resolutions = [first[@"resolutions"] isKindOfClass:NSArray.class] ? first[@"resolutions"] : nil;
    // Avoid decoding full-resolution originals for grid thumbnails.
    for (id item in resolutions) {
        if (![item isKindOfClass:NSDictionary.class]) continue;
        if ([item[@"width"] respondsToSelector:@selector(integerValue)] && [item[@"width"] integerValue] >= 320) {
            NSURL *url = ApolloSearchImageURL(item[@"url"]);
            if (url) return url;
        }
    }
    NSURL *thumbnail = ApolloSearchImageURL(data[@"thumbnail"]);
    if (thumbnail) return thumbnail;
    NSDictionary *gallery = [data[@"media_metadata"] isKindOfClass:NSDictionary.class] ? data[@"media_metadata"] : nil;
    for (id entry in gallery.allValues) {
        if (![entry isKindOfClass:NSDictionary.class]) continue;
        NSArray *previews = [entry[@"p"] isKindOfClass:NSArray.class] ? entry[@"p"] : nil;
        for (id p in previews) {
            if (![p isKindOfClass:NSDictionary.class]) continue;
            NSURL *url = ApolloSearchImageURL(p[@"u"]);
            if (url) return url;
        }
    }
    return nil;
}

BOOL ApolloRedditSearchIsMedia(NSDictionary *data) {
    NSString *hint = [data[@"post_hint"] isKindOfClass:NSString.class] ? data[@"post_hint"] : @"";
    return [data[@"is_video"] isEqual:@YES] || [data[@"is_gallery"] isEqual:@YES] ||
        [@[@"image", @"hosted:video", @"rich:video"] containsObject:hint];
}
