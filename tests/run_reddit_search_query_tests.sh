#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build=$(mktemp -d "${TMPDIR:-/tmp}/apollo-reddit-search.XXXXXX")
trap 'rm -rf -- "$build"' EXIT HUP INT TERM
xcrun --sdk macosx clang -fobjc-arc -fblocks -Wall -Wextra -Werror \
    -fsanitize=address,undefined -framework Foundation -I "$repo/src" \
    "$repo/src/ApolloRedditSearchQuery.m" "$repo/tests/reddit_search_query_tests.m" -o "$build/test"
"$build/test"
