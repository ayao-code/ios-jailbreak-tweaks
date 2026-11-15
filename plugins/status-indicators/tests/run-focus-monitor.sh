#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
out=${1:?usage: run-focus-monitor.sh OUTPUT_DIRECTORY}
mkdir -p "$out"
xcrun clang -fobjc-arc -fblocks -Wall -Wextra -Werror -DSI_FOCUS_TEST=1 \
    -fsanitize=address,undefined -g -framework Foundation \
    "$root/SIFocusMonitor.m" "$root/tests/focus_monitor_test.m" -o "$out/focus-monitor-test"
"$out/focus-monitor-test"
python3 "$root/tests/host_update_test.py" "$out"
