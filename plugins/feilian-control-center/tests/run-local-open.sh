#!/bin/sh
set -eu
project=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
output=${1:?usage: run-local-open.sh OUTPUT_DIRECTORY}
mkdir -p "$output"
xcrun clang -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter \
    -DVPN_IPC_HOST_TEST=1 -fsanitize=address,undefined -g -framework Foundation \
    "$project/Shared/VPNIPC.m" "$project/tests/local-open-ipc-test.m" -o "$output/local-open-ipc-test"
"$output/local-open-ipc-test"
