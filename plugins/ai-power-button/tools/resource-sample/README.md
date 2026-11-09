# Finite SpringBoard resource sampler

Read-only diagnostic CLI, not linked into the tweak. Accepts only a PID whose
native process path is exactly SpringBoard. Takes 12 samples 3 seconds apart,
rejects identity changes, then exits. Uses proc_pid_rusage, not task_for_pid,
debugger attachment, hooks, application data, or screenshot capture.

Compile main.c for arm64 with the retained iPhoneOS SDK and sign locally for
the authorized device. Results describe the entire SpringBoard process,
not the tweak alone. No disabled-baseline comparison or energy measurement
is implied. The sampler's sleep loop is test-only; it is not a background
service and is never included in released packages.
