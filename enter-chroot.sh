#!/usr/bin/env bash

# Root rights are required

if [ $EUID != 0 ]; then
    echo "Root rights are required!"

    exit 1
fi

script_dir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

bootstrap="${script_dir}"/root.x86_64

if [ ! -d "${bootstrap}" ]; then
    echo "Bootstrap is missing"
    exit 1
fi

# First unmount just in case
umount -Rl "${bootstrap}"

mount --bind "${bootstrap}" "${bootstrap}"
mount -t proc /proc "${bootstrap}"/proc
mount --bind /sys "${bootstrap}"/sys
mount --make-rslave "${bootstrap}"/sys
mount --bind /dev "${bootstrap}"/dev
mount --bind /dev/pts "${bootstrap}"/dev/pts
mount --bind /dev/shm "${bootstrap}"/dev/shm
mount --make-rslave "${bootstrap}"/dev

rm -f "${bootstrap}"/etc/resolv.conf
cp /etc/resolv.conf "${bootstrap}"/etc/resolv.conf

mkdir -p "${bootstrap}"/run/shm

echo "Entering chroot"
echo "To exit the chroot, perform the \"exit\" command"
chroot "${bootstrap}" /usr/bin/env LANG=en_US.UTF-8 TERM=xterm PATH="/bin:/sbin:/usr/bin:/usr/sbin" /bin/bash
echo "Exiting chroot"

umount -l "${bootstrap}"
umount "${bootstrap}"/proc
umount "${bootstrap}"/sys
umount "${bootstrap}"/dev/pts
umount "${bootstrap}"/dev/shm
umount "${bootstrap}"/dev
