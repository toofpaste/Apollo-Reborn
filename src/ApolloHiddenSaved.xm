#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "ApolloCommon.h"
#import "ApolloToast.h"
#import "ApolloAccountCredentials.h"
#import "ApolloClasses.h"
#import "ApolloSwiftRuntime.h"
#import "ApolloHiddenSaved.h"
#import "UIWindow+Apollo.h"

@protocol ApolloBookmarkLink <NSObject, NSCopying>
@property(nonatomic, readonly) BOOL isNSFW;
@property(nonatomic) BOOL saved;
@end

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
NSArray *ApolloHiddenSavedRead(NSString *account) {
    NSURL *file = HiddenFile(account);
    NSArray *rows = file ? [NSArray arrayWithContentsOfURL:file] : nil;
    return [rows isKindOfClass:NSArray.class] ? rows : @[];
}
BOOL ApolloHiddenSavedWrite(NSArray *rows, NSString *account) {
    NSURL *file = HiddenFile(account);
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:rows format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
    return file && data && [data writeToURL:file options:NSDataWritingAtomic | NSDataWritingFileProtectionComplete error:nil];
}
static NSString *HiddenPostID(id link) {
    NSString *identifier = ApolloSendObject(link, @selector(identifier));
    if (![identifier isKindOfClass:NSString.class]) return nil;
    if ([identifier hasPrefix:@"t3_"]) identifier = [identifier substringFromIndex:3];
    NSCharacterSet *invalid = [[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789"] invertedSet];
    return identifier.length && [identifier rangeOfCharacterFromSet:invalid].location == NSNotFound ? identifier : nil;
}

// All folder edits run on the main queue and read the current file before writing.
static BOOL UpdateHiddenBookmark(NSString *account, NSString *identifier, NSString *title) {
    if (!identifier.length || !account.length) return NO;
    NSMutableArray *rows = [ApolloHiddenSavedRead(account) mutableCopy];
    NSIndexSet *matches = [rows indexesOfObjectsPassingTest:^BOOL(NSDictionary *row, NSUInteger index, BOOL *stop) {
        return [row[@"id"] isEqual:identifier];
    }];
    if (!title && !matches.count) return YES;
    [rows removeObjectsAtIndexes:matches];
    if (title) [rows insertObject:@{@"id": identifier, @"title": title} atIndex:0];
    return ApolloHiddenSavedWrite(rows, account);
}

static NSString *BookmarkTitle(id link) {
    NSString *title = ApolloSendObject(link, @selector(title));
    return [title isKindOfClass:NSString.class] ? title : @"Saved post";
}

static void PublishBookmarkState(id<ApolloBookmarkLink> link, BOOL saved) {
    link.saved = saved;
    id updated = [link copyWithZone:NULL];
    [NSNotificationCenter.defaultCenter postNotificationName:@"com.christianselig.ModelObjectUpdated"
                                                    object:link userInfo:@{@"newModel": updated}];
}

static void PresentSaveChoice(UIWindow *window, NSString *account, BOOL stored, dispatch_block_t saveNormally) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:stored ? @"Saved to Hidden Saved" : @"Couldn’t save to Hidden Saved"
                                                                 message:stored ? @"You can move this post to your Reddit Saved list." : @"You can still save this post to your Reddit Saved list."
                                                          preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:stored ? @"Keep Hidden" : @"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save to Reddit Saved" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        if ([account isEqual:ApolloActiveAccountUsername().lowercaseString]) saveNormally();
    }]];
    dispatch_block_t present = ^{
        if ([account isEqual:ApolloActiveAccountUsername().lowercaseString]) {
            [window.visibleViewController presentViewController:alert animated:YES completion:nil];
        }
    };
    // Feed action sheets may still be dismissing when the save is intercepted.
    id<UIViewControllerTransitionCoordinator> transition = window.visibleViewController.transitionCoordinator;
    if (![transition animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        dispatch_async(dispatch_get_main_queue(), present);
    }]) present();
}

typedef void (^BookmarkSaveCompletion)(NSError *error);
typedef id (*BookmarkSaveIMP)(id, SEL, id, BookmarkSaveCompletion);

%hook RDKClient
- (id)saveLink:(id<ApolloBookmarkLink>)link completion:(BookmarkSaveCompletion)completion {
    if (!link.isNSFW) return %orig;
    NSString *account = ApolloActiveAccountUsername().lowercaseString;
    NSString *identifier = HiddenPostID(link);
    id client = self;
    BookmarkSaveIMP save = (BookmarkSaveIMP)&%orig;
    // Native callers publish their optimistic copy immediately after returning
    // from this method. Correct it once that synchronous update has finished.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (account.length && ![account isEqual:ApolloActiveAccountUsername().lowercaseString]) return;
        if (link.saved) PublishBookmarkState(link, NO);
        if (!account.length) {
            ApolloShowToastWithStyle(@"Couldn’t save", @"Sign in to use Hidden Saved.", ApolloToastStyleError, nil);
            return;
        }
        BOOL stored = UpdateHiddenBookmark(account, identifier, BookmarkTitle(link));
        PresentSaveChoice(ApolloKeyWindow(), account, stored, ^{
            save(client, @selector(saveLink:completion:), link, ^(NSError *error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    // Finish the move only after Reddit confirms the normal save.
                    BOOL removed = error || !stored || UpdateHiddenBookmark(account, identifier, nil);
                    if (![account isEqual:ApolloActiveAccountUsername().lowercaseString]) return;
                    if (!error) PublishBookmarkState(link, YES);
                    if (completion) completion(error);
                    if (!removed) ApolloShowToastWithStyle(@"Saved to Reddit", @"The Hidden Saved copy couldn’t be removed.", ApolloToastStyleError, nil);
                });
            });
        });
    });
    return nil;
}
%end
static UIViewController *Owner(UIView *view) {
    for (UIResponder *r = view; r; r = r.nextResponder) if ([r isKindOfClass:UIViewController.class]) return (UIViewController *)r;
    return nil;
}
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
    if (![owner isKindOfClass:ApolloClassCommentsViewController]) return NO;
    id<ApolloBookmarkLink> link = ApolloObjectIvar(owner, "link");
    return link && !link.isNSFW;
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
        BOOL saved = UpdateHiddenBookmark(account, HiddenPostID(link), BookmarkTitle(link));
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
