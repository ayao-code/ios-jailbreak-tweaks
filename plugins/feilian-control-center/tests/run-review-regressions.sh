#!/bin/bash
set -euo pipefail
project=$(cd "$(dirname "$0")/.." && pwd)
output=${1:?usage: run-review-regressions.sh OUTPUT_DIRECTORY}
mkdir -p "$output"
xcrun clang -fobjc-arc -Wall -Wextra -Werror -Wno-objc-property-no-attribute \
  -Wno-undeclared-selector -I"$project/tests/host-stubs" -framework Foundation \
  "$project/tests/easy-lifecycle-test.m" -o "$output/easy-lifecycle-test"
"$output/easy-lifecycle-test"
xcrun clang -fobjc-arc -Wall -Wextra -Werror -framework Foundation \
  "$project/tools/live-acceptance/runtime-guard-test.m" -o "$output/runtime-guard-test"
"$output/runtime-guard-test"
python3 "$project/tests/oracle-check.py"
