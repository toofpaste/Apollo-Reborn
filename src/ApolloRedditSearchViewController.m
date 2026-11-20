#import "ApolloRedditSearchViewController.h"
#import "ApolloRedditSearchQuery.h"
#import "ApolloCommon.h"
#import "ApolloState.h"
#import "ApolloThemeRuntime.h"
#import <WebKit/WebKit.h>
#import "ApolloGoogleSearch.h"

@interface ApolloSearchResultCell : UICollectionViewCell
@property(nonatomic, strong) UIImageView *imageView;
@property(nonatomic, strong) UILabel *label;
@property(nonatomic, strong) NSURLSessionDataTask *imageTask;
@property(nonatomic, copy) NSString *representedID;
@end

@implementation ApolloSearchResultCell
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.contentView.backgroundColor = UIColor.secondarySystemBackgroundColor;
        self.contentView.layer.cornerRadius = 10;
        self.contentView.clipsToBounds = YES;
        _imageView = [UIImageView new];
        _imageView.contentMode = UIViewContentModeScaleAspectFill;
        _imageView.clipsToBounds = YES;
        _label = [UILabel new];
        _label.numberOfLines = 0;
        _label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
        _label.adjustsFontForContentSizeCategory = YES;
        _label.textColor = UIColor.labelColor;
        [self.contentView addSubview:_imageView];
        [self.contentView addSubview:_label];
        self.isAccessibilityElement = YES;
        self.accessibilityTraits = UIAccessibilityTraitButton;
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat height = self.imageView.hidden ? 0 : MAX(0, self.bounds.size.height - 90);
    self.imageView.frame = CGRectMake(0, 0, self.bounds.size.width, height);
    self.label.frame = CGRectMake(12, height + 8, self.bounds.size.width - 24, self.bounds.size.height - height - 16);
}
- (void)prepareForReuse {
    [super prepareForReuse];
    [self.imageTask cancel];
    self.imageTask = nil;
    self.representedID = nil;
    self.imageView.image = nil;
}
- (void)dealloc { [_imageTask cancel]; }
@end

@interface ApolloRedditSearchViewController () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UISearchBarDelegate, WKNavigationDelegate>
@property(nonatomic, copy) NSString *query;
@property(nonatomic, strong) UISearchBar *searchBar;
@property(nonatomic, strong) UISegmentedControl *kinds;
@property(nonatomic, strong) UIButton *sortButton;
@property(nonatomic, strong) UIButton *timeButton;
@property(nonatomic, strong) UIButton *nsfwButton;
@property(nonatomic, strong) UIButton *statusButton;
@property(nonatomic, strong) UICollectionView *collection;
@property(nonatomic, strong) ApolloGoogleSearchSession *commentSession;
@property(nonatomic) NSUInteger commentPage;
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *results;
@property(nonatomic, strong) NSMutableSet<NSString *> *seen;
@property(nonatomic, strong) NSURLSessionDataTask *task;
@property(nonatomic, copy) NSString *after;
@property(nonatomic, copy) NSString *sort;
@property(nonatomic, copy) NSString *time;
@property(nonatomic) ApolloSearchNSFWFilter nsfw;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) BOOL loading;
@property(nonatomic) BOOL more;
@property(nonatomic) BOOL failed;
@property(nonatomic) CGFloat layoutWidth;
@end

