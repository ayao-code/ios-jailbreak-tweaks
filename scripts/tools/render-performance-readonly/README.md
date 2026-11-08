# Read-only render performance probe

Standalone console diagnostic for authorized iOS 16.3 testing. It calls the
existing QuartzCore render-server query, never injects a dylib, attaches a
debugger, suspends a thread, modifies a render option, or accesses an app sandbox.
An external read of the iOS 16.3 implementation confirms its single Mach-port
argument and created-property-list return. Other iOS versions are unverified.
The output retains numeric metrics, limits recursion and hides string/data
values. Render-server metrics alone do not prove an individual application's
frame production or the panel's physical refresh rate.

Use a process timeout and `_SafeMode=1 _MSSafeMode=1`. No resident polling.

## Verified display counter path

`--display-stats` calls `CARenderServerGetStatistics(mach_port_t, char ***)`.
External inspection of iOS 16.3 verifies that it creates display descriptions
using `malloc` and `asprintf` and returns their count. `--sample` reads only LCD
frame/skip counters at 10 Hz for about 6 seconds, then exits. It reports the
current low-power and thermal state without changing either. The console
signature needs `com.apple.QuartzCore.debug` to read statistics; without it the
queries returned empty results. The entitlement is on this standalone process
only, not on an application or system executable. No global debug option is set.

Build: `bash scripts/tools/render-performance-readonly/build.sh`.

`run-scroll-test.py` opens only SMS/WeChat, wakes the display through the existing
screen helper, checks unlock/foreground and two stable screenshots, then runs
one optional authorized scroll with the separate SMS/WeChat-only HID helper.
Only frame counters, timings, state booleans and screenshot hashes/change
booleans are saved. Message/chat image contents stay in memory and are discarded.
It never opens a conversation or sends a message. A changed screen, unknown
foreground, locked device or absent initial sample refuses input. The observed
rate is LCD compositor output, not a guaranteed per-app FPS measurement, and
synthetic touch pacing can differ from human input. Do not use it to assert a
specific tweak caused a frame-rate dip without a separate controlled comparison.

Retained external read evidence is in `research/`. The counter query and its
numeric interpretation were actually checked on an iPhone15,3 with iOS 16.3.
The generic performance-info query returned an empty array even with permission;
it is not used as frame-rate evidence.
