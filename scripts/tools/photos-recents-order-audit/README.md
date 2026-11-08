# Read-only PhotoKit Recents query

This one-shot helper fetches the default PhotoKit sequences for the user
library and recently-added smart album, with normal burst collapsing and
includeAllBurstAssets. It never calls performChanges, writes Photos SQLite,
injects an app, or refreshes Photos. Output is JSON on stdout.

A standalone PhotoKit query proves its returned sequence, not the visible
Photos app's in-memory/UI sequence under every app-only tweak. Compare default
IDs with the original restored added-date order and report that boundary.

Build with the iPhoneOS SDK, Foundation and Photos. Sign using the Photos-only
entitlements from ../photos-camera-roll-transfer/entitlements.plist. Remove the
temporary device executable after collecting output; retain source here.
