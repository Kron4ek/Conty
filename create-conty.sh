#!/usr/bin/env bash

# Dependencies: squashfs-tools zstd lz4

script_dir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

# Builtin suqashfuse supports only lz4 and zstd
# So choose either lz4 or zstd
squashfs_compressor="lz4"
compressor_arguments="-Xhc"

bootstrap="${script_dir}"/root.x86_64

cd "${script_dir}" || exit 1

if [ ! -f utils.tar ] || [ "$(wc -c < utils.tar)" -lt 1000 ]; then
	rm -f utils.tar
	wget -q --show-progress "https://github.com/Kron4ek/Conty/raw/master/utils.tar"
fi

if [ ! -f squashfs-start.sh ]; then
	echo "squashfs-start.sh is required!"
	exit 1
fi

if ! command -v mksquashfs 1>/dev/null; then
	echo "Please install squashfs-tools and run the script again"
	exit 1
fi

if [ ! -d "${bootstrap}" ]; then
	echo "Bootstrap is required!"
	exit 1
fi

echo
echo "Creating conty..."
echo

# Create the squashfs image
rm -f bootstrap.squashfs
mksquashfs "${bootstrap}" bootstrap.squashfs -comp $squashfs_compressor $compressor_arguments

# Combine the files into a single executable using cat
cat squashfs-start.sh utils.tar bootstrap.squashfs > conty.sh
chmod +x conty.sh

clear
echo "Conty created and ready to use!"
