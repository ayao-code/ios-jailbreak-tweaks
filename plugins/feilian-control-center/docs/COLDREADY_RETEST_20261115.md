# bfirst6-coldready1: bounded cold-start readiness

Device: iPhone13,1 / iOS 16.3.1 / RootHide. Date: 2026-11-15.
Installed: `1.3.0~bfirst6-coldready1`, `iphoneos-arm64e`.

## Change and evidence

A bfirst5 supplemental Feilian initial-connect attempt failed at the helper
preparation stage (no connect-dispatch). It stopped at 2.139 seconds after the
controller began, despite a subsequently present mobile-owned 0600 socket and
an existing Feilian process. This supports an asynchronous socket-readiness
race; it does not prove every helper failure has the same cause.

The controller previously tried ten times at 200 ms intervals; a successful
background launch callback does not mean the helper socket is initialized.
Connect and explicit-off preparation now retry on the IPC work queue within
an eight-second attempt window. A successful authenticated open/probe exits
immediately. This is not a fixed eight-second delay and does not add a cache,
keepalive, new worker, foreground fallback, or any command to stop old A.
All generation/cancel checks and client closes remain. UI work stays on main.
The existing open/handshake timeout and finite assertion cancellation still
apply: eight seconds bounds starting retries, not total connection latency.

The first bfirst6 supplemental run passed:

| Operation | Handler-to-stable readback | Sole target after 6 s | HTTPS |
| --- | --- | --- | --- |
| Initial Feilian connect | 8.042 s | yes | 200, Success |
| Feilian -> Easy | 11.023 s | yes | 200, Success |

It completed PREFERENCE_RESTORED=1 and BFIRST_TEST_DONE=1, then an independent
system readback confirmed all five targets off. Initial preference was Feilian.
The controller recorded target-ready at 3.888 seconds after starting Feilian:
longer than the old short retry window, consistent with the readiness fix.

The compact circular progress indicator was running at zero x/y offset in
both operations. The test executes the installed module handlers in the real
SpringBoard, not physical touch or expanded-menu visual acceptance.

## History and release boundaries

The previous bfirst5 sequence's Hotspot -> Feilian HTTPS timeout (-1001), later
independent successful HTTPS check, and rejected continuation are preserved
in CLASSGUARD_RETEST_20261115.md. They are not relabeled as bfirst6 passes.
The bfirst5 acquire/cancel/concurrent-close evidence remains version-specific;
expiry was not rerun on bfirst6 unless recorded below.

Jump and GOFast stay Beta, not stable-supported providers. These tests do not
prove all enterprise destinations, app-specific VPN compatibility, long-term
CPU/battery behavior or 100-percent reliability. No old-VPN manual cleanup,
identity/authentication bypass, RootHide isolation change or high-sensitivity
App injection is introduced. No commit or push was made.

Package SHA256:
`469c152ffc3b36c1940430c5827e6bad32ffeb99c36d92b14c69f0cc8308e25b`.
Nested package privacy scan passed. iCloud has not been written; its old silent1
artifact remains unchanged. Complete-matrix and cleanup observations follow.

## Complete bfirst6 matrix

| Direction | Handler-to-stable readback | Sole target after 6 s | HTTPS |
| --- | --- | --- | --- |
| Easy -> Feilian | 13.995 s | yes | 200, Success |
| Feilian -> Hotspot | 12.987 s | yes | 200, Success |
| Hotspot -> Easy | 9.061 s | yes | 200, Success |
| Easy -> Hotspot | 9.997 s | yes | 200, Success |
| Hotspot -> Feilian | 13.971 s | yes | 200, Success |
| Feilian -> Easy | 8.989 s | yes | 200, Success |

Six directions passed 6/6 with HTTPS and sole-target readback; initial Easy
connect also passed in 10.034 seconds. Six-direction median is 11.492 seconds,
range 8.989-13.995. PREFERENCE_RESTORED=1 and BFIRST_TEST_DONE=1 completed.
Initial and restored preference is Feilian. The extra six-second observation
and HTTPS requests are test steps, not waits added to ordinary switching.
Each busy geometry check showed animating=1 and zero x/y offset.

