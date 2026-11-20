#import "ApolloHiddenSaved.h"
#import "ApolloAccountCredentials.h"
#import "ApolloCommon.h"
#import "ApolloToast.h"
#import "ApolloState.h"
#import "ApolloClasses.h"
#import "ApolloThemeRuntime.h"
#import "ApolloGalleryFeed.h"
#import "ApolloGalleryImageLoader.h"
#import "ApolloRedditSearchQuery.h"
#import <AVFoundation/AVFoundation.h>

@interface ApolloHiddenMediaCell : UITableViewCell
@property(nonatomic, strong) UIImageView *preview;
@property(nonatomic, strong) UILabel *caption;
@property(nonatomic, strong) UIButton *next;
@property(nonatomic, copy) NSArray<ApolloGalleryItem *> *media;
@property(nonatomic) NSUInteger mediaIndex;
@property(nonatomic) BOOL expanded;
@property(nonatomic) BOOL active;
@property(nonatomic, strong) ApolloGalleryImageRequest *request;
@property(nonatomic, strong) ApolloGalleryDecodedImage *decoded;
@property(nonatomic, strong) AVQueuePlayer *player;
@property(nonatomic, strong) AVPlayerLooper *looper;
@property(nonatomic, strong) AVPlayerLayer *videoLayer;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) BOOL resolving;
- (void)configure:(NSDictionary *)row media:(NSArray *)media expanded:(BOOL)expanded;
- (void)setPlaybackActive:(BOOL)active;
@end
@implementation ApolloHiddenMediaCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    if ((self=[super initWithStyle:style reuseIdentifier:identifier])) {
        _preview=[[(ApolloClassFLAnimatedImageView ?: UIImageView.class) alloc] initWithFrame:CGRectZero];
        _preview.contentMode=UIViewContentModeScaleAspectFit; _preview.clipsToBounds=YES;
        _caption=[UILabel new]; _caption.numberOfLines=0;_caption.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];_caption.adjustsFontForContentSizeCategory=YES;
        _next=[UIButton buttonWithType:UIButtonTypeSystem];[_next addTarget:self action:@selector(nextImage) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:_preview];[self.contentView addSubview:_caption];[self.contentView addSubview:_next];
    }return self;
}
- (void)stop {
    [self.player pause];self.player=nil;self.looper=nil;[self.videoLayer removeFromSuperlayer];self.videoLayer=nil;
    if ([self.preview respondsToSelector:@selector(setAnimatedImage:)]) ((void(*)(id,SEL,id))objc_msgSend)(self.preview,@selector(setAnimatedImage:),nil);
    self.preview.image=self.decoded.image ?: self.preview.image;
}
- (void)setPlaybackActive:(BOOL)active {
    self.active=active && self.expanded;
    if (!self.active) { [self stop];return; }
    ApolloGalleryItem *item=self.mediaIndex<self.media.count ? self.media[self.mediaIndex] : nil;
    if (item.needsHostedVideoResolution && !self.resolving) {
        self.resolving=YES;NSUInteger generation=self.generation;__weak typeof(self) weakSelf=self;
        [item resolveHostedVideoWithCompletion:^(BOOL resolved) {
            typeof(self) owner=weakSelf;if (!owner || owner.generation!=generation) return;
            [owner stop];[owner setPlaybackActive:owner.active];
        }];
    }
    NSURL *url=item.gifMP4URL ?: item.videoURL;
    if (url && !self.player) {
        self.player=[AVQueuePlayer queuePlayerWithItems:@[]];self.player.muted=YES;self.player.volume=0;
        self.looper=[AVPlayerLooper playerLooperWithPlayer:self.player templateItem:[AVPlayerItem playerItemWithURL:url]];
        self.videoLayer=[AVPlayerLayer playerLayerWithPlayer:self.player];self.videoLayer.videoGravity=AVLayerVideoGravityResizeAspect;
        self.videoLayer.frame=self.preview.bounds;[self.preview.layer addSublayer:self.videoLayer];[self.player play];
    } else if (!url && self.decoded.animatedImage && [self.preview respondsToSelector:@selector(setAnimatedImage:)]) {
        ((void(*)(id,SEL,id))objc_msgSend)(self.preview,@selector(setAnimatedImage:),self.decoded.animatedImage);
    }
}
- (void)loadImage {
    [self.request cancel];[self stop]; self.decoded=nil; self.generation++;self.resolving=NO;
    self.preview.image=[UIImage systemImageNamed:@"photo"];
    ApolloGalleryItem *item=self.mediaIndex<self.media.count ? self.media[self.mediaIndex] : nil;
    self.next.hidden=!self.expanded || self.media.count<2;
    [self.next setTitle:[NSString stringWithFormat:@"%lu / %lu  Next image ›",(unsigned long)self.mediaIndex+1,(unsigned long)self.media.count] forState:UIControlStateNormal];
    if (!item) return;
    NSURL *still=self.expanded ? item.imageURL : (item.thumbnailURL ?: item.imageURL);
    if (!still) { [self setPlaybackActive:self.active];return; }
    NSUInteger generation=self.generation;__weak typeof(self) weakSelf=self;
    if (self.expanded) {
        self.request=[[ApolloGalleryImageLoader sharedLoader] loadImageAtURL:still progress:nil completion:^(ApolloGalleryDecodedImage *decoded, NSData *data) {
            typeof(self) owner=weakSelf;if (!owner || owner.generation!=generation) return;
            owner.decoded=decoded;owner.preview.image=decoded.image ?: [UIImage systemImageNamed:@"photo"];
            [owner setPlaybackActive:owner.active];
        }];
    } else {
        self.request=[[ApolloGalleryImageLoader sharedLoader] loadThumbnailAtURL:still completion:^(UIImage *image) { if (weakSelf.generation==generation) weakSelf.preview.image=image ?: [UIImage systemImageNamed:@"photo"]; }];
    }
    [self setPlaybackActive:self.active];
}
- (void)nextImage { if (self.media.count) { self.mediaIndex=(self.mediaIndex+1)%self.media.count;[self loadImage]; } }
- (void)configure:(NSDictionary *)row media:(NSArray *)media expanded:(BOOL)expanded {
    self.expanded=expanded;self.active=NO;self.media=media ?: @[];self.mediaIndex=0;
    NSString *subreddit=[row[@"subreddit"] isKindOfClass:NSString.class] ? [@"r/" stringByAppendingString:row[@"subreddit"]] : @"Subreddit unavailable";
    self.caption.text=[NSString stringWithFormat:@"%@\n%@",row[@"title"] ?: @"Saved post",subreddit];
    [self loadImage];[self setNeedsLayout];
}
- (void)layoutSubviews {
    [super layoutSubviews]; CGFloat width=self.contentView.bounds.size.width, height=self.contentView.bounds.size.height;
    if (self.expanded) {
        CGFloat captionHeight=MIN(height-100,[self.caption sizeThatFits:CGSizeMake(width-24,CGFLOAT_MAX)].height+16);
        CGFloat nextHeight=self.next.hidden ? 0 : 36;
        self.preview.frame=CGRectMake(12,8,width-24,MAX(50,height-captionHeight-nextHeight-16));
        self.caption.frame=CGRectMake(12,CGRectGetMaxY(self.preview.frame)+8,width-24,captionHeight);
        self.next.frame=CGRectMake(12,height-nextHeight,width-24,nextHeight);
    } else { self.preview.frame=CGRectMake(12,12,76,76);self.caption.frame=CGRectMake(100,8,MAX(1,width-112),height-16); }
    self.videoLayer.frame=self.preview.bounds;
}
- (void)prepareForReuse { [super prepareForReuse];self.generation++;[self.request cancel];[self setPlaybackActive:NO];self.decoded=nil;self.preview.image=nil; }
- (void)dealloc { [_request cancel];[_player pause]; }
@end

