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

# MD5 of the last 1 MB of the script
script_md5="$(tail -c 1000000 "${script}" | md5sum | head -c 7)"

script_id="${RANDOM}"

# Working directory where the utils will be extracted
# And where the squashfs image will be mounted
# The default path is /tmp/scriptname_username_md5
if  [ -z "${BASE_DIR}" ]; then
	export working_dir=/tmp/"$(basename "${script}")"_"${USER}"_"${script_md5}"
else
	export working_dir="${BASE_DIR}"/"$(basename "${script}")"_"${USER}"_"${script_md5}"
fi

mount_point="${working_dir}"/mnt

# It's important to set correct sizes below, otherwise there will be
# a problem with mounting the squashfs image due to an incorrectly calculated offset.

# The size of this script
scriptsize=18029

# The size of the utils.tar archive
# utils.tar contains bwrap and squashfuse binaries
utilssize=1515520

# Offset where the squashfs image is stored
offset=$((scriptsize+utilssize))

if [ "$1" = "--help" ] || [ "$1" = "-h" ] || ([ -z "$1" ] && [ -z "${AUTOSTART}" ] && [ ! -L "${script_literal}" ]); then
	echo "Usage: ./conty.sh command command_arguments"
	echo
	echo "Arguments:"
	echo
	echo -e "-e \tExtract the squashfs image"
	echo -e "-o \tShow the squashfs image offset"
	echo -e "-u \tUpdate all packages inside the container"
	echo -e "\tThis will update all packages inside the container and will rebuild"
	echo -e "\tthe squashfs image. This may take quite a lot of time, depending"
	echo -e "\ton your hardware and an internet speed. Additional disk space"
	echo -e "\t(about 5x the size of the current file) is needed during"
	echo -e "\tthe update process."
	echo -e "\tIf you want to install additional packages, specify them as additional"
	echo -e "\targuments. For example: ./conty.sh -u pkgname1 pkgname2"
	echo -e "\tIn this case Conty will update all packages and will additionally"
	echo -e "\tinstall specified packages."
	echo -e "-U \tThe same as -u but will also update the init script (conty-start.sh)"
	echo -e "\tand the integrated utils directly from the GitHub repo."
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
	echo "no directories will be available at all and a fake temporary HOME"
	echo "directory will be used."
	echo
	echo "If the script is a symlink to itself but with a different name,"
	echo "then the symlinked script will automatically run a program according"
	echo "to its name. For instance, if the script is a symlink with the name \"wine\","
	echo "then it will automatically run wine during launch. This is an alternative"
	echo "to the AUTOSTART variable, but the variable has a higher priority."

	exit
elif [ "$1" = "-e" ]; then
	if command -v unsquashfs 1>/dev/null; then
		unsquashfs -o $offset -user-xattrs -d "$(basename "${script}")"_files "${script}"
	else
		echo "To extract the image install squashfs-tools."
	fi

	exit
elif [ "$1" = "-o" ]; then
	echo $offset

	exit
elif [ "$1" = "-u" ] || [ "$1" = "-U" ]; then
	OLD_PWD="${PWD}"

	# Check if current directory is writable
	# And if it's not, use ~/.local/share/Conty as a working directory
	if ! touch test_rw 2>/dev/null; then
		update_temp_dir="${HOME}"/.local/share/Conty/conty_update_temp
	else
		update_temp_dir="${OLD_PWD}"/conty_update_temp
	fi
	rm -f test_rw

	# Remove conty_update_temp directory if it already exists
	chmod -R 700 "${update_temp_dir}" 2>/dev/null
	rm -rf "${update_temp_dir}"

	mkdir -p "${update_temp_dir}"
	cd "${update_temp_dir}" || exit 1

	# Since Conty is used here to update itself, it's necessary to disable
	# SANDBOX and DISABLE_NET (if they are enabled) for this to work properly
	unset DISABLE_NET
	unset SANDBOX

	# Extract the squashfs image
	clear
	echo "Extracting the squashfs image"
	bash "${script}" unsquashfs -o $offset -user-xattrs -d sqfs "${script}"

	# Download or extract the utils.tar and the init script depending
	# on what command line argument is used (-u or -U)
	clear
	if [ "$1" = "-U" ] && command -v wget 1>/dev/null; then
		echo "Downloading the init script and the utils"
		wget -q --show-progress "https://github.com/Kron4ek/Conty/raw/master/conty-start.sh"
		wget -q --show-progress "https://github.com/Kron4ek/Conty/raw/master/utils.tar"
	fi

	if [ ! -s conty-start.sh ] || [ ! -s utils.tar ]; then
		echo "Extracting the init script and the integrated utils"
		tail -c +$((scriptsize+1)) "${script}" | head -c $utilssize > utils.tar
		head -c $scriptsize "${script}" > conty-start.sh
	fi

	# Check if there are additional arguments passed
	shift
	if [ -n "$1" ]; then
		export packagelist="$@"
	fi

	# Generate a script to perform inside Conty
	# It updates Arch mirrorlist
	# Updates keyrings
	# Updates all installed packages
	# Installs additional packages (if requested)
	# Clears package cache
	cat <<EOF > container-update.sh
