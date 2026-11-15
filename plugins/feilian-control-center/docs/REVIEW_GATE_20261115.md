# 2026-11-15 code review: release blocked

Scope: current multi-provider VPN Control Center source, application helpers,
IPC/authentication/publisher, packaging, diagnostics and test source. Other
projects in this worktree are excluded. Existing network successes do not
waive the correctness and security findings below.

## Findings requiring correction

1. P1: Easy stop completion can observe Session=nil before the asynchronous
   manager readback, interpret nil.status=0 as NEVPNStatusInvalid, and report
   a disconnected helper reply without a real session readback. The main
   controller's independent system check limits this error; no claim that it
   necessarily starts a new provider follows. EasyVPNConnectionHelper.m:59.
2. P1: Easy's background native Start only validates generation before
   OldStart. A cancellation/new request while OldStart runs lets its late
   result overwrite Session/Started or call unscoped Finish on the new request.
   State publication is also off-main despite main-thread cancellation.
   EasyVPNConnectionHelper.m:126.
3. P1: Shell publisher checks the App-owned tmp directory, then cd -P follows
   it later. Replacing tmp with a symlink between check and cd can redirect
   root publication of the fixed vcc1.permit leaf. mv -T protects the leaf,
   not the parent. This does not establish authentication bypass or arbitrary
   file-name overwrite. Broker/publish.sh:19.
4. P2: Publisher cleanup trap is installed after the target-directory check;
   failure at that check leaks the root-owned temporary source permit after
   posix_spawn succeeds. Permit expiry does not remove it. Broker/publish.sh:20.
5. P2: Server construction tests an existing socket with the full VPNIPCClient
   authorization flow. The VPN App caller cannot pass the SpringBoard broker
   check; on a same-main-queue live owner it can also block response, then
   unlink a live socket. Current helpers create one server per process, so
   this is defensive insufficiency, not proof of a routine startup failure.
   Shared/VPNIPC.m:314.

## Decision

Do not rename bfirst6 as a stable release, publish a new install package, or
replace iCloud. The user requested publication only if review found no issue;
that condition is not met. Preserve and commit the related maintained source,
regression/diagnostic code and records as unreleased work, excluding unrelated
changes and historical/debug DEBs. Candidate packages remain local in packages/.
No source fix, device mutation or new device test was performed in this review.

Previous complete bfirst6 six-direction and three-provider on/off results
remain valid observations, not exhaustive stability evidence. The interrupted
same-version close regression is unresolved. Review findings are code-based;
none is presented as the proven cause of the earlier unexplained host restart.

## Test-oracle findings and final scope

6. P1: The concurrent-close/expiry regression logs completion even when no
   authenticated client was acquired; expiry probe still succeeding does not
   fail the test either. Ready counts and per-line results were manually
   checked in earlier runs, so their recorded observations are not overturned,
   but completion markers alone are not a reliable automated pass oracle.
   tools/live-acceptance/assertion-close-stress.m:56.
7. P1: Historical native-probe --net can exit zero after HTTP/body/network
   failure because it tests callback completion, not network success. The
   older live-acceptance host similarly progresses after network failure.
   The new bfirst-switch-host already stops on network failure. Historical
   manually checked HTTPS results remain observations, not invalidated by
   this oracle defect. EasyVPNHelper/native-probe.m:121.

Final review: 5 P1 and 2 P2, no confirmed P0. Full machine-readable findings
are in REVIEW_FINDINGS_20261115.json; the user-facing detailed report selects
all five P1 findings. Source-only WIP commit includes the maintained production
and research/test code plus documentation. All untracked historical/current
candidate DEBs remain local, unstaged and unshipped. Cross-group check confirms
controller system readback mitigates the false helper stop reply but does not
remove the stale native-start result race or root publication path race.
