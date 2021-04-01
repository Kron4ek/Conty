#!/usr/bin/env bash

## Dependencies: bash fuse2 tar coreutils

# Prevent launching as root
if [ -z "$ALLOW_ROOT" ]; then
	if [ $EUID = 0 ]; then
		echo "Do not run this script as root!"
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
# The default path is /tmp/scriptname_username_randomnumber
export working_dir=/tmp/"$(basename "${script}")"_"${USER}"_${RANDOM}

# It's important to set correct sizes below, otherwise there will be
# a problem with mounting the squashfs image due to an incorrectly calculated offset.

# The size of this script
scriptsize=13213

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
	echo -e "HOME_DIR \tSets HOME directory to a custom location."
	echo -e "\t\tCan be used only together with SANDBOX enabled."
	echo -e "\t\tFor example, HOME_DIR=\"/home/username/custom_home\""
	echo -e "USE_SYS_UTILS \tMakes the script to use squashfuse and bwrap"
	echo -e "\t\tinstalled on the system instead of the builtin ones."
	echo -e "\t\tIf you want to enable this variable, please make sure"
	echo -e "\t\tthat bubblewrap and squashfuse are installed on your system"
	echo -e "\t\tand that squashfuse supports the compression algo the image"
	echo -e "\t\twas built with."
	echo -e "NVIDIA_FIX \tAutomatically download and bind the required Nvidia"
	echo -e "\t\tlibraries if the kernel module version in the system differs"
	echo -e "\t\tfrom the Nvidia libraries version inside the container."
	echo -e "\t\tThis should fix the graphics acceleration problems on Nvidia."
	echo -e "SUDO_MOUNT \tMakes the script to mount the squashfs image by using"
	echo -e "\t\tthe regular mount command instead of squashfuse. In this"
	echo -e "\t\tcase root rights will be requested (via sudo) when mounting"
	echo -e "\t\tand unmounting."
	echo -e "BASE_DIR \tSets custom directory where Conty will extract"
	echo -e "\t\tits builtin utilities and mount the squashfs image."
	echo -e "\t\tThe default location is /tmp."
	echo
	echo "If you enable SANDBOX but don't set BIND or HOME_DIR, then"
	echo "no directories will be available at all. And a fake temporary HOME"
	echo "directory will be created inside the container."
	echo
	echo "Also, if the script is a symlink to itself but with different name,"
	echo "then the symlinked script will automatically run a program according"
	echo "to its name. For instance, if the script is a symlink with the name \"wine\","
	echo "then it will automatically run wine during launch. This is an alternative"
	echo "to the AUTOSTART variable, but the variable has a higher priority."

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
	echo "Please install fuse2 and run the script again!"
	exit 1
fi

if  [ -n "${BASE_DIR}" ]; then
	echo "Using custom BASE_DIR: ${BASE_DIR}"

	export working_dir="${BASE_DIR}"/"$(basename "${script}")"_"${USER}"_${RANDOM}
fi

# Extract utils.tar
mkdir -p "${working_dir}"

if [ -z "${USE_SYS_UTILS}" ]; then
	tail -c +$((scriptsize+1)) "${script}" | head -c $utilssize > "${working_dir}"/utils.tar
	tar -C "${working_dir}" -xf "${working_dir}"/utils.tar
	rm "${working_dir}"/utils.tar

	export LD_LIBRARY_PATH="${LD_LIBRARY_PATH}:${working_dir}/utils"
	sfuse="${working_dir}"/utils/squashfuse
	bwrap="${working_dir}"/utils/bwrap

	chmod +x "${sfuse}"
	chmod +x "${bwrap}"
else
	if ! command -v bwrap 1>/dev/null; then
		echo "USE_SYS_UTILS is enabled, but bwrap is not installed!"
		echo "Please install it and run the script again."

		exit 1
	fi

	if ! command -v squashfuse 1>/dev/null && [ -z "${SUDO_MOUNT}" ]; then
		echo "USE_SYS_UTILS is enabled, but squshfuse is not installed!"
		echo "Please install it and run the script again."
		echo "Or enable SUDO_MOUNT to mount the image using the regular"
		echo "mount command instead of squashfuse."

		exit 1
	fi

	echo "Using system squashfuse and bwrap"

	sfuse=squashfuse
	bwrap=bwrap
fi

