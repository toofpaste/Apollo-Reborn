#import <UIKit/UIKit.h>

__BEGIN_DECLS
// Only the marked post-save button (including its image/label descendants).
// location is in the context-menu interaction's view coordinates.
BOOL ApolloHiddenSaveShouldSuppressContextMenu(UIContextMenuInteraction *interaction, CGPoint location);
__END_DECLS
