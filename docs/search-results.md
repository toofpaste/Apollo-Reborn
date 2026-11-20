# Search and Hidden Saved

Normal searches again open Apollo's original post results. The original sort/time
menu remains intact. A separate content menu offers All content (default), Exclude
NSFW, Only NSFW, Media gallery, and Search indexed comments. Content restrictions
are applied to the Reddit query and checked against response flags. Existing
Google/Kagi modes remain available.

Comment search uses Google-indexed Reddit comments displayed in native rows, not
an embedded Reddit page. This is not exhaustive Reddit-wide search. Google may
require verification. Native post filters are disabled for these comment results.
Media and profile-author search default to All content too.

## Hidden Saved

Hold the save/bookmark icon on a post's comments quick bar for five seconds to
save a local bookmark. A short tap retains Apollo's normal save behavior. Holding
the save button no longer opens the post-header context menu; holding the
title, body, or other header controls still opens their usual menus. Hold
Saved on your own profile for five seconds to open Hidden Saved. Swipe a hidden
bookmark to remove it. Normal Reddit Saved is not used or modified; an item
previously saved normally remains there until you unsave it normally.

The folder is account-specific, device-local, excluded from device backups, and
written with complete iOS file protection. It closes when the app becomes inactive
or the account changes. It has no passcode/biometric gate and is a hidden UI feature,
not a secure vault. Removing the app removes these bookmarks.

## Validation

The Windows checkout supports source/syntax checks only. The macOS IPA workflow
runs search-query tests and compiles the tweak. Device checks still required:

- Original post cards and native sort/time menu, including Top / Past hour.
- All content by default; Only/Exclude NSFW, pagination and rapid filter changes.
- Native indexed comment rows, verification, retries, and opening comments.
- Five-second post save: shorter hold cancels, long hold creates one hidden entry
  without a normal save; repeated holds deduplicate.
- Own-profile Saved hold opens the folder; another user's profile does not.
- Remove bookmarks, restart, account switch, and background/foreground isolation.
