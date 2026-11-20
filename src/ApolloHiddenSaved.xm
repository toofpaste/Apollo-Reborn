#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "ApolloCommon.h"
#import "ApolloToast.h"
#import "ApolloAccountCredentials.h"
#import "ApolloClasses.h"
#import "ApolloSwiftRuntime.h"
#import "ApolloHiddenSaved.h"

extern NSString *ApolloUsernameFromProfileViewController(UIViewController *controller);
static NSURL *HiddenFile(NSString *account) {
    if (!account.length) return nil;
    // Reddit usernames contain only ASCII letters, digits, underscores and hyphens.
    if ([account rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789_-"] invertedSet]].location != NSNotFound) return nil;
    NSURL *directory = [[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject URLByAppendingPathComponent:@"HiddenSaved" isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:nil];
    [directory setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
    return [directory URLByAppendingPathComponent:[account stringByAppendingString:@".plist"]];
}
static NSArray *ReadHidden(NSString *account) {
    NSURL *file = HiddenFile(account);
    NSArray *rows = file ? [NSArray arrayWithContentsOfURL:file] : nil;
    return [rows isKindOfClass:NSArray.class] ? rows : @[];
}
static BOOL WriteHidden(NSArray *rows, NSString *account) {
    NSURL *file = HiddenFile(account);
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:rows format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
    return file && data && [data writeToURL:file options:NSDataWritingAtomic | NSDataWritingFileProtectionComplete error:nil];
}
static UIViewController *Owner(UIView *view) {
    for (UIResponder *r = view; r; r = r.nextResponder) if ([r isKindOfClass:UIViewController.class]) return (UIViewController *)r;
    return nil;
}
@interface ApolloHiddenSavedController : UITableViewController
@property(nonatomic, copy) NSString *account;
@property(nonatomic, strong) NSArray *rows;
@end
@implementation ApolloHiddenSavedController
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = @"Hidden Saved";
    self.rows = ReadHidden(self.account);
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 70;
    UILabel *footer = [[UILabel alloc] initWithFrame:CGRectMake(0,0,300,65)];
    footer.text = @"Stored only on this device. Swipe a post to remove it.";
    footer.numberOfLines = 0; footer.textAlignment = NSTextAlignmentCenter;
    footer.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    self.tableView.tableFooterView = footer;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(lock) name:UIApplicationWillResignActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(lock) name:@"com.christianselig.RedditAccountChanged" object:nil];
}
- (void)lock { self.rows = @[]; [self.tableView reloadData]; [self.navigationController popToRootViewControllerAnimated:NO]; }
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (![self.account isEqual:ApolloActiveAccountUsername().lowercaseString]) { self.rows = @[]; [self.tableView reloadData]; [self lock]; }
}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { return self.rows.count; }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [table dequeueReusableCellWithIdentifier:@"hidden"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"hidden"];
    cell.textLabel.text = self.rows[path.row][@"title"];
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.text = @"Tap to open post";
    return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    if (![self.account isEqual:ApolloActiveAccountUsername().lowercaseString]) { [self lock]; return; }
    NSURL *url = [NSURL URLWithString:[@"https://www.reddit.com/comments/" stringByAppendingString:self.rows[path.row][@"id"]]];
    if (!ApolloRouteResolvedURLViaApolloScheme(url)) ApolloPresentWebURLFromViewController(self, url);
}
- (void)tableView:(UITableView *)table commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)path {
    if (style != UITableViewCellEditingStyleDelete || ![self.account isEqual:ApolloActiveAccountUsername().lowercaseString]) return;
    NSMutableArray *rows = [self.rows mutableCopy]; [rows removeObjectAtIndex:path.row];
    if (WriteHidden(rows,self.account)) { self.rows = rows; [table deleteRowsAtIndexPaths:@[path] withRowAnimation:UITableViewRowAnimationAutomatic]; }
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
@end

@interface ApolloHiddenHold : NSObject <UIGestureRecognizerDelegate>
@property(nonatomic, weak) id node;
@property(nonatomic) BOOL opensFolder;
@end
@implementation ApolloHiddenHold
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture
        shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)other {
    // The header's shorter long press must wait for this button's five-second
    // hold. This relationship only participates in touches delivered to the
    // save button; title/body/sibling-button touches never reach our recognizer.
    // Leave taps and scrolling alone, and don't change the profile-folder hold.
    return !self.opensFolder && other != gesture &&
        [other isKindOfClass:UILongPressGestureRecognizer.class] &&
        other.view && [gesture.view isDescendantOfView:other.view];
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
    if (!ApolloActiveAccountUsername().length) return NO;
    UIViewController *owner = Owner(gesture.view);
    if (self.opensFolder) {
        if (![owner isKindOfClass:ApolloClassProfileViewController]) return NO;
        NSString *username = ApolloUsernameFromProfileViewController(owner);
        if ([username caseInsensitiveCompare:ApolloActiveAccountUsername()] != NSOrderedSame || !username.length) return NO;
        id text = ApolloSendObject(ApolloObjectIvar(self.node, "titleNode"), @selector(attributedText));
        return [text isKindOfClass:NSAttributedString.class] && [[text string] isEqualToString:@"Saved"];
    }
    return [owner isKindOfClass:ApolloClassCommentsViewController];
}
- (void)held:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    UIViewController *owner = Owner(gesture.view);
    NSString *account = ApolloActiveAccountUsername().lowercaseString;
    if (self.opensFolder) {
        ApolloHiddenSavedController *folder = [ApolloHiddenSavedController new]; folder.account = account;
        [owner.navigationController pushViewController:folder animated:YES];
    } else {
        id link = ApolloObjectIvar(owner, "link");
        NSString *identifier = ApolloSendObject(link, @selector(identifier));
        NSString *title = ApolloSendObject(link, @selector(title));
        if (![identifier isKindOfClass:NSString.class] || !identifier.length) return;
        if ([identifier hasPrefix:@"t3_"]) identifier = [identifier substringFromIndex:3];
        if ([identifier rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789"] invertedSet]].location != NSNotFound) return;
        NSMutableArray *rows = [ReadHidden(account) mutableCopy];
        NSIndexSet *duplicates = [rows indexesOfObjectsPassingTest:^BOOL(NSDictionary *item, NSUInteger index, BOOL *stop) { return [item[@"id"] isEqual:identifier]; }];
        [rows removeObjectsAtIndexes:duplicates];
        [rows insertObject:@{@"id":identifier, @"title":[title isKindOfClass:NSString.class] ? title : @"Saved post"} atIndex:0];
        BOOL saved = WriteHidden(rows, account);
        ApolloShowToastWithStyle(saved ? @"Saved privately" : @"Couldn’t save", saved ? @"Added to Hidden Saved on this device." : @"Please try again.", saved ? ApolloToastStyleSuccess : ApolloToastStyleError, nil);
    }
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
}
@end
static char holdKey;
BOOL ApolloHiddenSaveShouldSuppressContextMenu(UIContextMenuInteraction *interaction, CGPoint location) {
    UIView *source = interaction.view;
    if (!source) return NO;
    // Hit-test in the menu's coordinate space rather than using a remembered
    // press or a broad header rectangle. This also follows layout/rotation.
    UIView *hit = [source hitTest:location withEvent:nil];
    for (UIView *view = hit; view; view = view.superview) {
        ApolloHiddenHold *hold = objc_getAssociatedObject(view, &holdKey);
        if (hold && !hold.opensFolder) return YES;
    }
    return NO;
}
static void InstallHold(id node, UIView *view, BOOL folder) {
    if (!view || objc_getAssociatedObject(view,&holdKey)) return;
    ApolloHiddenHold *target = [ApolloHiddenHold new]; target.node = node; target.opensFolder = folder;
    UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:target action:@selector(held:)];
    hold.minimumPressDuration = 5; hold.allowableMovement = 12; hold.cancelsTouchesInView = YES; hold.delegate = target;
    objc_setAssociatedObject(view,&holdKey,target,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [view addGestureRecognizer:hold];
}
%hook _TtC6Apollo20CommentsQuickBarNode
- (void)didLoad { %orig; InstallHold(self, ApolloNodeView(ApolloObjectIvar(self,"saveButton")), NO); }
%end
%hook _TtC6Apollo22ProfileFeatureCellNode
- (void)didLoad { %orig; InstallHold(self, ApolloNodeView(self), YES); }
%end
%ctor { %init; }
