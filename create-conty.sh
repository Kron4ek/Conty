#!/usr/bin/env bash

# Dependencies: squashfs-tools

script_dir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

# Supported compression algorithms: lz4, zstd, gzip, xz, lzo
# These are the algorithms supported by the integrated squashfuse
# However, your squashfs-tools (mksquashfs) may not support some of them
squashfs_compressor="lz4"
compressor_arguments="-Xhc"

# Set to true to use an existing squashfs image if it exists
# Otherwise the script will always create a new image
use_existing_image="false"

bootstrap="${script_dir}"/root.x86_64

cd "${script_dir}" || exit 1

if [ ! -f utils.tar ] || [ "$(wc -c < utils.tar)" -lt 1000 ]; then
	rm -f utils.tar
	wget -q --show-progress "https://github.com/Kron4ek/Conty/raw/master/utils.tar"
fi

if [ ! -f conty-start.sh ]; then
	echo "conty-start.sh is required!"
	exit 1
fi

# Check if selected compression algorithm is supported by mksquashfs
if command -v grep 1>/dev/null; then
	# mksquashfs writes its output to stderr instead of stdout
	mksquashfs &>mksquashfs_out.txt

	if [ ! "$(cat mksquashfs_out.txt | grep ${squashfs_compressor})" ]; then
		echo "Seems like your mksquashfs doesn't support the selected"
		echo "compression algorithm (${squashfs_compressor})."
		echo
		echo "Choose another algorithm and run the script again"

		exit 1
	fi

	rm -f mksquashfs_out.txt
fi

echo
echo "Creating Conty..."
echo

# Create the squashfs image
if [ ! -f image ] || [ "${use_existing_image}" != "true" ]; then
	if ! command -v mksquashfs 1>/dev/null; then
		echo "Please install squashfs-tools and run the script again"
		exit 1
	fi

	if [ ! -d "${bootstrap}" ]; then
		echo "Distro bootstrap is required!"
		echo "Use the create-arch-bootstrap.sh script to get it"
		exit 1
	fi

	rm -f image
	mksquashfs "${bootstrap}" image -b 256K -comp ${squashfs_compressor} ${compressor_arguments}
fi

# Combine the files into a single executable using cat
cat conty-start.sh utils.tar image > conty.sh
chmod +x conty.sh

clear
echo "Conty created and ready to use!"
