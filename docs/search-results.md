# Reddit search results

Submit a query with the keyboard Search button in the Reddit engine to open
the new results screen. Existing native suggestions and Google/Kagi search
remain available. The results screen supports editing and resubmitting the query.

- Posts: Relevance, New, Top, Hot, Most comments; All time, Past hour/day/week/month/year.
- Media: the same search and sort, displayed as a scrolling thumbnail grid of
  image, gallery, and video posts. Tap a tile to open the post in Apollo.
- Subreddits: community search, with content filtering. Post sort/time controls
  are disabled because they do not describe community results.
- Comments: Reddit's actual comment-search page embedded in a WKWebView. Reddit's
  public Data API does not support global comment search. This page may require
  sign-in and uses its own controls; native filters are disabled. Tapped comment
  permalinks route into Apollo when its native router is available.

NSFW choices are mutually exclusive: All content, Exclude NSFW (initial choice),
Only NSFW. Post search sends an explicit `nsfw:` clause and verifies every
returned item's `over_18` flag. Community results use `over18`. Missing/invalid
flags are excluded from either restricted mode. Media filtering happens after
the same NSFW check. Spoiler previews are concealed.

Pages are deduplicated and use Reddit's `after` cursor. Scrolling near the bottom
fetches another page; the status control also loads more or retries errors.
When a page has no matching media/content, it offers the next page explicitly
instead of silently stopping or issuing an unbounded sequence of requests.
Changes to query/tab/filters cancel the request and invalidate stale callbacks.

Profile → More → **Search posts from this user** opens `author:<username>` search
for public indexed posts. It is available in both legacy and Liquid Glass menus,
including the signed-in user's own menu. Reddit's indexing and access rules still
determine what can be found; this does not retrieve private or deleted content.

## Verification

`sh tests/run_reddit_search_query_tests.sh` on macOS tests request encoding,
author/OR queries, pagination parameters, strict NSFW matching, media detection,
and safe preview selection. Both manual Build IPA and push-triggered unsigned IPA
workflows run it before compilation.

Device/simulator checklist:

1. Submit a Reddit search; switch between Posts, Media, Subreddits, Comments.
2. Compare Top / Past hour and New; change filters during a slow request.
3. Check All / Only / Exclude NSFW with known tagged and untagged results.
4. Scroll several pages, including a page with no media matches; retry offline.
5. Open image/video/gallery posts and comments, then return to the results.
6. Check portrait, landscape, large text, light/dark, and both menu styles.
7. Open the profile action for yourself and another user; verify the author query.
