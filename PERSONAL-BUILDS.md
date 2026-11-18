# Personal iPhone builds

This repository preserves the Apollo Reborn source and upstream history.
The app is a tweak packaged with the upstream prepared Apollo base IPA,
not a standalone rebuild of the original Apollo app.

**Build unsigned iPhone IPAs** runs on code pushes to `main` and can also be
started from Actions → Build unsigned iPhone IPAs → Run workflow.
It builds the tweak using Xcode 26.0.1 / iOS 26.0, injects it using the
existing upstream scripts, and validates four IPA variants.

After a successful run, download `Apollo-Reborn-unsigned-<run number>` from
Artifacts and unzip it. Pick Standard or GLASS (Liquid Glass), with or without
extensions (`NOEXTENSIONS`). Sign your chosen IPA using your sideloading tool
and install it on your iPhone. No Apple account, certificate, or provisioning
profile is needed by CI; internal ad-hoc signatures may remain for re-signing.
Artifacts and debug symbols are retained for 30 days.

The workflow downloads the prepared base IPA from
https://downloads.apolloreborn.app/apollobase.ipa and requires that upstream
download to remain available. Dependencies use the existing submodule commits
and Theos revision.

The existing upstream release/source-publishing workflows are preserved;
use the personal unsigned workflow for normal builds. It does not publish
releases or modify distribution feeds.

When asking Codex to start a build, stop after triggering it. Do not poll or
wait for the build unless explicitly requested; report the run result manually.
