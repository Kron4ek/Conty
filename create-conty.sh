#!/usr/bin/env bash

# Dependencies: sed, squashfs-tools or dwarfs

script_dir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
image_path="${script_dir}"/image
bootstrap="${script_dir}"/root.x86_64

source "${script_dir}"/settings.sh

launch_wrapper () {
	if [ "${USE_SYS_UTILS}" = 1 ]; then
		if ! command -v "${1}" 1>/dev/null; then
			echo "Please install $(echo "${1}" | tail -c +3) and run the script again"
			exit 1
		fi

		"$@"
	else
		"${script_dir}"/utils/ld-linux-x86-64.so.2 --library-path "${script_dir}"/utils "${script_dir}"/utils/"$@"
	fi
}

if ! command -v sed 1>/dev/null; then
	echo "sed is required"
	exit 1
fi

cd "${script_dir}" || exit 1

if [ -n "$USE_DWARFS" ]; then
	utils="utils_dwarfs.tar.gz"
	compressor_command=(mkdwarfs -i "${bootstrap}" -o "${image_path}" "${DWARFS_COMPRESSOR_ARGUMENTS[@]}")
else
	utils="utils.tar.gz"
	compressor_command=(mksquashfs "${bootstrap}" "${image_path}" "${SQUASHFS_COMPRESSOR_ARGUMENTS[@]}")
fi

if [ ! -f "${utils}" ] || [ "$(wc -c < "${utils}")" -lt 100000 ]; then
 	if git config --get remote.origin.url; then
		utils_url="$(git config --get remote.origin.url)"/raw/"$(git rev-parse --abbrev-ref HEAD)"/${utils}
	else
		utils_url="https://github.com/Kron4ek/Conty/raw/master/${utils}"
   	fi

	rm -f "${utils}"
	curl -#LO "${utils_url}"

	if [ ! -f "${utils}" ] || [ "$(wc -c < "${utils}")" -lt 100000 ]; then
		rm -f "${utils}"
		curl -#LO "https://gitlab.com/-/project/61149207/uploads/1ff27b6750e246ebd181260695bc95f3/utils.tar"
  		tar -xf utils.tar
	fi
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

# Check if selected compression algorithm is supported by mksquashfs
if [ "${USE_SYS_UTILS}" = 1 ] && [ -z "$USE_DWARFS" ] && command -v grep 1>/dev/null; then
	if ! mksquashfs 2>&1 | grep -q "${SQUASHFS_COMPRESSOR}"; then
		echo "Seems like your mksquashfs doesn't support the selected"
		echo "compression algorithm (${SQUASHFS_COMPRESSOR})."
		echo
		echo "Choose another algorithm and run the script again"

		exit 1
	fi
fi

echo
echo "Creating Conty..."
echo

# Create the image
if [ ! -f "${image_path}" ] || [ -z "${USE_EXISTING_IMAGE}" ]; then
	if [ ! -d "${bootstrap}" ]; then
		echo "Distro bootstrap is required!"
		echo "Use the create-arch-bootstrap.sh script to get it"
		exit 1
	fi

	rm -f "${image_path}"
	launch_wrapper "${compressor_command[@]}"
fi

if command -v sed 1>/dev/null; then
	utils_size="$(stat -c%s "${utils}")"
	init_size=0
	bash_size=0
	busybox_size=0

	if [ -s utils/init ]; then
		init_size="$(stat -c%s utils/init)"
	fi

	if [ -s utils/bash ]; then
		bash_size="$(stat -c%s utils/bash)"
	fi

	if [ -s utils/busybox ]; then
		busybox_size="$(stat -c%s utils/busybox)"
	fi

	if [ "${init_size}" = 0 ] || [ "${bash_size}" = 0 ]; then
		init_size=0
		bash_size=0
		rm -f utils/init utils/bash
	fi

	sed -i "s/init_size=.*/init_size=${init_size}/" conty-start.sh
	sed -i "s/bash_size=.*/bash_size=${bash_size}/" conty-start.sh
	sed -i "s/busybox_size=.*/busybox_size=${busybox_size}/" conty-start.sh
	sed -i "s/utils_size=.*/utils_size=${utils_size}/" conty-start.sh

	sed -i "s/script_size=.*/script_size=$(stat -c%s conty-start.sh)/" conty-start.sh
	sed -i "s/script_size=.*/script_size=$(stat -c%s conty-start.sh)/" conty-start.sh
fi

# Combine the files into a single executable using cat
cat utils/init utils/bash conty-start.sh utils/busybox "${utils}" "${image_path}" > conty.sh
chmod +x conty.sh

clear
echo "Conty created and ready to use!"
