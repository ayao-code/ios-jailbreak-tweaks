#!/bin/sh
# Fixed publisher using RootHide's existing shell tools. Pin cwd, then bind it
# to the broker's dev/inode before the first target write; never trust cd alone.
set -eu
[ "$(id -u)" = 0 ] || exit 2
[ "$#" = 4 ] || exit 2
source_path=$1
target=$2
case "$source_path" in /rootfs/var/run/.vpncc-permit-*) ;; *) exit 2 ;; esac
nonce=${source_path#/rootfs/var/run/.vpncc-permit-}
[ "${#nonce}" = 32 ] || exit 2
case "$nonce" in *[!0-9a-f]*) exit 2 ;; esac
[ ! -L "$source_path" ] && [ -f "$source_path" ] || exit 2
[ "$(stat -c '%u %a %s %h' "$source_path")" = '0 600 64 1' ] || exit 2
trap 'rm -f "$source_path"' EXIT INT TERM
case "$target" in /rootfs/var/mobile/Containers/Data/Application/*/tmp) ;; *) exit 2 ;; esac
identifier=${target#/rootfs/var/mobile/Containers/Data/Application/}
identifier=${identifier%/tmp}
[ "${#identifier}" = 36 ] || exit 2
case "$identifier" in *[!0-9A-Fa-f-]*) exit 2 ;; esac
case "$3:$4" in *[!0-9:]*|:*|*:) exit 2 ;; esac
cd -P "$target"
# A symlink swap before cd resolves to a different directory and fails here.
# Later renames cannot redirect relative writes: cwd holds the validated inode.
[ "$(stat -c '%d:%i:%u' .)" = "$3:$4:501" ] || exit 2
chmod 644 "$source_path"
mv -fT "$source_path" ./vcc1.permit
