# bfirst5-classguard1: class isolation and real-host regression

Device: iPhone13,1 / iOS 16.3.1 / RootHide. Date: 2026-11-15.
Installed package: `1.3.0~bfirst5-classguard1`, `iphoneos-arm64e`.

## Why the last test entered safe mode

The 18:13:26 and 18:13:53 SpringBoard crash reports identify the temporary
cancel regression host sending `ready` to the system `VPNController`.
VPNPreferences exports that class (a PSListController subclass), so a bare
`NSClassFromString(@"VPNController")` did not identify our implementation.
This was a test-host error, not proof that the production cancel path passed.
The interrupted earlier run must not be counted as a completed regression.

The production class is now `AYAVPNController`; the maintained files remain
`VPNController.h` and `VPNController.m`. Test hosts obtain the controller from
the installed module, check its exact class and owning Mach-O image, and check
method argument counts and return types before calling it. The same guard is
used for the installed IPC client in cancel/concurrent-close regressions.
No copied controller or IPC implementation replaces the production code.

The bfirst4 opening-FD cancellation, early controller client registration,
pre-dispatch lock check, and identical-snapshot suppression remain. Normal
provider switches have no added delay, cache, permanent execution assertion,
or command to stop the old provider. The finite 15-second assertion remains.

## Non-network regressions

- Local runtime origin/signature checks: 10/10.
- Real SpringBoard cancel-during-open: 10/10; opening FD observed in all 10,
  open/probe false after cancellation, elapsed 0.071-0.126 seconds.
- Twenty identical snapshot reloads: zero state-change callbacks.
- Real installed IPC acquire/probe and two concurrent closes: 10/10;
  ready_count=10 and concurrent_close_completed=1 for each iteration.
- These regressions do not send VPN connect/disconnect commands.
- Assertion expiry was not rerun on this build; prior safety-build evidence
  remains historical, not an additional bfirst5 pass.

## Network regression, including the failure

The SpringBoard host calls the installed view's select/buttonTapped handlers.
It requires the exact target to be the sole active, connected configuration,
checks it again after six seconds, then requests the Apple HTTPS success page.
Network failure now stops the sequence, rather than silently proceeding.
This is real device business-handler execution, not finger/HID/visual testing.

| Operation | Handler-to-stable readback | Sole target after 6 s | HTTPS |
| --- | --- | --- | --- |
| Initial Easy connect | 10.991 s | yes | 200, Success |
| Easy -> Feilian | 17.040 s | yes | 200, Success |
| Feilian -> Hotspot | 13.076 s | yes | 200, Success |
| Hotspot -> Easy | 9.033 s | yes | 200, Success |
| Easy -> Hotspot | 10.062 s | yes | 200, Success |
| Hotspot -> Feilian | 16.030 s | yes | timeout -1001 |

The first sequence stops at that HTTPS timeout. An independent read-only
provider/network tool then confirms Feilian is connected, all other targets
are disconnected, and HTTPS returns 200 with Success. This later pass does
NOT erase the first timeout or turn the first sequence into a full pass.
A subsequent continuation requires Feilian to remain the sole source; after
SpringBoard refresh it is no longer connected, so the precondition rejects
without issuing a switch. The refresh/disconnect association is observed;
its cause is not established and must not be described as solved.

Busy-state layout readbacks for the initial connection and five attempted
switches show a running UIActivityIndicatorView at delta_x=delta_y=0.000.
This validates compact-view geometry only, not actual expanded-menu appearance.

## Release gate and safety boundaries

Jump and GOFast remain Beta and are excluded from the main switching matrix.
A successful sole VPN readback does not prove all business destinations or
long-term network availability. No claim of 100 percent stability, performance
improvement, or full visual/touch acceptance follows from this small sample.
The previous bfirst3 failures are preserved in BFIRST_STATUS.md.

The latest package SHA256 is
`10612ad6d979fe770fbf72f991da58aab39435fd7a40fc0c780d60b9f08ee545`.
Source/test files and nested package content were privacy-screened, not pushed
or committed. No high-sensitivity app injection/configuration was changed.
iCloud was not written; the old silent1 artifact remains unchanged with hash
`be50d18795248a1d129a510c01d4443658a80232bbf68159c106accff9c19013`.
Final cleanup and supplemental direction results are recorded below.

## Supplemental attempt and next candidate

The bfirst5 independent supplemental run began all-off with Feilian selected.
Initial Feilian connect failed helper preparation at 2.139 seconds controller
elapsed (3.988 seconds from test selection); no connect-dispatch was sent.
All targets remained off, and no new crash report was observed. A later socket
readback found a mobile-owned 0600 socket. This readiness race was addressed
in bfirst6-coldready1; subsequent results belong to that version and are
recorded in COLDREADY_RETEST_20261115.md, not added to this build's pass count.
