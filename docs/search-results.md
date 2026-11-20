# Search and Hidden Saved

Normal searches again open Apollo's original post results. The original sort/time
menu remains intact. A separate content menu offers All content (default), Exclude
NSFW, Only NSFW, Media gallery, and Search comments. Content restrictions
are applied to the Reddit query and checked against response flags. Existing
Google/Kagi modes remain available.

Comment search checks recent Reddit comments alongside PullPush and Arctic Shift.
Use `subreddit:apolloapp` or `r/apolloapp` to search a community. Use
`author:example` or `u/example` to search someone's comments. Quotation marks
keep words together. Unquoted words can appear in any order.

For global searches, Apollo reads r/all's comment feed and recent comments in
communities found through post search or matching archived comments. A scoped search reads the community or
author feed directly. Each feed scans up to three pages of 100 comments per
batch when matches are sparse. Apollo also checks replies in up to five
distinct threads drawn from Reddit's relevant and newest post results.
Recent replies on older posts qualify for the same comment-date filters.
PullPush searches its keyword index. Arctic Shift searches the given author or
community, or the first related community for a global query. When its keyword
index rejects a scoped search, Apollo checks the archive's chronological listing.

Each row shows the subreddit, parent post title, local posting date and time,
a matching excerpt, author, score and sources when available. Apollo looks up
missing post titles in batches and combines duplicate comments by ID.
Relevance favors complete phrases and uses the newer comment to break ties.
Newest, Oldest and Top sort the matches found so far. Each feed and archive
pages independently for up to ten batches. Live feeds cover a moving sample
of Reddit and archive coverage varies.

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

The macOS IPA workflow runs search-query tests, comment model and search-session
fixtures, and compiles the tweak. Device checks include the following.

- Original post cards and native sort/time menu, including Top / Past hour.
- All content by default; Only/Exclude NSFW, pagination and rapid filter changes.
- Open a recent comment on an older post, check its title and local posting time,
  and check wrapping for long titles and larger text sizes.
- Five-second post save: shorter hold cancels, long hold creates one hidden entry
  without a normal save; repeated holds deduplicate.
- Own-profile Saved hold opens the folder; another user's profile does not.
- Select/deselect and remove multiple bookmarks while previews load; failed writes
  must preserve selection and saved data.
- Compact/expanded layouts, galleries, muted video/GIF autoplay, offscreen stopping,
  restart, account switch, and background/foreground isolation.
