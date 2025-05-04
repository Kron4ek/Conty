#!/usr/bin/env bash

set -e
source settings.sh
script_dir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
build_dir="${script_dir}/$BUILD_DIR"
bootstrap="$build_dir/root.x86_64"

if [ ! -d "${bootstrap}" ]; then
	echo "Bootstrap at $bootstrap is missing. Use the create-arch-bootstrap.sh script to create it"
    exit 1
fi

enter_namespace() {
	mount --bind "$bootstrap"/ "$bootstrap"/
	mount --rbind /proc "$bootstrap"/proc
	mount --rbind /dev "$bootstrap"/dev
	mount none -t devpts "$bootstrap"/dev/pts
	mount none -t tmpfs "$bootstrap"/dev/shm
	chroot "$bootstrap" /usr/bin/env -i USER='root' HOME='/root' /bin/bash -c 'source /etc/profile; exec bash'
}

export bootstrap
export -f enter_namespace
unshare --uts --ipc --user --mount --map-auto --map-root-user --pid --fork -- bash -c enter_namespace
