#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
out=${1:?usage: run-config-tests.sh OUTPUT_DIRECTORY}
mkdir -p "$out"
xcrun clang -fobjc-arc -Wall -Wextra -Werror -DSI_SETTINGS_TEST=1 \
    -fsanitize=address,undefined -g -framework Foundation \
    "$root/Preferences/SIConfigCodec.m" "$root/SISettingsStore.m" "$root/tests/config_codec_test.m" \
    -o "$out/config-codec-test"
"$out/config-codec-test" "$root/Preferences/Resources"
xcrun clang -Wall -Wextra -Werror -I"$root/Shared" -fsanitize=address,undefined -g \
    "$root/tests/rate_test.c" "$root/Shared/SIRate.c" "$root/Shared/SIPresentation.c" -lm -o "$out/rate-test"
"$out/rate-test"
python3 "$root/tests/preview_config_test.py" "$out"
python3 "$root/tests/color_config_test.py" "$out"
python3 "$root/tests/scheduling_test.py" "$out"
python3 "$root/tests/landscape_visibility_test.py" "$out"
