#!/usr/bin/env bash

# Root rights are required

if [ $EUID != 0 ]; then
    echo "Root rights are required!"

    exit 1
fi

unmount() {
	umount -l "${bootstrap}"
	for fs in proc sys dev/pts dev/shm dev; do
		umount "${bootstrap}"/"${fs}"
	done
}

script_dir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

bootstrap="${script_dir}"/root.x86_64

if [ ! -d "${bootstrap}" ]; then
    echo "Bootstrap is missing"
    exit 1
fi

# First unmount just in case
unmount

mount -o bind "${bootstrap}" "${bootstrap}"
mount -t proc /proc "${bootstrap}"/proc
mount -t sysfs /sys "${bootstrap}"/sys
mount -o bind /dev "${bootstrap}"/dev
mount -o bind /dev/pts "${bootstrap}"/dev/pts
mount -o bind /dev/shm "${bootstrap}"/dev/shm

rm -f "${bootstrap}"/etc/resolv.conf
cp /etc/resolv.conf "${bootstrap}"/etc/resolv.conf

mkdir -p "${bootstrap}"/run/shm

echo "Entering chroot"
echo "To exit the chroot, perform the \"exit\" command"
chroot "${bootstrap}" /usr/bin/env LANG=en_US.UTF-8 TERM=xterm PATH="/bin:/sbin:/usr/bin:/usr/sbin" /bin/bash
echo "Exiting chroot"

unmount
