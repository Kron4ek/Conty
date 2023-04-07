#!/usr/bin/env bash

# Dependencies: squashfs-tools or dwarfs

script_dir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

# Enable this variable to use the system-wide mksquashfs/mkdwarfs instead
# of those provided by the Conty project
USE_SYS_UTILS=0

# Supported compression algorithms: lz4, zstd, gzip, xz, lzo
# These are the algorithms supported by the integrated squashfuse
# However, your squashfs-tools (mksquashfs) may not support some of them
squashfs_compressor="zstd"
squashfs_compressor_arguments=(-b 1M -comp ${squashfs_compressor} -Xcompression-level 19)

# Uncomment these variables if your mksquashfs does not support zstd or
# if you want faster compression/decompression (at the cost of compression ratio)
#squashfs_compressor="lz4"
#squashfs_compressor_arguments=(-b 256K -comp "${squashfs_compressor}" -Xhc)

# Use DwarFS instead of SquashFS
# If you enable this, don't forget to change utils_size in conty-start.sh
dwarfs="false"
dwarfs_compressor_arguments=(-l7 -C zstd:level=19 --metadata-compression null \
                            -S 22 -B 2 --order nilsimsa:255:60000:60000 \
                            --bloom-filter-size 11 -W 15 -w 3 --no-create-timestamp)

# Set to true to use an existing image if it exists
# Otherwise the script will always create a new image
use_existing_image="false"

image_path="${script_dir}"/image

bootstrap="${script_dir}"/root.x86_64

launch_wrapper () {
	if [ "${USE_SYS_UTILS}" != 0 ]; then
		if ! command -v "${1}" 1>/dev/null; then
			echo "Please install $(echo "${1}" | tail -c +3) and run the script again"
			exit 1
		fi

		"$@"
	else
		"${script_dir}"/utils/ld-linux-x86-64.so.2 --library-path "${script_dir}"/utils "${script_dir}"/utils/"$@"
	fi
}

cd "${script_dir}" || exit 1

if [ "${dwarfs}" = "true" ]; then
	utils="utils_dwarfs.tar.gz"
	compressor_command=(mkdwarfs -i "${bootstrap}" -o "${image_path}" "${dwarfs_compressor_arguments[@]}")
else
	utils="utils.tar.gz"
	compressor_command=(mksquashfs "${bootstrap}" "${image_path}" "${squashfs_compressor_arguments[@]}")
fi

if [ ! -f "${utils}" ] || [ "$(wc -c < "${utils}")" -lt 1000 ]; then
	rm -f "${utils}"
	curl -#LO "https://github.com/Kron4ek/Conty/raw/master/${utils}"
fi

if [ ! -f conty-start.sh ]; then
	echo "conty-start.sh is required!"
	exit 1
fi

rm -rf utils
tar -zxf "${utils}"

if [ $? != 0 ]; then
	echo "Something is wrong with ${utils}"
	exit 1
fi

if [ "${USE_SYS_UTILS}" != 0 ]; then
	rm -rf utils
fi

# Check if selected compression algorithm is supported by mksquashfs
if [ "${USE_SYS_UTILS}" != 0 ] && [ "${dwarfs}" != "true" ] && command -v grep 1>/dev/null; then
	# mksquashfs writes its output to stderr instead of stdout
	mksquashfs &>mksquashfs_out.txt

	if ! grep -q "${squashfs_compressor}" mksquashfs_out.txt; then
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

# Create the image
if [ ! -f "${image_path}" ] || [ "${use_existing_image}" != "true" ]; then
	if [ ! -d "${bootstrap}" ]; then
		echo "Distro bootstrap is required!"
		echo "Use the create-arch-bootstrap.sh script to get it"
		exit 1
	fi

	rm -f "${image_path}"
	launch_wrapper "${compressor_command[@]}"
fi

# Combine the files into a single executable using cat
cat conty-start.sh "${utils}" "${image_path}" > conty.sh
chmod +x conty.sh

clear
echo "Conty created and ready to use!"