@interface ApolloHiddenSavedController ()
@property(nonatomic, strong) NSArray<NSDictionary *> *rows;
@property(nonatomic, strong) NSMutableDictionary *metadata;
@property(nonatomic, strong) NSMutableDictionary *media;
@property(nonatomic, strong) NSMutableSet *selection;
@property(nonatomic, strong) NSURLSessionDataTask *task;
@property(nonatomic, strong) UIBarButtonItem *removeButton;
@property(nonatomic, strong) UISegmentedControl *mode;
@property(nonatomic, copy) NSString *token;
@property(nonatomic) NSUInteger generation;
@end
@implementation ApolloHiddenSavedController
- (void)viewDidLoad {
    [super viewDidLoad];self.title=@"Hidden Saved";
    self.view.tintColor=ApolloThemeAccentColor() ?: self.view.tintColor;
    self.rows=ApolloHiddenSavedRead(self.account);self.metadata=[NSMutableDictionary dictionary];self.media=[NSMutableDictionary dictionary];self.selection=[NSMutableSet set];self.token=ApolloActiveAccountRedditBearerToken();
    self.mode=[[UISegmentedControl alloc] initWithItems:@[@"Compact",@"Expanded"]];self.mode.selectedSegmentIndex=0;
    [self.mode addTarget:self action:@selector(changeMode) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.titleView=self.mode;
    self.removeButton=[[UIBarButtonItem alloc] initWithTitle:@"Remove" style:UIBarButtonItemStylePlain target:self action:@selector(removeSelected)];
    self.navigationItem.rightBarButtonItems=@[self.editButtonItem];
    self.tableView.allowsMultipleSelectionDuringEditing=YES;
    [self.tableView registerClass:ApolloHiddenMediaCell.class forCellReuseIdentifier:@"post"];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(lock) name:UIApplicationWillResignActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(lock) name:@"com.christianselig.RedditAccountChanged" object:nil];
    self.refreshControl=[UIRefreshControl new];[self.refreshControl addTarget:self action:@selector(refreshMetadata) forControlEvents:UIControlEventValueChanged];
    [self updateEmptyState];
    [self refreshMetadata];
}
- (void)updateEmptyState {
    UILabel *label=[UILabel new];label.text=@"No hidden saves";label.textAlignment=NSTextAlignmentCenter;label.textColor=UIColor.secondaryLabelColor;
    self.tableView.backgroundView=self.rows.count ? nil : label;
    self.editButtonItem.enabled=self.rows.count>0;
}
- (BOOL)validAccount { return [self.account isEqual:ApolloActiveAccountUsername().lowercaseString]; }
- (void)stopPlayers { for (ApolloHiddenMediaCell *cell in self.tableView.visibleCells) [cell setPlaybackActive:NO]; }
- (void)lock { self.generation++;[self.task cancel];[self stopPlayers];self.rows=@[];[self.metadata removeAllObjects];[self.media removeAllObjects];[self.tableView reloadData];[self.navigationController popToRootViewControllerAnimated:NO]; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated];if (![self validAccount]) [self lock]; }
- (void)viewDidAppear:(BOOL)animated { [super viewDidAppear:animated];[self updatePlayback]; }
- (void)viewWillDisappear:(BOOL)animated { [super viewWillDisappear:animated];[self stopPlayers]; }
- (void)changeMode { [self stopPlayers];[self.tableView reloadData];[self restoreSelection];[self updatePlayback]; }
- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
    [super setEditing:editing animated:animated];[self.selection removeAllObjects];
    self.navigationItem.rightBarButtonItems=editing ? @[self.editButtonItem,self.removeButton] : @[self.editButtonItem];
    self.removeButton.enabled=NO;self.removeButton.title=@"Remove";[self.tableView reloadData];[self updatePlayback];
}
- (void)restoreSelection {
    if (!self.editing) return;
    for (NSUInteger i=0;i<self.rows.count;i++) if ([self.selection containsObject:self.rows[i][@"id"]]) [self.tableView selectRowAtIndexPath:[NSIndexPath indexPathForRow:i inSection:0] animated:NO scrollPosition:UITableViewScrollPositionNone];
}
- (void)removeSelected {
    if (![self validAccount] || !self.selection.count) return;
    NSMutableArray *remaining=[NSMutableArray array];for (NSDictionary *row in self.rows) if (![self.selection containsObject:row[@"id"]]) [remaining addObject:row];
    if (!ApolloHiddenSavedWrite(remaining,self.account)) { ApolloShowToastWithStyle(@"Couldn’t remove posts",@"Your saved posts have been kept. Try again.",ApolloToastStyleError,nil);return; }
    self.rows=remaining;[self updateEmptyState];[self setEditing:NO animated:YES];[self.tableView reloadData];[self updatePlayback];
}
- (void)refreshMetadata {
    if (![self validAccount]) { [self lock];return; }
    self.generation++;[self.task cancel];[self hydrate:[self.rows copy] offset:0 generation:self.generation];
}
- (void)hydrate:(NSArray *)snapshot offset:(NSUInteger)offset generation:(NSUInteger)generation {
    if (offset>=snapshot.count) { [self.refreshControl endRefreshing];return; }
    NSUInteger length=MIN(100,snapshot.count-offset);NSMutableArray *ids=[NSMutableArray array];
    for (NSDictionary *row in [snapshot subarrayWithRange:NSMakeRange(offset,length)]) if ([row[@"id"] isKindOfClass:NSString.class]) [ids addObject:[@"t3_" stringByAppendingString:row[@"id"]]];
    NSString *base=self.token.length ? @"https://oauth.reddit.com" : @"https://www.reddit.com";
    NSURLComponents *url=[NSURLComponents componentsWithString:[base stringByAppendingString:@"/api/info.json"]];
    url.queryItems=@[[NSURLQueryItem queryItemWithName:@"id" value:[ids componentsJoinedByString:@","]],[NSURLQueryItem queryItemWithName:@"raw_json" value:@"1"]];
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:url.URL cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:25];
    if (self.token.length) [request setValue:[@"Bearer " stringByAppendingString:self.token] forHTTPHeaderField:@"Authorization"];
    if (sUserAgent.length) [request setValue:sUserAgent forHTTPHeaderField:@"User-Agent"];
    __weak typeof(self) weakSelf=self;
    self.task=[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        id root=data && !error ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) owner=weakSelf;if (!owner || generation!=owner.generation || ![owner validAccount]) return;
            NSDictionary *listing=[root isKindOfClass:NSDictionary.class] && [root[@"data"] isKindOfClass:NSDictionary.class] ? root[@"data"] : nil;
            NSArray *children=[listing[@"children"] isKindOfClass:NSArray.class] ? listing[@"children"] : nil;
            if (!children) { [owner.refreshControl endRefreshing];ApolloShowToastWithStyle(@"Previews couldn’t load",@"Pull down to retry. Your hidden saves are intact.",ApolloToastStyleError,nil);return; }

            for (id child in children) {
                NSDictionary *post=[child isKindOfClass:NSDictionary.class] && [child[@"data"] isKindOfClass:NSDictionary.class] ? child[@"data"] : nil;
                NSString *identifier=post[@"id"];if (![identifier isKindOfClass:NSString.class]) continue;
                owner.metadata[identifier]=post;
                ApolloGalleryFeed *feed=[[ApolloGalleryFeed alloc] initWithHomeFeed];[feed seedFromListing:@{@"children":@[child],@"after":NSNull.null}];
                NSMutableArray *items=[NSMutableArray array];for (ApolloGalleryItem *item in feed.allItems) if ([item.postFullname isEqual:[@"t3_" stringByAppendingString:identifier]]) [items addObject:item];
                if (!items.count) {
                    NSURL *thumbnail=ApolloRedditSearchPreviewURL(post);
                    if (thumbnail) { ApolloGalleryItem *preview=[ApolloGalleryItem new];preview.kind=ApolloGalleryMediaKindPhoto;preview.imageURL=thumbnail;preview.thumbnailURL=thumbnail;preview.pixelSize=CGSizeMake(320,320);[items addObject:preview]; }
                }
                owner.media[identifier]=items;
            }
            [owner.tableView reloadData];[owner restoreSelection];[owner updatePlayback];
            [owner hydrate:snapshot offset:offset+length generation:generation];
        });
    }];[self.task resume];
}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { return self.rows.count; }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    ApolloHiddenMediaCell *cell=[table dequeueReusableCellWithIdentifier:@"post" forIndexPath:path];NSDictionary *row=self.rows[path.row];
    [cell configure:self.metadata[row[@"id"]] ?: row media:self.media[row[@"id"]] expanded:self.mode.selectedSegmentIndex==1];
    cell.accessoryType=self.editing && [self.selection containsObject:row[@"id"]] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.editingAccessoryType=cell.accessoryType;
    return cell;
}
- (CGFloat)tableView:(UITableView *)table heightForRowAtIndexPath:(NSIndexPath *)path {
    NSDictionary *row=self.rows[path.row];NSDictionary *post=self.metadata[row[@"id"]] ?: row;
    CGFloat width=MAX(100,table.bounds.size.width-24), font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody].lineHeight;
    if (self.mode.selectedSegmentIndex==0) return MAX(100,font*4+24);
    NSArray *items=self.media[row[@"id"]];ApolloGalleryItem *item=items.firstObject;
    CGFloat ratio=item.pixelSize.height>0 ? item.pixelSize.width/item.pixelSize.height : 1;
    CGFloat imageHeight=items.count ? MIN(MAX(180,width/MAX(0.1,ratio)),MAX(200,self.view.bounds.size.height*0.7)) : 100;
    NSString *text=[NSString stringWithFormat:@"%@\nr/%@",post[@"title"] ?: @"Saved post",post[@"subreddit"] ?: @""];
    CGFloat caption=[text boundingRectWithSize:CGSizeMake(width,CGFLOAT_MAX) options:NSStringDrawingUsesLineFragmentOrigin attributes:@{NSFontAttributeName:[UIFont preferredFontForTextStyle:UIFontTextStyleBody]} context:nil].size.height;
    return imageHeight+ceil(caption)+32+(items.count>1 ? 36:0);
}
- (BOOL)tableView:(UITableView *)table canEditRowAtIndexPath:(NSIndexPath *)path { return YES; }
- (UITableViewCellEditingStyle)tableView:(UITableView *)table editingStyleForRowAtIndexPath:(NSIndexPath *)path { return UITableViewCellEditingStyleNone; }
- (BOOL)tableView:(UITableView *)table shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)path { return NO; }
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    if (![self validAccount]) { [self lock];return; }
    if (self.editing) { [self.selection addObject:self.rows[path.row][@"id"]];self.removeButton.enabled=YES;self.removeButton.title=[NSString stringWithFormat:@"Remove (%lu)",(unsigned long)self.selection.count];[table cellForRowAtIndexPath:path].editingAccessoryType=UITableViewCellAccessoryCheckmark;return; }
    [table deselectRowAtIndexPath:path animated:YES];
    NSURL *url=[NSURL URLWithString:[@"https://www.reddit.com/comments/" stringByAppendingString:self.rows[path.row][@"id"]]];
    if (!ApolloRouteResolvedURLViaApolloScheme(url)) ApolloPresentWebURLFromViewController(self,url);
}
- (void)tableView:(UITableView *)table didDeselectRowAtIndexPath:(NSIndexPath *)path { if (self.editing) { [self.selection removeObject:self.rows[path.row][@"id"]];self.removeButton.enabled=self.selection.count>0;self.removeButton.title=[NSString stringWithFormat:@"Remove (%lu)",(unsigned long)self.selection.count];[table cellForRowAtIndexPath:path].editingAccessoryType=UITableViewCellAccessoryNone; } }
- (void)updatePlayback {
    BOOL visible=self.view.window && self.navigationController.topViewController==self && !self.editing && self.mode.selectedSegmentIndex==1 && UIApplication.sharedApplication.applicationState==UIApplicationStateActive;
    for (ApolloHiddenMediaCell *cell in self.tableView.visibleCells) {
        CGRect mediaFrame=[cell.preview convertRect:cell.preview.bounds toView:self.tableView];
        CGRect intersection=CGRectIntersection(self.tableView.bounds,mediaFrame);
        BOOL mostlyVisible=!CGRectIsNull(intersection) && intersection.size.height>=mediaFrame.size.height*0.5;
        [cell setPlaybackActive:visible && mostlyVisible];
    }
}
- (void)scrollViewDidScroll:(UIScrollView *)scrollView { [self updatePlayback]; }
- (void)tableView:(UITableView *)table willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)path { dispatch_async(dispatch_get_main_queue(), ^{ [self updatePlayback]; }); }
- (void)tableView:(UITableView *)table didEndDisplayingCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)path { [(ApolloHiddenMediaCell *)cell setPlaybackActive:NO]; }
- (void)dealloc { [_task cancel];[NSNotificationCenter.defaultCenter removeObserver:self]; }
@end