This sample supports correctness on these exercised paths, not a guarantee
of 100-percent future reliability. The prior bfirst3 last full matrix median
was 11.483 seconds, so no measured speed increase is claimed. The new change
avoids premature cold-start failure; it does not make native tunnel startup
itself faster or claim the earlier transient HTTPS issue has been fixed.

The installed RootHide-rewritten module/helper whole-file hashes differ from
the DEB originals. Both arm64 and arm64e __text hashes match for the installed
module and Feilian helper; dpkg and the loaded bundle both report bfirst6.
Do not report whole-file hash equality for these RootHide-rewritten binaries.

## Separate native on/off regression

| Provider | Initial connect readback | HTTPS | Explicit native off |
| --- | --- | --- | --- |
| Easy | 12.056 s | 200, Success | passed |
| Feilian | 7.072 s | 200, Success | passed |
| Hotspot | 14.012 s | 200, Success | passed |

Each operation began all-off; select followed by the actual installed
buttonTapped handler requested connection. After exact target/HTTPS checks,
the same handler issued explicit off and the controller confirmed none active.
The sequence completed with the original Feilian selection restored. This is
separate from switching, which still sends no old-provider stop command.

## Same-version cancellation regression

The completed bfirst6 cancel run reported opening_count=8, passed=8 over ten
attempts. Eight attempts observed an in-flight opening FD and passed immediate
cancellation (0.083-0.125 seconds); two attempts had no pending FD at the fixed
50 ms sampling point and therefore did not exercise the intended race window.
Those two log lines say passed=0: they are precondition misses, NOT additional
passes. All ten attempts returned open=0/probe=0 after cancellation, but this
cannot be reported as ten verified in-flight cancellations. The bfirst5 ten
observed-window passes are separately preserved as historical evidence.
Twenty identical reloads again produced zero state callbacks on bfirst6.

The new prepare window is a targeted startup-race correction, not a guarantee
that all attempts become faster. Expensive operations remain on the existing
IPC queue, and the controller/client generation checks bound canceled work.
The operation timer and assertion lease remain unchanged. No internal app
launcher framework, cache fallback or permanent prewarming was introduced.

## Interrupted same-version concurrent-close test

The bfirst6 concurrent-close log completed iterations 0-6 with ready=1 and
concurrent_close_completed=1, then contained another STRESS_STARTED marker and
another iteration 0. A fresh start during that run is observed; no new
SpringBoard crash filename or safe-mode marker was found at the immediate
readback. The cause is not established (absence of an IPS is not proof of no
process restart). This run is NOT 10/10, and repeated iteration 0 is not an
eighth unique pass. The temporary tests were stopped and removed immediately,
then SpringBoard was refreshed to unload them. No additional automatic retry
was initiated. The prior bfirst5 10/10 is historical, not a bfirst6 result.
This interruption leaves the final safety regression incomplete and keeps
the iCloud publication gate closed despite the main matrix passing.

## Final cleanup/readback

- Network test files were removed; both non-network test dylib/filter pairs
  were removed and SpringBoard refreshed to unload them. The repeated-start
  concurrent-close log was retained rather than called a completed run.
- After refresh: no safe-mode marker, normal native unlock readback LOCKED=0,
  and all five VPN profiles disconnected in an independent system readback.
- Actual installed version remains bfirst6-coldready1. Preferred provider is
  Feilian, matching the recorded initial preference of the final test runs.
- All four original RootHide/injection policy files compare byte-for-byte
  unchanged; no high-sensitivity App isolation change was made.
- Entire CrashReporter filename set has no additions relative to the first
  post-cancel full baseline; SpringBoard set also has no additions relative
  to this turn's pretest baseline. An unreported restart is still not excluded.
- This turn's device-side temporary test/package/client files were removed.
  One-shot native unlock dylib/filter were removed after the final refresh;
  their existing memory mapping exits on the next normal host restart.
- The iCloud artifact SHA256 is still
  be50d18795248a1d129a510c01d4443658a80232bbf68159c106accff9c19013;
  no iCloud write or publication was performed. Source and local packages
  remain available and maintained in this project. No commit or push.
- Physical tap/long-press, expanded visual layout, long-term resource usage,
  assertion-expiry regression, and the interrupted close-test cause remain
  unverified/unresolved. Main functional tests passing do not close the
  release gate or establish that the whole task is complete.
