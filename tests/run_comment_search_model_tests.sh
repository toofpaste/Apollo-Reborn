#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build=$(mktemp -d "${TMPDIR:-/tmp}/apollo-comment-search.XXXXXX")
trap 'rm -rf -- "$build"' EXIT HUP INT TERM
xcrun --sdk macosx clang -fobjc-arc -fblocks -Wall -Wextra -Werror \
    -fsanitize=address,undefined -framework Foundation -I "$repo/src" \
    "$repo/src/ApolloCommentSearchModel.m" "$repo/tests/comment_search_model_tests.m" -o "$build/test"
"$build/test"
xcrun --sdk macosx clang -fobjc-arc -fblocks -Wall -Wextra -Werror \
    -fsanitize=address,undefined -framework Foundation -I "$repo/src" \
    "$repo/src/ApolloCommentSearchModel.m" "$repo/src/ApolloCommentSearch.m" \
    "$repo/tests/comment_search_session_tests.m" -o "$build/session"
"$build/session"
