# Search and Hidden Saved

Normal searches again open Apollo's original post results. The original sort/time
menu remains intact. A separate content menu offers All content (default), Exclude
NSFW, Only NSFW, Media gallery, and Search indexed comments. Content restrictions
are applied to the Reddit query and checked against response flags. Existing
Google/Kagi modes remain available.

Comment search now aggregates actual comment bodies from:

- Live Reddit: scans up to five matching threads per batch (100 loaded comments
  per thread, depth 8), using the account's normal Reddit transport.
- PullPush: keyword search across its archive.
- Arctic Shift: scoped keyword search. Explicit `subreddit:` / `author:` operators
  are supported; otherwise the first matching Reddit community supplies the scope,
  which is displayed in the source status.

Each source publishes independently, with explicit network/HTTP errors. Results
are deduplicated by comment ID, combine source labels, and prefer live Reddit data
when the same comment is available there. Relevance, Newest, Oldest and Top sort
**loaded matches**, with comment-date time filters. Archive cursors are separate
from Reddit's post cursor. A batch requests at most 100 entries per archive and
five Reddit threads; a search caps at ten batches. Coverage is incomplete and
archives may lag behind live Reddit. Google HTML/redirect scraping is removed.

Provider references: [Arctic Shift API](https://github.com/ArthurHeitmann/arctic_shift/blob/master/api/README.md),
[PullPush API](https://pullpush.io/), [Reddit API](https://www.reddit.com/dev/api/).

## Hidden Saved

Hold the save/bookmark icon on a post's comments quick bar for five seconds to
save a local bookmark. A short tap retains Apollo's normal save behavior. Holding
the save button no longer opens the post-header context menu; holding the
title, body, or other header controls still opens their usual menus. Hold
Saved on your own profile for five seconds to open Hidden Saved. Use **Edit**, select posts, then **Remove** to delete hidden bookmarks. Normal Reddit Saved is not used or modified; an item
previously saved normally remains there until you unsave it normally.

Compact view shows thumbnails, titles and subreddit names. Expanded view shows
uncropped media with the title/subreddit below, and a Next image control for
multi-image galleries. Videos and GIFs play muted when at least half the media is
visible; leaving the screen, entering Edit, backgrounding, or scrolling away stops
playback. Previews are refreshed from Reddit by ID, so existing bookmarks upgrade
without migration; unavailable posts keep their saved title and remain removable.

The folder is account-specific, device-local, excluded from device backups, and
written with complete iOS file protection. It closes when the app becomes inactive
or the account changes. It has no passcode/biometric gate and is a hidden UI feature,
not a secure vault. Removing the app removes these bookmarks.

## Validation

The Windows checkout supports source/syntax checks only. The macOS IPA workflow
runs search-query and comment sorting tests and compiles the tweak. Device checks still required:

- Original post cards and native sort/time menu, including Top / Past hour.
- All content by default; Only/Exclude NSFW, pagination and rapid filter changes.
- Aggregated comment rows, source failures, duplicate IDs, all four sorts, time
  filters, independent pagination, and opening comments.
- Five-second post save: shorter hold cancels, long hold creates one hidden entry
  without a normal save; repeated holds deduplicate.
- Own-profile Saved hold opens the folder; another user's profile does not.
- Select/deselect and remove multiple bookmarks while previews load; failed writes
  must preserve selection and saved data.
- Compact/expanded layouts, galleries, muted video/GIF autoplay, offscreen stopping,
  restart, account switch, and background/foreground isolation.