reflector --protocol https --score 5 --sort rate --save /etc/pacman.d/mirrorlist
fakeroot -- pacman -q -Syy 2>/dev/null
yes | fakeroot -- pacman -q -S archlinux-keyring 2>/dev/null
yes | fakeroot -- pacman -q -S chaotic-keyring 2>/dev/null
rm -rf /etc/pacman.d/gnupg
fakeroot -- pacman-key --init
fakeroot -- pacman-key --populate archlinux
fakeroot -- pacman-key --populate chaotic
yes | fakeroot -- pacman -q --overwrite "*" -Su 2>/dev/null
yes | fakeroot -- pacman -q -S ${packagelist} 2>/dev/null
rm -f /var/cache/pacman/pkg/*
update-ca-trust
EOF

	bind_items="--bind sqfs/var /var --bind sqfs/etc /etc --bind sqfs/usr /usr \
          --ro-bind-try /etc/resolv.conf /etc/resolv.conf \
          --ro-bind-try /etc/nsswitch.conf /etc/nsswitch.conf \
          --ro-bind-try /etc/hosts /etc/hosts"

	# Execute the previously generated script
	clear
	echo "Updating and installing packages"
	bash "${script}" ${bind_items} bash container-update.sh

	# Create a squashfs image
	clear
	echo "Creating a squashfs image"
	bash "${script}" mksquashfs sqfs image -b 256K -comp zstd -Xcompression-level 14

	# Combine into a single executable
	clear
	echo "Combining everything into a single executable"
	cat conty-start.sh utils.tar image > conty_updated.sh
	chmod +x conty_updated.sh

	mv "${script}" "${script}".old
	mv conty_updated.sh "${script}" || \
	mv conty_updated.sh "${OLD_PWD}" || \
	mv conty_updated.sh "${HOME}"

	chmod -R 700 sqfs 2>/dev/null
	rm -rf "${update_temp_dir}"

	clear
	echo "Conty has been updated!"

	exit
fi

# Check if FUSE2 is installed when SUDO_MOUNT is not enabled
if [ -z "${SUDO_MOUNT}" ] && ! command -v fusermount 1>/dev/null; then
	echo "Please install fuse2 and run the script again!"
	exit 1
fi

# Extract utils.tar
mkdir -p "${working_dir}"

if [ -z "${USE_SYS_UTILS}" ]; then
	mount_tool="${working_dir}"/utils/squashfuse
	bwrap="${working_dir}"/utils/bwrap

	if [ ! -f "${mount_tool}" ] || [ ! -f "${bwrap}" ]; then
		tail -c +$((scriptsize+1)) "${script}" | head -c $utilssize > "${working_dir}"/utils.tar
		tar -C "${working_dir}" -xf "${working_dir}"/utils.tar
		rm "${working_dir}"/utils.tar

		chmod +x "${mount_tool}"
		chmod +x "${bwrap}"
	fi

	export LD_LIBRARY_PATH="${working_dir}/utils:${LD_LIBRARY_PATH}"
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

	mount_tool=squashfuse
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
			--bind-try /run/user /run/user --bind-try /run/dbus /run/dbus \
			--tmpfs /tmp --ro-bind-try /tmp/.X11-unix /tmp/.X11-unix"

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
		echo "Bound items: ${BIND}"

		for i in ${BIND}; do
			bind="${bind} --bind ${i} ${i}"
		done

		dirs="${dirs} ${bind}"
	fi

	echo

	"${bwrap}" --ro-bind "${mount_point}" / \
			--dev-bind /dev /dev \
			--ro-bind /sys /sys \
			--bind-try /tmp /tmp \
			--proc /proc \
			--ro-bind-try /etc/resolv.conf /etc/resolv.conf \
			--ro-bind-try /etc/hosts /etc/hosts \
			--ro-bind-try /etc/nsswitch.conf /etc/nsswitch.conf \
			--ro-bind-try /etc/passwd /etc/passwd \
			--ro-bind-try /etc/group /etc/group \
			--ro-bind-try /etc/machine-id /etc/machine-id \
			--ro-bind-try /etc/asound.conf /etc/asound.conf \
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
			nvidia_version_inside="$(basename "${mount_point}"/usr/lib/libGLX_nvidia.so.*.* | tail -c +18)"

			if [ "$(cat "${nvidia_drivers_dir}"/current_version.txt 2>/dev/null)" != "${nvidia_version}" ] \
			   && [ "${nvidia_version}" != "${nvidia_version_inside}" ]; then
				echo "Nvidia driver version mismatch detected, trying to fix"

				OLD_PWD="${PWD}"

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

				cd "${OLD_PWD}"
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
					if [ -f "${mount_point}"/usr/lib/${lib}.${nvidia_version_inside} ]; then
						nvidia_driver_bind="${nvidia_driver_bind} \
						--ro-bind-try ${nvidia_drivers_dir}/nvidia-driver/${lib}.${nvidia_version} \
						/usr/lib/${lib}.${nvidia_version_inside}"
					fi

					if [ -f "${mount_point}"/usr/lib32/${lib}.${nvidia_version_inside} ]; then
						nvidia_driver_bind="${nvidia_driver_bind} \
						--ro-bind-try ${nvidia_drivers_dir}/nvidia-driver/32/${lib}.${nvidia_version} \
						/usr/lib32/${lib}.${nvidia_version_inside}"
					fi

					if [ -f "${mount_point}"/usr/lib/nvidia/xorg/libglxserver_nvidia.so.${nvidia_version_inside} ]; then
						nvidia_driver_bind="${nvidia_driver_bind} \
						--ro-bind-try ${nvidia_drivers_dir}/nvidia-driver/libglxserver_nvidia.so.${nvidia_version} \
						/usr/lib/nvidia/xorg/libglxserver_nvidia.so.${nvidia_version_inside}"
					fi

					if [ -f "${mount_point}"/usr/lib/vdpau/libvdpau_nvidia.so.${nvidia_version_inside} ]; then
						nvidia_driver_bind="${nvidia_driver_bind} \
						--ro-bind-try ${nvidia_drivers_dir}/nvidia-driver/libvdpau_nvidia.so.${nvidia_version} \
						/usr/lib/vdpau/libvdpau_nvidia.so.${nvidia_version_inside}"
					fi

					if [ -f "${mount_point}"/usr/lib32/vdpau/libvdpau_nvidia.so.${nvidia_version_inside} ]; then
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
	rm -f "${working_dir}"/running_"${script_id}"

	if [ ! "$(ls "${working_dir}"/running_* 2>/dev/null)" ]; then
		fusermount -uz "${mount_point}" 2>/dev/null || \
		${use_sudo} umount --lazy "${mount_point}" 2>/dev/null

		rm -rf "${working_dir}"
	fi

	exit
}

trap 'trap_exit' EXIT

if [ -n "${SUDO_MOUNT}" ]; then
	echo "Using regular mount command (sudo mount) instead of squashfuse"

	mount_tool=mount
	use_sudo=sudo
fi

# Mount the squashfs image
mkdir -p "${mount_point}"

if [ "$(ls "${mount_point}" 2>/dev/null)" ] || \
	${use_sudo} "${mount_tool}" -o offset="${offset}",ro "${script}" "${mount_point}" ; then
	echo 1 > "${working_dir}"/running_"${script_id}"

	echo "Running Conty"

	if [ -n "${NVIDIA_FIX}" ]; then
		bind_nvidia_driver
	fi

	if [ -n "${AUTOSTART}" ]; then
		autostart="${AUTOSTART}"
	elif [ -L "${script_literal}" ]; then
		if [ -f "${mount_point}"/usr/bin/"${script_name}" ]; then
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
