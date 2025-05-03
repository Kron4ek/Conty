#!/usr/bin/env bash

script_dir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
bootstrap="${script_dir}"/root.x86_64

if [ ! -d "${bootstrap}" ]; then
    echo "Bootstrap is missing"
    exit 1
fi

enter_namespace() {
	mount --bind "$bootstrap"/ "$bootstrap"/
	mount --rbind /proc "$bootstrap"/proc
	mount --rbind /dev "$bootstrap"/dev
	mount none -t devpts "$bootstrap"/dev/pts
	mount none -t tmpfs "$bootstrap"/dev/shm
	chroot "$bootstrap" /usr/bin/env -i USER='root' HOME='/root' /bin/bash
}

export bootstrap
export -f enter_namespace
unshare --uts --ipc --user --mount --map-auto --map-root-user --pid --fork -- bash -c enter_namespace
