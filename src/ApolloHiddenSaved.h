#import <UIKit/UIKit.h>

__BEGIN_DECLS
// Only the marked post-save button (including its image/label descendants).
// location is in the context-menu interaction's view coordinates.
BOOL ApolloHiddenSaveShouldSuppressContextMenu(UIContextMenuInteraction *interaction, CGPoint location);
NSArray *ApolloHiddenSavedRead(NSString *account);
BOOL ApolloHiddenSavedWrite(NSArray *rows, NSString *account);
__END_DECLS

@interface ApolloHiddenSavedController : UITableViewController
@property(nonatomic, copy) NSString *account;
@end
