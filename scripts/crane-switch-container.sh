#!/bin/sh

set -eu

usage() {
    cat <<'EOF'
Usage: crane-switch-container.sh <ssh-control-socket> <ssh-target> <bundle-id> <container>

Examples:
  crane-switch-container.sh /tmp/device_mux mobile@device com.example.app name:Work
  crane-switch-container.sh /tmp/device_mux mobile@device com.example.app CONTAINER-UUID
EOF
}

if [ "$#" -ne 4 ]; then
    usage >&2
    exit 2
fi

control_socket=$1
ssh_target=$2
bundle_id=$3
container=$4

case "$bundle_id" in
    com.taobao.*|com.alibaba.*|com.alipay.*|com.antgroup.*|com.autonavi.*|cn.damai.*|com.alicloud.*|com.quark.*|com.360buy.*|com.jingdong.*|com.jd.*|*.bank*|*.finance*|*.securit*|*.wallet*|*.pay*)
        echo "Refusing Crane injection for protected app: $bundle_id" >&2
        exit 3
        ;;
esac

ssh_device() {
    ssh -S "$control_socket" -o BatchMode=yes -o ControlMaster=no "$ssh_target" "$@"
}

container_list=$(ssh_device "/usr/local/bin/cranectl --list '$bundle_id'" 2>/dev/null || true)
if [ -z "$container_list" ]; then
    echo "Crane has no container configuration for $bundle_id" >&2
    exit 4
fi

expected_container_identifier=
case "$container" in
    DEFAULT)
        ;;
    name:*)
        expected_name=${container#name:}
        while IFS= read -r container_line; do
            container_name=${container_line% (*}
            container_identifier=${container_line##*(}
            container_identifier=${container_identifier%)}
            if [ "$container_name" = "$expected_name" ]; then
                expected_container_identifier=$container_identifier
                break
            fi
        done <<EOF
$container_list
EOF
        if [ -z "$expected_container_identifier" ]; then
            echo "Unknown Crane container name for $bundle_id: $expected_name" >&2
            exit 9
        fi
        ;;
    *)
        expected_container_identifier=$container
        ;;
esac

app_path=$(ssh_device "uicache -l 2>/dev/null | awk -F ' : ' -v id='$bundle_id' '\$1 == id { print \$2; exit }'")
if [ -z "$app_path" ]; then
    echo "Unable to locate application path for $bundle_id" >&2
    exit 5
fi

executable=$(ssh_device "plutil -key CFBundleExecutable '$app_path/Info.plist' 2>/dev/null")
if [ -z "$executable" ]; then
    echo "Unable to read CFBundleExecutable for $bundle_id" >&2
    exit 6
fi

process_path=$app_path/$executable
case "$process_path" in
    /private/*) process_path=${process_path#/private} ;;
esac

old_pids=$(ssh_device "/rootfs/bin/ps -axo pid=,command= 2>/dev/null | awk -v path='$process_path' '\$0 ~ path { print \$1 }'" || true)
old_pids=$(printf '%s\n' "$old_pids" | tr '\n' ' ' | sed 's/[[:space:]]*$//')

ssh_device "/usr/local/bin/cranectl --switch '$bundle_id' '$container'"

if [ -n "$old_pids" ]; then
    ssh_device "kill -9 $old_pids 2>/dev/null || true"
fi

ssh_device "uiopen --bundleid '$bundle_id' >/dev/null 2>&1"

attempt=0
new_pid=
while [ "$attempt" -lt 20 ]; do
    new_pid=$(ssh_device "/rootfs/bin/ps -axo pid=,command= 2>/dev/null | awk -v path='$process_path' '\$0 ~ path { print \$1; exit }'" || true)
    if [ -n "$new_pid" ]; then
        break
    fi
    attempt=$((attempt + 1))
    sleep 0.5
done

if [ -z "$new_pid" ]; then
    echo "Container switched, but $bundle_id did not relaunch" >&2
    exit 7
fi

for old_pid in $old_pids; do
    if [ "$new_pid" = "$old_pid" ]; then
        echo "Application process was not replaced: pid=$new_pid" >&2
        exit 8
    fi
done

if [ -n "$expected_container_identifier" ]; then
    process_environment=$(ssh_device "/rootfs/bin/ps eww -p '$new_pid' 2>/dev/null" || true)
    case " $process_environment " in
        *" CRANE_CONTAINER_IDENTIFIER=$expected_container_identifier "*)
            ;;
        *)
            echo "Crane container takeover failed for $bundle_id: expected CRANE_CONTAINER_IDENTIFIER=$expected_container_identifier" >&2
            exit 10
            ;;
    esac
fi

printf 'bundle_id=%s\ncontainer=%s\nexecutable=%s\nnew_pid=%s\n' \
    "$bundle_id" "$container" "$executable" "$new_pid"