run_bwrap () {
	if [ -n "$DISABLE_NET" ]; then
		echo "Network is disabled"

		net="--unshare-net"
	fi

	if [ -n "$SANDBOX" ]; then
		echo "Filesystem sandbox is enabled"

		dirs="--tmpfs /home --dir ${HOME} --tmpfs /opt --tmpfs /mnt \
			--tmpfs /media --tmpfs /var --tmpfs /run --symlink /run /var/run \
			--bind-try /run/user /run/user --bind-try /run/dbus /run/dbus"

		if [ -n "${HOME_DIR}" ]; then
			echo "Set HOME to ${HOME_DIR}"
			dirs="${dirs} --bind ${HOME_DIR} ${HOME}"
		fi

#		unshare="--unshare-user-try --unshare-pid --unshare-uts --unshare-cgroup-try \
#				--hostname Conty"
	else
		dirs="--bind-try /home /home --bind-try /mnt /mnt --bind-try /opt /opt \
			--bind-try /media /media --bind-try /run /run --bind-try /var /var"
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
			--bind-try /tmp /tmp \
			--proc /proc \
			--ro-bind-try /etc/resolv.conf /etc/resolv.conf \
			--ro-bind-try /etc/hosts /etc/hosts \
			--ro-bind-try /etc/nsswitch.conf /etc/nsswitch.conf \
			--ro-bind-try /etc/passwd /etc/passwd \
			--ro-bind-try /etc/group /etc/group \
			--ro-bind-try /usr/local /usr/local \
			${dirs} \
			${net} \
			${nvidia_driver_bind} \
			--setenv PATH "${CUSTOM_PATH}" \
			"$@"
}

# Function that checks if the Nvidia kernel module loaded in the
# system matches the version of the Nvidia libraries inside the container
# and downloads corresponding Nvidia libs from the official site if they
# are not the same. Also binds the downloaded libraries to the container.
#
# This is absolutely necessary for Nvidia GPUs, otherwise graphics
# acceleration will not work.

bind_nvidia_driver () {
	# Path to store downloaded Nvidia drivers
	nvidia_drivers_dir="${HOME}"/.local/share/Conty/nvidia-drivers

	# Check if the Nvidia module is loaded
	# If it's loaded, then likely Nvidia GPU is being used
	if lsmod | grep nvidia 1>/dev/null || nvidia-smi 1>/dev/null; then
		if nvidia-smi 1>/dev/null; then
			nvidia_version="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader)"
		elif modinfo nvidia &>/dev/null; then
			nvidia_version="$(modinfo -F version nvidia 2>/dev/null)"
		else
			if [ -d /usr/lib/x86_64-linux-gnu ]; then
				nvidia_version="$(basename /usr/lib/x86_64-linux-gnu/libGLX_nvidia.so.*.* | tail -c +18)"
			else
				nvidia_version="$(basename /usr/lib/libGLX_nvidia.so.*.* | tail -c +18)"
			fi
		fi

		# Check if the kernel module version is different from the
		# libraries version inside the container
		if [ -n "${nvidia_version}" ]; then
			nvidia_version_inside="$(basename "${working_dir}"/mnt/usr/lib/libGLX_nvidia.so.*.* | tail -c +18)"

			if [ "$(cat "${nvidia_drivers_dir}"/current_version.txt 2>/dev/null)" != "${nvidia_version}" ] \
			   && [ "${nvidia_version}" != "${nvidia_version_inside}" ]; then
				echo "Nvidia driver version mismatch detected, trying to fix"

				mkdir -p "${nvidia_drivers_dir}"
				cd "${nvidia_drivers_dir}"

				rm -rf nvidia-driver
				rm -f nvidia.run

				echo "Downloading Nvidia ${nvidia_version}, please wait"

				# Try to download from the default Nvidia url
				driver_url="https://us.download.nvidia.com/XFree86/Linux-x86_64/${nvidia_version}/NVIDIA-Linux-x86_64-${nvidia_version}.run"
				wget -q --show-progress "${driver_url}" -O nvidia.run

				# If the previous download failed, get url from flathub
				if [ ! -s nvidia.run ]; then
					rm -f nvidia.run
					driver_url="https:$(wget -q "https://raw.githubusercontent.com/flathub/org.freedesktop.Platform.GL.nvidia/master/data/nvidia-${nvidia_version}-i386.data" \
							-O - | cut -d ':' -f 6)"

					wget -q --show-progress "${driver_url}" -O nvidia.run
				fi

				if [ -s nvidia.run ]; then
					chmod +x nvidia.run
					echo "Unpacking nvidia.run..."
					./nvidia.run -x &>/dev/null
					rm nvidia.run
					mv NVIDIA-Linux-x86_64-${nvidia_version} nvidia-driver
					echo ${nvidia_version} > current_version.txt
				fi

				cd "${PWD}"
			fi

			# Bind the downloaded Nvidia libs to the container
			if [ -d "${nvidia_drivers_dir}"/nvidia-driver ]; then
				nvidia_libs_list="libcuda.so libEGL_nvidia.so libGLESv1_CM_nvidia.so \
				libGLESv2_nvidia.so libGLX_nvidia.so libnvcuvid.so libnvidia-cbl.so \
				libnvidia-cfg.so libnvidia-eglcore.so libnvidia-encode.so libnvidia-fbc.so \
				libnvidia-glcore.so libnvidia-glsi.so libnvidia-glvkspirv.so libnvidia-ifr.so \
				libnvidia-ml.so libnvidia-ngx.so libnvidia-opticalflow.so libnvidia-ptxjitcompiler.so \
				libnvidia-rtcore.so libnvidia-tls.so libnvoptix.so"

				for lib in ${nvidia_libs_list}; do
					if [ -f "${working_dir}"/mnt/usr/lib/${lib}.${nvidia_version_inside} ]; then
						nvidia_driver_bind="${nvidia_driver_bind} \
						--ro-bind-try ${nvidia_drivers_dir}/nvidia-driver/${lib}.${nvidia_version} \
						/usr/lib/${lib}.${nvidia_version_inside}"
					fi

					if [ -f "${working_dir}"/mnt/usr/lib32/${lib}.${nvidia_version_inside} ]; then
						nvidia_driver_bind="${nvidia_driver_bind} \
						--ro-bind-try ${nvidia_drivers_dir}/nvidia-driver/32/${lib}.${nvidia_version} \
						/usr/lib32/${lib}.${nvidia_version_inside}"
					fi

					if [ -f "${working_dir}"/mnt/usr/lib/nvidia/xorg/libglxserver_nvidia.so.${nvidia_version_inside} ]; then
						nvidia_driver_bind="${nvidia_driver_bind} \
						--ro-bind-try ${nvidia_drivers_dir}/nvidia-driver/libglxserver_nvidia.so.${nvidia_version} \
						/usr/lib/nvidia/xorg/libglxserver_nvidia.so.${nvidia_version_inside}"
					fi

					if [ -f "${working_dir}"/mnt/usr/lib/vdpau/libvdpau_nvidia.so.${nvidia_version_inside} ]; then
						nvidia_driver_bind="${nvidia_driver_bind} \
						--ro-bind-try ${nvidia_drivers_dir}/nvidia-driver/libvdpau_nvidia.so.${nvidia_version} \
						/usr/lib/vdpau/libvdpau_nvidia.so.${nvidia_version_inside}"
					fi

					if [ -f "${working_dir}"/mnt/usr/lib32/vdpau/libvdpau_nvidia.so.${nvidia_version_inside} ]; then
						nvidia_driver_bind="${nvidia_driver_bind} \
						--ro-bind-try ${nvidia_drivers_dir}/nvidia-driver/32/libvdpau_nvidia.so.${nvidia_version} \
						/usr/lib32/vdpau/libvdpau_nvidia.so.${nvidia_version_inside}"
					fi
				done
			fi
		fi
	fi
}

