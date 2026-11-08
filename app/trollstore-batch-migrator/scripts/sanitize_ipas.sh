#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
    echo "usage: $0 INPUT_DIRECTORY OUTPUT_DIRECTORY" >&2
    exit 64
fi

input_directory=$1
output_directory=$2
ldid_path=${LDID:-ldid}
work_directory=$(mktemp -d)
trap 'rm -rf "$work_directory"' EXIT

mkdir -p "$output_directory"

sanitize_ipa() {
    input_path=$1
    output_path=$2
    package_directory="$work_directory/package"
    rm -rf "$package_directory"
    mkdir -p "$package_directory"
    ditto -x -k "$input_path" "$package_directory"

    find "$package_directory/Payload" -type f -perm -111 -print | while IFS= read -r binary_path; do
        entitlements_path="$work_directory/entitlements.plist"
        if ! "$ldid_path" -e "$binary_path" > "$entitlements_path" 2>/dev/null; then
            continue
        fi
        for entitlement_key in \
            get-task-allow \
            com.apple.security.get-task-allow \
            task_for_pid-allow \
            com.apple.system-task-ports \
            com.apple.system-task-ports.control \
            com.apple.system-task-ports.token.control \
            com.apple.private.cs.debugger
        do
            /usr/libexec/PlistBuddy -c "Delete :$entitlement_key" "$entitlements_path" >/dev/null 2>&1 || true
        done
        "$ldid_path" -S"$entitlements_path" "$binary_path"
    done

    rm -f "$output_path"
    (cd "$package_directory" && /usr/bin/zip -qry "$output_path" Payload)
}

for input_path in "$input_directory"/*.ipa; do
    output_path="$output_directory/$(basename "$input_path")"
    case "$(basename "$input_path")" in
        com.developlab.BatteryInfo-*|com.iosdump.trollcm-*|com.mika.LocationSimulation-*)
            sanitize_ipa "$input_path" "$(cd "$(dirname "$output_path")" && pwd)/$(basename "$output_path")"
            ;;
        *)
            cp "$input_path" "$output_path"
            ;;
    esac
done
