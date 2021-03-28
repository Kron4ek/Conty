#!/usr/bin/env bash

## Dependencies: fuse2 tar

# Prevent launching as root
if [ -z $ALLOW_ROOT ]; then
	if [ $EUID = 0 ]; then
		echo "Do not run this app as root!"
		echo
		echo "If you really need to run it as root, set ALLOW_ROOT env variable."

		exit 1
	fi
fi

# Full path to the script
script_literal="${BASH_SOURCE[0]}"
script_name="$(basename "${script_literal}")"
script="$(readlink -f "${script_literal}")"

# Working directory where squashfs image will be mounted
# Default path: /tmp/scriptname_username_randomnumber
working_dir=/tmp/"$(basename "${script}")"_"$(id -un)"_$RANDOM

# It's important to set correct sizes below, otherwise there will be
# a problem with mounting the squashfs image due to an incorrectly calculated offset.

# The size of this script
scriptsize=5358

# The size of the utils.tar archive
# utils.tar contains bwrap and squashfuse binaries
utilssize=1259520

# Offset where the squashfs image is stored
offset=$((scriptsize+utilssize))


if [ "$1" = "--help" ] || [ "$1" = "-h" ] || ([ -z "$1" ] && [ -z "${AUTOSTART}" ] && [ ! -L "${script_literal}" ]); then
	echo "Usage: ./conty.sh command command_arguments"
	echo
	echo "Arguments:"
	echo
	echo -e "-e \tExtract squashfs image"
	echo -e "-o \tShow squashfs image offset"

	echo
	echo "Environment variables:"
	echo
	echo -e "AUTOSTART \tAutostarts an application specified in this variable"
	echo -e "\t\tFor example, AUTOSTART=\"steam\" or AUTOSTART=\"/home/username/"
	echo -e "\t\tprogram\""
	echo -e "AUTOARGS \tAutomatically appends arguments from this variable to a"
	echo -e "\t\tlaunched application. For example, AUTOARGS=\"--version\""
	echo -e "\t\tCan be used together with AUTOSTART, but also without it."
	echo -e "DISABLE_NET \tDisables network access"
	echo -e "SANDBOX \tEnables filesystem sandbox"
	echo -e "BIND \t\tBinds directories and files (separated by space) from host"
	echo -e "\t\tsystem to the container. All specified items must exist."
	echo -e "\t\tFor example, BIND=\"/home/username/.config /etc/pacman.conf\""
	echo
	echo "If you enable SANDBOX but don't set BIND, then"
	echo "no directories will be available at all. And a fake temporary HOME"
	echo "directory will be created inside the container."
	echo
	echo "Also, if the script is a symlink to itself but with different name,"
	echo "then the symlinked script will automatically run a program according it's name."
	echo "For instance, if the script is a symlink with the name \"wine\", then it will"
	echo "automatically run wine during launch. This is an alternative"
	echo "to AUTOSTART variable, but the variable has higher priority."

	exit
elif [ "$1" = "-e" ]; then
	if command -v unsquashfs 1>/dev/null; then
		unsquashfs -o $offset -d "$(basename "${script}")"_files "${script}"
	else
		echo "To extract the image install squashfs-tools."
	fi

	exit
elif [ "$1" = "-o" ]; then
	echo $offset

	exit
fi

# Check if FUSE2 is installed
if command -v fusermount 1>/dev/null; then
	fmount=fusermount
else
	echo "Please install fuse2 and run the app again"

	exit 1
fi

# Extract utils.tar
mkdir -p "${working_dir}"
tail -c +$((scriptsize+1)) "${script}" | head -c $utilssize > "${working_dir}"/utils.tar
tar -C "${working_dir}" -xf "${working_dir}"/utils.tar
rm "${working_dir}"/utils.tar

export LD_LIBRARY_PATH="${LD_LIBRARY_PATH}:${working_dir}/utils"
sfuse="${working_dir}"/utils/squashfuse
bwrap="${working_dir}"/utils/bwrap

chmod +x "${sfuse}"
chmod +x "${bwrap}"

run_bwrap () {
	if [ -n "$DISABLE_NET" ]; then
		echo "Network is disabled"

		net="--unshare-net"
	fi

	if [ -n "$SANDBOX" ]; then
		echo "Filesystem sandbox is enabled"

		dirs="--tmpfs /home --tmpfs /opt --tmpfs /mnt --dir ${HOME}"

		unshare="--unshare-user-try --unshare-pid --unshare-uts --unshare-cgroup-try \
				--hostname Conty"
	else
		dirs="--bind /home /home --bind-try /mnt /mnt --bind-try /opt /opt --bind-try /media /media"
	fi

	if [ -n "$BIND" ]; then
		echo "Binded items: ${BIND}"

		for i in ${BIND}; do
			bind="${bind} --bind ${i} ${i}"
		done

		dirs="${dirs} ${bind}"
	fi

	echo

	"${bwrap}" --ro-bind "${working_dir}"/mnt / \
			--dev-bind /dev /dev \
			--ro-bind /sys /sys \
			--bind /run /run \
			--bind /var /var \
			--bind /tmp /tmp \
			--ro-bind-try /etc/resolv.conf /etc/resolv.conf \
			--ro-bind-try /etc/hosts /etc/hosts \
			--ro-bind-try /etc/nsswitch.conf /etc/nsswitch.conf \
			--proc /proc \
			--ro-bind-try /usr/local /usr/local \
			${dirs} ${net} \
			--setenv PATH "/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:/usr/lib/jvm/default/bin:${PATH}" \
			"$@"
}

# Mount boostrap image
mkdir -p "${working_dir}"/mnt
"${fmount}" -u "${working_dir}"/mnt 2>/dev/null || umount "${working_dir}"/mnt 2>/dev/null

"${sfuse}" -o offset="${offset}" "${script}" "${working_dir}"/mnt
if [ $? = 0 ]; then
	echo "Running Conty"

	if [ -n "${AUTOSTART}" ]; then
		autostart="${AUTOSTART}"
	elif [ -L "${script_literal}" ]; then
		if [ -f "${working_dir}"/mnt/usr/bin/"${script_name}" ]; then
			autostart="${script_name}"
		fi
	fi

	if [ -n "${autostart}" ]; then
		run_bwrap "${autostart}" "$@" ${AUTOARGS}
	else
		run_bwrap "$@" ${AUTOARGS}
	fi

	"${fmount}" -uz "${working_dir}"/mnt 2>/dev/null || umount --lazy "${working_dir}"/mnt 2>/dev/null
else
	echo "Mounting the squashfs image failed!"

	exit 1
fi

sleep 2
rm -rf "${working_dir}"

exit