trap_exit () {
	"${fmount}" -uz "${working_dir}"/mnt 2>/dev/null || \
	${sudo_umount} umount --lazy "${working_dir}"/mnt 2>/dev/null
	sleep 1
	rm -rf "${working_dir}"
	exit
}

trap 'trap_exit' EXIT

if [ -n "${SUDO_MOUNT}" ]; then
	echo "Using regular mount command (sudo mount) instead of squashfuse"

	sfuse=mount
	sudo_mount=sudo
	sudo_umount=sudo
fi

# Mount boostrap image
mkdir -p "${working_dir}"/mnt

if ${sudo_mount} "${sfuse}" -o offset="${offset}" "${script}" "${working_dir}"/mnt ; then
	echo "Running Conty"

	if [ -n "${NVIDIA_FIX}" ]; then
		bind_nvidia_driver
	fi

	if [ -n "${AUTOSTART}" ]; then
		autostart="${AUTOSTART}"
	elif [ -L "${script_literal}" ]; then
		if [ -f "${working_dir}"/mnt/usr/bin/"${script_name}" ]; then
			autostart="${script_name}"
		fi
	fi

	if [ -n "${AUTOARGS}" ]; then
		echo "Automatically append arguments: ${AUTOARGS}"
	fi

	if [ -n "${autostart}" ]; then
		export CUSTOM_PATH="/bin:/sbin:/usr/bin:/usr/sbin:/usr/lib/jvm/default/bin"

		echo "Autostarting ${autostart}"
		run_bwrap "${autostart}" "$@" ${AUTOARGS}
	else
		export CUSTOM_PATH="/bin:/sbin:/usr/bin:/usr/sbin:/usr/lib/jvm/default/bin:/usr/local/bin:/usr/local/sbin:${PATH}"

		run_bwrap "$@" ${AUTOARGS}
	fi
else
	echo "Mounting the squashfs image failed!"

	exit 1
fi

exit
