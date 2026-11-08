#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
OUT="$(mktemp -d /tmp/autoskip-guard-check.XXXXXX)"
VERSION=${VERSION:-0.4.6}
DIAGNOSTICS=${DIAGNOSTICS:-0}
clang -std=c11 -Wall -Wextra -Werror -I. ASGPolicy.c tests/policy_test.c -o "$OUT/policy-test"
"$OUT/policy-test"
clang -std=c11 -Wall -Wextra -Werror -I. ASGPolicy.c tests/ocr_schedule_test.c -o "$OUT/ocr-schedule-test"
"$OUT/ocr-schedule-test"
clang -fobjc-arc -fblocks -Wall -Wextra -Werror -I. -framework Foundation ASGMatchers.m tests/matchers_test.m -o "$OUT/matchers-test"
"$OUT/matchers-test"
clang -fobjc-arc -fblocks -Wall -Wextra -Werror -I. -framework Foundation ASGActionIdentity.m tests/action_identity_test.m -o "$OUT/action-identity-test"
"$OUT/action-identity-test"
clang -fobjc-arc -fblocks -Wall -Wextra -Werror -I. -framework Foundation ASGCache.m ASGPolicy.c tests/cache_test.m -o "$OUT/cache-test"
"$OUT/cache-test"
clang -fobjc-arc -fblocks -Wall -Wextra -Werror -I. -framework Foundation ASGCache.m ASGPolicy.c tests/cache_recovery_test.m -o "$OUT/cache-recovery-test"
"$OUT/cache-recovery-test"
clang -fobjc-arc -fblocks -Wall -Wextra -Werror -I. -DASG_DIAGNOSTICS=1 -framework Foundation -framework QuartzCore ASGDiagnostics.m tests/diagnostics_test.m -o "$OUT/diagnostics-test"
"$OUT/diagnostics-test"
make all VERSION="$VERSION" DIAGNOSTICS="$DIAGNOSTICS"
codesign --verify --strict "dist/AutoSkipGuard_${VERSION}_arm64.dylib"
otool -L "dist/AutoSkipGuard_${VERSION}_arm64.dylib"
printf 'Check artifacts: %s\n' "$OUT"