@implementation ApolloRedditSearchViewController
- (instancetype)initWithQuery:(NSString *)query {
    if ((self = [super init])) {
        _query = [query copy];
        _sort = @"relevance";
        _time = @"all";
        _nsfw = ApolloSearchNSFWAll;
        _results = [NSMutableArray array];
        _seen = [NSMutableSet set];
    }
    return self;
}
- (UIButton *)filterButton {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    button.titleLabel.adjustsFontForContentSizeCategory = YES;
    button.showsMenuAsPrimaryAction = YES;
    return button;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Search";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.view.tintColor = ApolloThemeAccentColor() ?: self.view.tintColor;
    self.searchBar = [UISearchBar new];
    self.searchBar.text = self.query;
    self.searchBar.placeholder = @"Search Reddit";
    self.searchBar.delegate = self;
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.kinds = [[UISegmentedControl alloc] initWithItems:@[@"Posts", @"Media", @"Subreddits", @"Comments"]];
    self.kinds.selectedSegmentIndex = self.initialKind;
    [self.kinds addTarget:self action:@selector(restart) forControlEvents:UIControlEventValueChanged];
    self.sortButton = [self filterButton];
    self.timeButton = [self filterButton];
    self.nsfwButton = [self filterButton];
    UIStackView *filters = [[UIStackView alloc] initWithArrangedSubviews:@[self.sortButton, self.timeButton, self.nsfwButton]];
    filters.distribution = UIStackViewDistributionFillEqually;
    self.statusButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.statusButton.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    self.statusButton.titleLabel.numberOfLines = 0;
    self.statusButton.titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.statusButton addTarget:self action:@selector(statusTapped) forControlEvents:UIControlEventTouchUpInside];
    UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
    layout.minimumInteritemSpacing = 8;
    layout.minimumLineSpacing = 8;
    layout.sectionInset = UIEdgeInsetsMake(8, 12, 12, 12);
    self.collection = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    self.collection.backgroundColor = UIColor.systemBackgroundColor;
    self.collection.dataSource = self;
    self.collection.delegate = self;
    self.collection.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.collection registerClass:ApolloSearchResultCell.class forCellWithReuseIdentifier:@"result"];
    UIStackView *header = [[UIStackView alloc] initWithArrangedSubviews:@[self.searchBar, self.kinds, filters, self.statusButton]];
    header.axis = UILayoutConstraintAxisVertical;
    header.spacing = 6;
    header.translatesAutoresizingMaskIntoConstraints = NO;
    self.collection.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:header];
    [self.view addSubview:self.collection];
    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [header.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:8],
        [header.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-8],
        [filters.heightAnchor constraintGreaterThanOrEqualToConstant:36],
        [self.statusButton.heightAnchor constraintGreaterThanOrEqualToConstant:34],
        [self.collection.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:6],
        [self.collection.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],
        [self.collection.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],
        [self.collection.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
    [self restart];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = self.collection.bounds.size.width;
    if (self.layoutWidth != width) {
        self.layoutWidth = width;
        [self.collection.collectionViewLayout invalidateLayout];
    }
}
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (![previousTraitCollection.preferredContentSizeCategory isEqual:self.traitCollection.preferredContentSizeCategory]) {
        [self.collection.collectionViewLayout invalidateLayout];
    }
}
- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    NSString *query = [searchBar.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!query.length) return;
    self.query = query;
    [searchBar resignFirstResponder];
    [self restart];
}
- (void)updateMenus {
    __weak typeof(self) weakSelf = self;
    NSArray *keys = @[@"relevance", @"new", @"top", @"hot", @"comments"];
    NSArray *titles = @[@"Relevance", @"New", @"Top", @"Hot", @"Most comments"];
    NSMutableArray *actions = [NSMutableArray array];
    for (NSUInteger i = 0; i < keys.count; i++) {
        NSString *key = keys[i];
        UIAction *action = [UIAction actionWithTitle:titles[i] image:nil identifier:nil handler:^(__kindof UIAction *a) {
            weakSelf.sort = key; [weakSelf restart];
        }];
        action.state = [self.sort isEqual:key] ? UIMenuElementStateOn : UIMenuElementStateOff;
        [actions addObject:action];
    }
    self.sortButton.menu = [UIMenu menuWithTitle:@"Sort posts" children:actions];
    [self.sortButton setTitle:titles[[keys indexOfObject:self.sort]] forState:UIControlStateNormal];
    keys = @[@"all", @"hour", @"day", @"week", @"month", @"year"];
    titles = @[@"All time", @"Past hour", @"Past day", @"Past week", @"Past month", @"Past year"];
    actions = [NSMutableArray array];
    for (NSUInteger i = 0; i < keys.count; i++) {
        NSString *key = keys[i];
        UIAction *action = [UIAction actionWithTitle:titles[i] image:nil identifier:nil handler:^(__kindof UIAction *a) {
            weakSelf.time = key; [weakSelf restart];
        }];
        action.state = [self.time isEqual:key] ? UIMenuElementStateOn : UIMenuElementStateOff;
        [actions addObject:action];
    }
    self.timeButton.menu = [UIMenu menuWithTitle:@"Time range" children:actions];
    [self.timeButton setTitle:titles[[keys indexOfObject:self.time]] forState:UIControlStateNormal];
    titles = @[@"All content", @"Exclude NSFW", @"Only NSFW"];
    actions = [NSMutableArray array];
    for (NSInteger i = 0; i < 3; i++) {
        UIAction *action = [UIAction actionWithTitle:titles[i] image:nil identifier:nil handler:^(__kindof UIAction *a) {
            weakSelf.nsfw = (ApolloSearchNSFWFilter)i; [weakSelf restart];
        }];
        action.state = self.nsfw == i ? UIMenuElementStateOn : UIMenuElementStateOff;
        [actions addObject:action];
    }
    self.nsfwButton.menu = [UIMenu menuWithTitle:@"NSFW filter" children:actions];
    [self.nsfwButton setTitle:titles[self.nsfw] forState:UIControlStateNormal];
    BOOL posts = self.kinds.selectedSegmentIndex < 2;
    self.sortButton.enabled = posts;
    self.timeButton.enabled = posts;
    self.nsfwButton.enabled = self.kinds.selectedSegmentIndex != 3;
}
- (void)restart {
    [self.task cancel];
    self.task = nil;
    self.generation++;
    self.loading = NO;
    self.failed = NO;
    self.after = nil;
    self.more = YES;
    [self.results removeAllObjects];
    [self.seen removeAllObjects];
    [self.collection reloadData];
    [self.collection setContentOffset:CGPointZero animated:NO];
    [self updateMenus];
    [self.commentSession cancel];
    self.commentPage = 0;
    self.collection.hidden = NO;
    [self loadNext];
}
- (void)loadNext {
    if (self.loading || !self.more) return;
    if (self.kinds.selectedSegmentIndex == 3) { [self loadComments]; return; }
    self.loading = YES;
    self.failed = NO;
    [self.statusButton setTitle:@"Searching…" forState:UIControlStateNormal];
    NSUInteger generation = self.generation;
    NSString *cursor = self.after;
    BOOL communities = self.kinds.selectedSegmentIndex == 2;
    NSString *token = ApolloActiveAccountRedditBearerToken();
    NSURL *url = ApolloRedditSearchURL(self.query, communities, communities ? @"relevance" : self.sort,
        communities ? @"all" : self.time, self.nsfw, cursor, token.length > 0);
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:30];
    if (token.length) [request setValue:[@"Bearer " stringByAppendingString:token] forHTTPHeaderField:@"Authorization"];
    if (sUserAgent.length) [request setValue:sUserAgent forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    __weak typeof(self) weakSelf = self;
    self.task = [NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
        id json = data && !error ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSDictionary *listing = [json isKindOfClass:NSDictionary.class] && [json[@"data"] isKindOfClass:NSDictionary.class] ? json[@"data"] : nil;
        NSArray *children = [listing[@"children"] isKindOfClass:NSArray.class] ? listing[@"children"] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf || strongSelf.generation != generation) return;
            strongSelf.loading = NO;
            strongSelf.task = nil;
            if (error || status < 200 || status >= 300 || !children) {
                strongSelf.failed = YES;
                [strongSelf.statusButton setTitle:status == 429 ? @"Reddit rate limit reached. Tap to retry." : @"Search couldn’t load. Tap to retry." forState:UIControlStateNormal];
                return;
            }
            for (id child in children) {
                if (![child isKindOfClass:NSDictionary.class] || ![child[@"kind"] isEqual:(communities ? @"t5" : @"t3")]) continue;
                NSDictionary *item = [child[@"data"] isKindOfClass:NSDictionary.class] ? child[@"data"] : nil;
                NSString *name = [item[@"name"] isKindOfClass:NSString.class] ? item[@"name"] : nil;
                if (!name.length || [strongSelf.seen containsObject:name]) continue;
                [strongSelf.seen addObject:name];
                if (!ApolloRedditSearchAcceptsNSFW(item, strongSelf.nsfw)) continue;
                if (strongSelf.kinds.selectedSegmentIndex == 1 && !ApolloRedditSearchIsMedia(item)) continue;
                [strongSelf.results addObject:item];
            }
            NSString *next = [listing[@"after"] isKindOfClass:NSString.class] ? listing[@"after"] : nil;
            strongSelf.after = next;
            strongSelf.more = next.length && ![next isEqual:cursor];
            [strongSelf.collection reloadData];
            NSString *message = strongSelf.more ? @"Scroll for more • Tap to load more" : @"End of results";
            if (!strongSelf.results.count) message = strongSelf.more ? @"No matches on this page. Tap to search the next page." : @"No results match these filters.";
            [strongSelf.statusButton setTitle:message forState:UIControlStateNormal];
        });
    }];
    [self.task resume];
}
- (void)statusTapped {
    [self loadNext];
}
- (NSInteger)collectionView:(UICollectionView *)view numberOfItemsInSection:(NSInteger)section { return self.results.count; }
- (UICollectionViewCell *)collectionView:(UICollectionView *)view cellForItemAtIndexPath:(NSIndexPath *)path {
    ApolloSearchResultCell *cell = [view dequeueReusableCellWithReuseIdentifier:@"result" forIndexPath:path];
    NSDictionary *item = self.results[path.item];
    BOOL gallery = self.kinds.selectedSegmentIndex == 1;
    cell.imageView.hidden = !gallery;
    NSString *title = [item[@"title"] isKindOfClass:NSString.class] ? item[@"title"] : @"";
    NSString *community = [item[@"subreddit"] isKindOfClass:NSString.class] ? item[@"subreddit"] : @"";
    NSString *author = [item[@"author"] isKindOfClass:NSString.class] ? item[@"author"] : @"[deleted]";
    BOOL nsfw = [item[@"over_18"] isEqual:@YES] || [item[@"over18"] isEqual:@YES];
    NSString *text = self.kinds.selectedSegmentIndex == 2
        ? [NSString stringWithFormat:@"r/%@\n%@%@", item[@"display_name"] ?: @"", title, nsfw ? @" • NSFW" : @""]
        : [NSString stringWithFormat:@"%@\nr/%@ • u/%@ • %@ points%@%@", title, community, author,
            [item[@"score"] isKindOfClass:NSNumber.class] ? item[@"score"] : @0,
            nsfw ? @" • NSFW" : @"", [item[@"is_video"] isEqual:@YES] ? @" • Video" : @""];
    cell.label.text = text;
    cell.accessibilityLabel = text;
    cell.representedID = item[@"name"];
    cell.imageView.image = nil;
    [cell.imageTask cancel];
    // Spoiler media remains concealed until the post is opened.
    NSURL *preview = gallery && ![item[@"spoiler"] isEqual:@YES] ? ApolloRedditSearchPreviewURL(item) : nil;
    if (preview) {
        NSString *identifier = cell.representedID;
        __weak ApolloSearchResultCell *weakCell = cell;
        cell.imageTask = [NSURLSession.sharedSession dataTaskWithURL:preview completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            UIImage *image = data && !error ? [UIImage imageWithData:data] : nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                ApolloSearchResultCell *current = weakCell;
                if ([current.representedID isEqual:identifier]) current.imageView.image = image;
            });
        }];
        [cell.imageTask resume];
    } else if (gallery) {
        cell.imageView.contentMode = UIViewContentModeScaleAspectFit;
        cell.imageView.image = [UIImage systemImageNamed:[item[@"spoiler"] isEqual:@YES] ? @"eye.slash" : @"photo.on.rectangle"];
    }
    if (preview) cell.imageView.contentMode = UIViewContentModeScaleAspectFill;
    [cell setNeedsLayout];
    return cell;
}
- (CGSize)collectionView:(UICollectionView *)view layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)path {
    CGFloat available = MAX(1, view.bounds.size.width - 24);
    BOOL gallery = self.kinds.selectedSegmentIndex == 1;
    NSUInteger columns = gallery ? MAX(2, (NSUInteger)(available / 220)) : 1;
    if (UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory)) columns = 1;
    CGFloat width = floor((available - (columns - 1) * 8) / columns);
    return CGSizeMake(width, gallery ? width + 90 : MAX(118, [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline].lineHeight * 5 + 16));
}
- (void)collectionView:(UICollectionView *)view didSelectItemAtIndexPath:(NSIndexPath *)path {
    NSDictionary *item = self.results[path.item];
    NSString *link = self.kinds.selectedSegmentIndex == 2 ? item[@"url"] : item[@"permalink"];
    if (![link isKindOfClass:NSString.class] || ![link hasPrefix:@"/"]) return;
    NSURL *url = [NSURL URLWithString:[@"https://www.reddit.com" stringByAppendingString:link]];
    if (!ApolloRouteResolvedURLViaApolloScheme(url)) ApolloPresentWebURLFromViewController(self, url);
}
- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView != self.collection || !scrollView.dragging || self.failed) return;
    if (scrollView.contentOffset.y + scrollView.bounds.size.height > scrollView.contentSize.height - 400) [self loadNext];
}
- (void)loadComments {
    if (!self.commentSession) {
        self.commentSession = [ApolloGoogleSearchSession new];
        __weak typeof(self) weakSelf = self;
        self.commentSession.presentVerification = ^(WKWebView *web) {
            UIViewController *sheet = [UIViewController new];
            sheet.view = web;
            [weakSelf presentViewController:sheet animated:YES completion:nil];
        };
        self.commentSession.dismissVerification = ^{ [weakSelf dismissViewControllerAnimated:YES completion:nil]; };
    }
    self.loading = YES;
    NSUInteger generation = self.generation;
    [self.statusButton setTitle:@"Searching indexed comments with Google…" forState:UIControlStateNormal];
    __weak typeof(self) weakSelf = self;
    NSString *query = [self.query stringByAppendingString:@" site:reddit.com/r/ inurl:comments"];
    [self.commentSession searchQuery:query options:nil page:self.commentPage completion:^(NSArray<ApolloGoogleSearchResult *> *results, BOOL more, NSError *error) {
        typeof(self) owner = weakSelf;
        if (!owner || owner.generation != generation) return;
        owner.loading = NO;
        owner.failed = error != nil;
        if (error) { [owner.statusButton setTitle:@"Comment search failed. Tap to retry." forState:UIControlStateNormal]; return; }
        owner.commentPage++;
        owner.more = more && owner.commentPage < 10;
        // Resolve Google's destination before classifying: encrypted Google links
        // are not known to be posts versus comments until their redirect resolves.
        dispatch_group_t group = dispatch_group_create();
        for (ApolloGoogleSearchResult *result in results) {
            dispatch_group_enter(group);
            [owner.commentSession resolveResult:result withRedditInfo:NO completion:^(NSError *failure) {
                if (owner.generation == generation && !failure && result.commentID.length && ![owner.seen containsObject:result.dedupeKey]) {
                    [owner.seen addObject:result.dedupeKey];
                    [owner.results addObject:@{@"name": result.dedupeKey, @"title": result.snippet.length ? result.snippet : result.title,
                        @"subreddit": result.subreddit ?: @"", @"author": result.author ?: @"", @"permalink": result.URL.path ?: @""}];
                }
                dispatch_group_leave(group);
            }];
        }
        owner.loading = YES;
        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            if (owner.generation != generation) return;
            owner.loading = NO;
            [owner.collection reloadData];
            [owner.statusButton setTitle:owner.more ? @"Google-indexed comments • Tap for more" : @"End of Google-indexed comments" forState:UIControlStateNormal];
        });
    }];
}
- (void)dealloc { [_task cancel]; [_commentSession cancel]; }
@end
