# One-shot folder-cover snapshot

## Device validation failed - do not deploy

On 2026-11-08, loading this arm64e library with the existing RootHide
`opainject` into iPhone15,3 / iOS 16.3 SpringBoard caused SIGILL during the
load attempt. SpringBoard restarted automatically and the transient fault
scene was lost. No snapshot was produced; the observer was absent from the
crash report's loaded-image list. The exact loader/injector/ABI failure is
unverified. Compilation success is NOT device compatibility validation.
Do not repeat on SpringBoard until the failure is isolated on an authorized
noncritical target. This source is retained for incident review, not as a
validated production diagnostic tool.

Authorized live diagnosis only. Load into the existing SpringBoard PID with
RootHide's existing `opainject`; never respring to load this observer.

The constructor checks the process name, schedules one main-thread snapshot,
then stops. It has no hooks, polling, UI actions or layout refresh. The dylib
remains mapped until SpringBoard exits; do not force an unload or respring.
It reads current UIView/CALayer/UIImage properties and selected stored ivars.
It deliberately avoids Bolders' state-mutating `listLayout` getters.
Output is `/tmp/folder-cover-snapshot-<pid>.json` in SpringBoard's filesystem view.

The PrimalFolder global offsets are specific to the inspected 0.1.2 arm64e
binary. Verify its hash and architecture before loading; do not reuse offsets
for another binary. A snapshot alone does not establish temporal causality.
Attachment and main-thread inspection can perturb timing. No protected app
process may be targeted. Retain source and remove temporary files only with
authorization; no automatic filesystem cleanup is performed.

Build with the local iPhoneOS SDK:

```sh
xcrun clang -target arm64e-apple-ios16.0 -isysroot "$HOME/theos/sdks/iPhoneOS16.5.sdk" \
  -fobjc-arc -fblocks -O1 -Wall -Wextra -dynamiclib \
  -framework Foundation -framework UIKit -framework QuartzCore \
  Snapshot.m -o /tmp/FolderCoverSnapshot.dylib
ldid -S /tmp/FolderCoverSnapshot.dylib
```
