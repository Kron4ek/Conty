#!/usr/bin/env bash

set -e

source settings.sh

script_dir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
build_dir="${script_dir}/$BUILD_DIR"
utils_dir="${build_dir}/utils"
image_path="${build_dir}"/image
bootstrap="${build_dir}"/root.x86_64

if [ ! -d "${bootstrap}" ]; then
	echo "Bootstrap at $bootstrap is missing. Use the create-arch-bootstrap.sh script to create it"
	exit 1
fi

if [ ! -f "$script_dir"/conty-start.sh ]; then
	echo "conty-start.sh is required!"
	exit 1
fi

if [ -n "$USE_DWARFS" ]; then
	utils="utils_dwarfs.tar.gz"
else
	utils="utils.tar.gz"
fi

if [ ! -f "$utils" ]; then
	echo "$utils is not available locally, trying to fetch them from repository"
 	if git config --get remote.origin.url; then
		utils_url="$(git config --get remote.origin.url)/raw/$(git rev-parse --abbrev-ref HEAD)/$utils"
	else
		utils_url="https://github.com/Kron4ek/Conty/raw/master/$utils"
   	fi
	curl --output-dir "$build_dir" -#LO "$utils_url"
fi

echo "Extracting $utils"
rm -rf "$utils_dir"
if ! tar -C "$build_dir" -xzf "$utils"; then
	echo "Error occured while trying to extract $utils"
	exit 1
fi

launch_wrapper () {
	if [ -n "${USE_SYS_UTILS}" ]; then
		if ! command -v "${1}" 1>/dev/null; then
			echo "Please install $(echo "${1}" | tail -c +3) and run the script again"
			exit 1
		fi

		"$@"
	else
		PATH="${utils_dir}:$PATH" "${utils_dir}"/ld-linux-x86-64.so.2 --library-path "${utils_dir}" "$@"
	fi
}

# Create the image
echo "Creating Conty..."
if [ ! -f "${image_path}" ] || [ -z "${USE_EXISTING_IMAGE}" ]; then
	rm -f "${image_path}"
	if [ -n "$USE_DWARFS" ]; then
		launch_wrapper mkdwarfs -i "${bootstrap}" -o "${image_path}" "${DWARFS_COMPRESSOR_ARGUMENTS[@]}"
	else
		launch_wrapper mksquashfs "${bootstrap}" "${image_path}" "${SQUASHFS_COMPRESSOR_ARGUMENTS[@]}"
	fi
fi

for util in init bash busybox; do
	if [ ! -s "$utils_dir"/"$util" ]; then
		echo "$utils_dir/$util does not exist or is empty"
		exit 1
	fi
done

utils_size="$(stat -c%s "$utils")"
init_size="$(stat -c%s "$utils_dir"/init)"
bash_size="$(stat -c%s "$utils_dir"/bash)"
busybox_size="$(stat -c%s "$utils_dir"/busybox)"

cp "$script_dir"/conty-start.sh "$build_dir"/conty-start.sh
sed -i "s/init_size=.*/init_size=${init_size}/" "$build_dir"/conty-start.sh
sed -i "s/bash_size=.*/bash_size=${bash_size}/" "$build_dir"/conty-start.sh
sed -i "s/busybox_size=.*/busybox_size=${busybox_size}/" "$build_dir"/conty-start.sh
sed -i "s/utils_size=.*/utils_size=${utils_size}/" "$build_dir"/conty-start.sh

sed -i "s/script_size=.*/script_size=$(stat -c%s conty-start.sh)/" "$build_dir"/conty-start.sh
sed -i "s/script_size=.*/script_size=$(stat -c%s conty-start.sh)/" "$build_dir"/conty-start.sh

# Combine the files into a single executable using cat
cat "$utils_dir"/init \
	"$utils_dir"/bash \
	"$build_dir"/conty-start.sh \
	"$utils_dir"/busybox \
	"$utils" \
	"$image_path" > "$script_dir"/conty.sh
chmod +x "$script_dir"/conty.sh
echo "Conty created and ready to use!"
