# Personal iPhone builds

This repository preserves the Apollo Reborn source and upstream history.
The app is a tweak packaged with the upstream prepared Apollo base IPA,
not a standalone rebuild of the original Apollo app.

**Build unsigned iPhone IPAs** runs on code pushes to `main` and can also be
started from Actions → Build unsigned iPhone IPAs → Run workflow.
It builds the tweak using Xcode 26.0.1 / iOS 26.0, injects it using the
existing upstream scripts, and validates four IPA variants.

After a successful run, open [Releases](https://github.com/toofpaste/Apollo-Reborn/releases)
and download an `.ipa` directly from the latest build's Assets (no ZIP extraction).
Pick Standard or GLASS (Liquid Glass), with or without
extensions (`NOEXTENSIONS`). Sign your chosen IPA using your sideloading tool
and install it on your iPhone. No Apple account, certificate, or provisioning
profile is needed by CI; internal ad-hoc signatures may remain for re-signing.
Release IPAs do not expire automatically. Debug symbols remain Actions artifacts
retained for 30 days. Each run attempt gets its own release tag pointing to the
exact source commit: `unsigned-build-<run number>-<attempt>`.

The workflow downloads the prepared base IPA from
https://downloads.apolloreborn.app/apollobase.ipa and requires that upstream
download to remain available. Dependencies use the existing submodule commits
and Theos revision.

The existing upstream release/source-publishing workflows are preserved;
use the personal unsigned workflow for normal builds. It publishes direct IPA
release assets without modifying distribution feeds.

When asking Codex to start a build, stop after triggering it. Do not poll or
wait for the build unless explicitly requested; report the run result manually.
