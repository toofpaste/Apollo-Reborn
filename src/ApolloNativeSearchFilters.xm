#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "ApolloCommon.h"
#import "ApolloSwiftRuntime.h"
#import "ApolloRedditSearchViewController.h"

static NSMutableDictionary *filters;
static char menuKey;
static NSURLRequest *FilteredRequest(NSURLRequest *request) {
    if ([NSURLProtocol propertyForKey:@"ApolloNativeSearchMode" inRequest:request]) return request;
    NSURLComponents *url = [NSURLComponents componentsWithURL:request.URL resolvingAgainstBaseURL:NO];
    NSString *host = url.host.lowercaseString;
    if (!([host isEqual:@"reddit.com"] || [host hasSuffix:@".reddit.com"]) ||
        !([url.path isEqual:@"/search"] || [url.path hasSuffix:@"/search.json"] || [url.path hasSuffix:@"/search"])) return request;
    NSMutableArray *items = [url.queryItems mutableCopy];
    NSString *query = nil;
    for (NSURLQueryItem *item in items) {
        if ([item.name isEqual:@"type"] && ![item.value isEqual:@"link"]) return request;
        if ([item.name isEqual:@"q"]) query = item.value;
    }
    if (!query.length) return request;
    NSInteger mode = 0;
    @synchronized(filters) { mode = [filters[query] integerValue]; }
    NSIndexSet *remove = [items indexesOfObjectsPassingTest:^BOOL(NSURLQueryItem *item, NSUInteger idx, BOOL *stop) {
        return [item.name isEqual:@"include_over_18"] || [item.name isEqual:@"q"];
    }];
    [items removeObjectsAtIndexes:remove];
    NSString *q = mode ? [NSString stringWithFormat:@"(%@) AND nsfw:%@", query, mode == 2 ? @"yes" : @"no"] : query;
    [items addObject:[NSURLQueryItem queryItemWithName:@"q" value:q]];
    [items addObject:[NSURLQueryItem queryItemWithName:@"include_over_18" value:mode == 1 ? @"off" : @"on"]];
    url.queryItems = items;
    NSMutableURLRequest *copy = [request mutableCopy]; copy.URL = url.URL;
    [NSURLProtocol setProperty:@(mode) forKey:@"ApolloNativeSearchMode" inRequest:copy];
    return copy;
}

static void InstallFilters(UIViewController *vc) {
    if (objc_getAssociatedObject(vc, &menuKey)) return;
    NSString *query = ApolloReadSwiftStringIvar(vc, "searchQuery");
    if (!query.length) return;
    __weak UIViewController *weakVC = vc;
    NSMutableArray *choices = [NSMutableArray array];
    NSArray *titles = @[@"All content", @"Exclude NSFW", @"Only NSFW"];
    for (NSInteger mode = 0; mode < 3; mode++) {
        UIAction *action = [UIAction actionWithTitle:titles[mode] image:nil identifier:nil handler:^(__kindof UIAction *sender) {
            UIViewController *owner = weakVC;
            if (!owner) return;
            @synchronized(filters) { filters[query] = @(mode); }
            UIBarButtonItem *button = objc_getAssociatedObject(owner, &menuKey);
            button.title = titles[mode];
            for (UIAction *choice in button.menu.children) if ([choice isKindOfClass:UIAction.class]) choice.state = choice == sender ? UIMenuElementStateOn : UIMenuElementStateOff;
            SEL refresh = @selector(refreshControlActivatedWithSender:);
            if ([owner respondsToSelector:refresh]) ((void(*)(id,SEL,id))objc_msgSend)(owner, refresh, nil);
        }];
        @synchronized(filters) { action.state = [filters[query] integerValue] == mode ? UIMenuElementStateOn : UIMenuElementStateOff; }
        [choices addObject:action];
    }
    for (NSInteger kind = 1; kind <= 3; kind += 2) {
        [choices addObject:[UIAction actionWithTitle:kind == 1 ? @"Media gallery" : @"Search indexed comments" image:nil identifier:nil handler:^(__kindof UIAction *action) {
            UIViewController *owner = weakVC;
            ApolloRedditSearchViewController *results = [[ApolloRedditSearchViewController alloc] initWithQuery:query];
            results.initialKind = kind;
            [owner.navigationController pushViewController:results animated:YES];
        }]];
    }
    UIBarButtonItem *button = [[UIBarButtonItem alloc] initWithTitle:@"All content" style:UIBarButtonItemStylePlain target:nil action:nil];
    @synchronized(filters) { button.title = titles[[filters[query] integerValue]]; }
    button.menu = [UIMenu menuWithTitle:@"Search filters" children:choices];
    objc_setAssociatedObject(vc, &menuKey, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    vc.navigationItem.rightBarButtonItems = [(vc.navigationItem.rightBarButtonItems ?: @[]) arrayByAddingObject:button];
}
%hook _TtC6Apollo32PostsSearchResultsViewController
- (void)viewDidLoad { %orig; InstallFilters((UIViewController *)self); }
%end
%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request { return %orig(FilteredRequest(request)); }
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completion {
    NSURLRequest *filtered = FilteredRequest(request);
    NSInteger mode = [[NSURLProtocol propertyForKey:@"ApolloNativeSearchMode" inRequest:filtered] integerValue];
    if (!mode || !completion) return %orig(filtered, completion);
    return %orig(filtered, ^(NSData *data, NSURLResponse *response, NSError *error) {
        id json = data ? [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil] : nil;
        if ([json isKindOfClass:NSMutableDictionary.class] && [json[@"data"] isKindOfClass:NSMutableDictionary.class] && [json[@"data"][@"children"] isKindOfClass:NSArray.class]) {
            NSMutableArray *accepted = [NSMutableArray array];
            for (id child in json[@"data"][@"children"]) {
                if (![child isKindOfClass:NSDictionary.class] || ![child[@"data"] isKindOfClass:NSDictionary.class]) continue;
                id flag = child[@"data"][@"over_18"];
                if ([flag isKindOfClass:NSNumber.class] && [flag boolValue] == (mode == 2)) [accepted addObject:child];
            }
            json[@"data"][@"children"] = accepted;
            data = [NSJSONSerialization dataWithJSONObject:json options:0 error:nil] ?: data;
        }
        completion(data,response,error);
    });
}
%end
%ctor { filters = [NSMutableDictionary dictionary]; %init; }
