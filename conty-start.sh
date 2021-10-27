#!/usr/bin/env bash

## Dependencies: bash gzip fuse2 (or fuse3) tar coreutils

# Prevent launching as root
if [ $EUID = 0 ] && [ -z "$ALLOW_ROOT" ]; then
	echo "Do not run this script as root!"
	echo
	echo "If you really need to run it as root and you know what you are doing,"
	echo "set ALLOW_ROOT environment variable."

	exit 1
fi

script_version="1.18"

# Full path to the script
script_literal="${BASH_SOURCE[0]}"
script_name="$(basename "${script_literal}")"
script="$(readlink -f "${script_literal}")"

# MD5 of the last 1 MB of the file
script_md5="$(tail -c 1000000 "${script}" | md5sum | head -c 7)"

script_id="${RANDOM}"

# Working directory where the utils will be extracted
# And where the image will be mounted
# The default path is /tmp/scriptname_username_scriptmd5
# And if /tmp is mounted with noexec, the default path
# is ~/.local/share/Conty/scriptname_username_scriptmd5
conty_dir_name="$(basename "${script}")"_"${USER}"_"${script_md5}"

if  [ -z "${BASE_DIR}" ]; then
	export working_dir=/tmp/"${conty_dir_name}"
else
	export working_dir="${BASE_DIR}"/"${conty_dir_name}"
fi

mount_point="${working_dir}"/mnt

# It's important to set correct sizes below, otherwise there will be
# a problem with mounting the image due to an incorrectly calculated offset.

# The size of this script
scriptsize=29829

# The size of the utils archive
utilssize=2928770

# Offset where the image is stored
offset=$((scriptsize+utilssize))

# Set to 1 if you are using an image compressed with dwarfs instead of squashfs
#
# Also, don't forget to change the utilssize variable to the size of
# utils_dwarfs.tar.gz
dwarfs_image=0

dwarfs_cache_size="128M"
dwarfs_num_workers="2"

# These arguments are used to rebuild the image when using the self-update function
squashfs_comp_arguments="-b 256K -comp zstd -Xcompression-level 14"
dwarfs_comp_arguments="-l7 -C zstd:level=19 --metadata-compression null \
					-S 22 -B 3"

if [ "$1" = "--help" ] || [ "$1" = "-h" ] || ([ -z "$1" ] && [ ! -L "${script_literal}" ]); then
	echo "Usage: ./conty.sh command command_arguments"
	echo
	echo "Arguments:"
	echo
	echo -e "-v \tShow version of this script"
	echo -e "-V \tShow version of the image"
	echo -e "-e \tExtract the image"
	echo -e "-o \tShow the image offset"
	echo -e "-l \tShow a list of all installed packages"
	echo -e "-m \tMount/unmount the image"
	echo -e "\tThe image will be mounted if it's not mounted, and unmounted otherwise."
	echo -e "\tMount point can be changed with the BASE_DIR env variable"
	echo -e "\t(the default is /tmp)."
	echo -e "-u \tUpdate all packages inside the container"
	echo -e "\tThis will update all packages inside the container and will rebuild"
	echo -e "\tthe image. This may take quite a lot of time, depending"
	echo -e "\ton your hardware and internet speed. Additional disk space"
	echo -e "\t(about 6x the size of the current file) is needed during"
	echo -e "\tthe update process."
	echo -e "-U \tThe same as -u but will also update the init script (conty-start.sh)"
	echo -e "\tand the integrated utils. This option may break Conty in some cases,"
	echo -e "\tuse with caution."
	echo
	echo "Arguments that don't match any of the above will be passed directly to"
	echo "bubblewrap. So all bubblewrap arguments are supported as well."
	echo
	echo "Environment variables:"
	echo
	echo -e "DISABLE_NET \tDisables network access"
	echo -e "SANDBOX \tEnables sandbox"
	echo -e "SANDBOX_LEVEL \tControls the strictness of the sandbox"
	echo -e "\t\tAvailable levels are 1-3. The default is 1."
	echo -e "\t\tLevel 1 isolates all user files."
	echo -e "\t\tLevel 2 isolates all user files, disables dbus and hides"
	echo -e "\t\tall running processes."
	echo -e "\t\tLevel 3 does the same as the level 2, but additionally"
	echo -e "\t\tdisables network access and isolates X11 server with Xephyr."
	echo -e "XEPHYR_SIZE \tSets the size of the Xephyr window. The default is 800x600."
	echo -e "BIND \t\tMounts directories and files (separated by space) from the"
	echo -e "\t\thost system to the container. All specified items must exist."
	echo -e "\t\tFor example, BIND=\"/home/username/.config /etc/pacman.conf\""
	echo -e "\t\tThis is mainly useful for allowing access to specific"
	echo -e "\t\tdirs/files when SANDBOX is enabled."
	echo -e "BIND_RO \tThe same as BIND but mounts as read-only."
	echo -e "HOME_DIR \tSets the HOME directory to a custom location."
	echo -e "\t\tFor example, HOME_DIR=\"/home/username/custom_home\""
	echo -e "\t\tIf you set this, HOME inside the container will still appear"
	echo -e "\t\tas /home/username, but actually a custom directory will be"
	echo -e "\t\tused for it."
	echo -e "USE_SYS_UTILS \tMakes the script to use squashfuse/dwarfs and bwrap"
	echo -e "\t\tinstalled on the system instead of the builtin ones."
	echo -e "NVIDIA_FIX \tFixes graphics acceleration problems on Nvidia GPUs with the"
	echo -e "\t\tproprietary driver. This is not needed for the free/oss Nouveau"
	echo -e "\t\tdriver. Enable this only if you have graphics acceleration"
	echo -e "\t\tproblems on Nvidia."
	echo -e "SUDO_MOUNT \tMakes the script to mount the squashfs image by using"
	echo -e "\t\tthe regular mount command instead of squashfuse. In this"
	echo -e "\t\tcase root rights will be requested (via sudo) when mounting"
	echo -e "\t\tand unmounting. This doesn't work for dwarfs-compressed images."
	echo -e "BASE_DIR \tSets a custom directory where Conty will extract"
	echo -e "\t\tits builtin utilities and mount the image."
	echo -e "\t\tThe default location is /tmp."
	echo -e "QUIET_MODE \tDisables all non-error Conty messages."
	echo -e "\t\tDoesn't affect the output of applications."
	echo
	echo "Additional notes:"
	echo
	echo "If you enable SANDBOX but don't set BIND or HOME_DIR, then no system"
	echo "directories/files will be available at all inside the container and a fake"
	echo "temporary HOME directory will be used."
	echo
	echo "Which SANDBOX_LEVEL to use? Well, if you just want to isolate your files from"
	echo "an application, then the level 1 (default) is enough. However, if an"
	echo "application doesn't strictly require dbus and doesn't need to communicate with"
	echo "other processes, then i recommend to use at least the level 2, which"
	echo "is more secure and is better for running untrusted or malicious apps. And"
	echo "for maximum protection use the level 3 (or Wayland + level 2), which protects"
	echo "even against X11 keyloggers. Disabling internet access with DISABLE_NET is also"
	echo "a very good idea if an application does not require constant internet access."
	echo
	echo "If the script is a symlink to itself but with a different name,"
	echo "then the symlinked script will automatically run a program according"
	echo "to its name. For instance, if the script is a symlink with the name \"wine\","
	echo "then it will automatically run wine during launch."
	echo
	echo "Besides updating all packages, you can also remove and install packages using"
	echo "the same -u (or -U) argument. To install packages add them as additional"
	echo "arguments, and to remove packages add a minus sign (-) before their names."
	echo "To install: ./conty.sh -u pkgname1 pkgname2 pkgname3"
	echo "To remove: ./conty.sh -u -pkgname1 -pkgname2 -pkgname3"
	echo "In this case Conty will update all packages and will additionally"
	echo "install and/or remove specified packages."
	exit
elif [ "$1" = "-v" ]; then
	echo "${script_version}"

	exit
elif [ "$1" = "-e" ]; then
	if [ "${dwarfs_image}" = 1 ]; then
		if command -v dwarfsextract 1>/dev/null; then
			mkdir "$(basename "${script}")"_files

			dwarfsextract -i "${script}" -o "$(basename "${script}")"_files -O ${offset}
		else
			echo "To extract the image install dwarfs."
		fi
	else
		if command -v unsquashfs 1>/dev/null; then
			unsquashfs -o ${offset} -user-xattrs -d "$(basename "${script}")"_files "${script}"
		else
			echo "To extract the image install squashfs-tools."
		fi
	fi

	exit
elif [ "$1" = "-o" ]; then
	echo ${offset}

	exit
fi

show_msg () {
	if [ "${QUIET_MODE}" != 1 ]; then
		echo "$@"
	fi
}

exec_test () {
	mkdir -p "${working_dir}"

	exec_test_file="${working_dir}"/exec_test

	rm -f "${exec_test_file}"
	touch "${exec_test_file}"
	chmod +x "${exec_test_file}"

	[ -x "${exec_test_file}" ]
}

launch_wrapper () {
	if [ "$1" = "mount" ]; then
		${use_sudo} "$@"
	elif [ "${USE_SYS_UTILS}" = 1 ]; then
		"$@"
	else
		"${working_dir}"/utils/ld-linux-x86-64.so.2 --library-path "${working_dir}"/utils "$@"
	fi
}

# Disable the regular mount command when using a dwarfs-compressed image
# because Linux kernel doesn't support dwarfs directly, only via FUSE
if [ "${dwarfs_image}" = 1 ]; then
	unset SUDO_MOUNT
fi

# Check if FUSE is installed when SUDO_MOUNT is not enabled
if [ "${SUDO_MOUNT}" != 1 ]; then
	if ! command -v fusermount3 1>/dev/null && ! command -v fusermount 1>/dev/null; then
		echo "Please install fuse2 or fuse3 and run the script again."
		exit 1
	fi

	if command -v fusermount3 1>/dev/null; then
		fuse_version=3
	fi
fi

# Set the dwarfs block cache size depending on how much RAM is available
# Also set the number of workers depending on the number of CPU cores
if [ "${dwarfs_image}" = 1 ]; then
	if getconf _PHYS_PAGES &>/dev/null && getconf PAGE_SIZE &>/dev/null; then
		memory_size="$(($(getconf _PHYS_PAGES) * $(getconf PAGE_SIZE) / (1024 * 1024)))"

		if [ "${memory_size}" -ge 23000 ]; then
			dwarfs_cache_size="2048M"
		elif [ "${memory_size}" -ge 15000 ]; then
			dwarfs_cache_size="1024M"
		elif [ "${memory_size}" -ge 7000 ]; then
			dwarfs_cache_size="512M"
		elif [ "${memory_size}" -ge 3000 ]; then
			dwarfs_cache_size="256M"
		elif [ "${memory_size}" -ge 1500 ]; then
			dwarfs_cache_size="128M"
		else
			dwarfs_cache_size="64M"
		fi
	fi

	if getconf _NPROCESSORS_ONLN &>/dev/null; then
		dwarfs_num_workers="$(getconf _NPROCESSORS_ONLN)"

		if [ "${dwarfs_num_workers}" -ge 16 ]; then
			dwarfs_num_workers=16
		fi
	fi
fi

# Extract utils.tar.gz
mkdir -p "${working_dir}"

if [ "${USE_SYS_UTILS}" != 1 ]; then
	# Check if filesystem of the working_dir is mounted without noexec
	if ! exec_test; then
		if [ -z "${BASE_DIR}" ]; then
			export working_dir="${HOME}"/.local/share/Conty/"${conty_dir_name}"
			mount_point="${working_dir}"/mnt
		fi

		if ! exec_test; then
			echo "Seems like /tmp is mounted with noexec or you don't have write access!"
			echo "Please remount it without noexec or set BASE_DIR to a different location."

			exit 1
		fi
	fi

	if ! command -v tar 1>/dev/null || ! command -v gzip 1>/dev/null; then
		echo "Please install tar and gzip and run the script again."
		exit 1
	fi

	if [ "${dwarfs_image}" = 1 ]; then
		mount_tool="${working_dir}"/utils/dwarfs${fuse_version}
	else
		mount_tool="${working_dir}"/utils/squashfuse${fuse_version}
	fi

	bwrap="${working_dir}"/utils/bwrap

	if [ ! -f "${mount_tool}" ] || [ ! -f "${bwrap}" ]; then
		tail -c +$((scriptsize+1)) "${script}" | head -c ${utilssize} | tar -C "${working_dir}" -zxf -

		if [ ! -f "${mount_tool}" ] || [ ! -f "${bwrap}" ]; then
			clear
			echo "The integrated utils were not extracted!"
			echo "Perhaps something is wrong with the integrated utils.tar.gz."

			exit 1
		fi

		chmod +x "${mount_tool}"
		chmod +x "${bwrap}"
	fi
else
	if ! command -v bwrap 1>/dev/null; then
		echo "USE_SYS_UTILS is enabled, but bubblewrap is not installed!"
		echo "Please install it and run the script again."

		exit 1
	fi

	bwrap=bwrap

	if [ "${dwarfs_image}" = 1 ]; then
		if ! command -v dwarfs 1>/dev/null && ! command -v dwarfs2 1>/dev/null; then
			echo "USE_SYS_UTILS is enabled, but dwarfs is not installed!"
			echo "Please install it and run the script again."

			exit 1
		fi

		if command -v dwarfs2 1>/dev/null; then
			mount_tool=dwarfs2
		else
			mount_tool=dwarfs
		fi
	else
		if ! command -v squashfuse 1>/dev/null && [ "${SUDO_MOUNT}" != 1 ]; then
			echo "USE_SYS_UTILS is enabled, but squshfuse is not installed!"
			echo "Please install it and run the script again."
			echo "Or enable SUDO_MOUNT to mount the image using the regular"
			echo "mount command instead of squashfuse."

			exit 1
		fi

		mount_tool=squashfuse
	fi

	show_msg "Using system-wide ${mount_tool} and bwrap"
fi

if [ "${SUDO_MOUNT}" = 1 ]; then
	show_msg "Using regular mount command (sudo mount) instead of squashfuse"

	mount_tool=mount
	use_sudo=sudo
fi

if [ "$1" = "-u" ] || [ "$1" = "-U" ]; then
	OLD_PWD="${PWD}"

	# Check if the current directory is writable
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

	tail -c +$((scriptsize+1)) "${script}" | head -c ${utilssize} | tar -C "${update_temp_dir}" -zxf -

	if [ "${dwarfs_image}" = 1 ]; then
		chmod +x utils/dwarfsextract 2>/dev/null
		chmod +x utils/mkdwarfs 2>/dev/null

		if [ ! -x "utils/dwarfsextract" ] || [ ! -x "utils/mkdwarfs" ]; then
			missing_utils="dwarfsextract and/or mkdwarfs"
		fi
	else
		chmod +x utils/unsquashfs 2>/dev/null
		chmod +x utils/mksquashfs 2>/dev/null

		if [ ! -x "utils/unsquashfs" ] || [ ! -x "utils/mksquashfs" ]; then
			missing_utils="unsquashfs and/or mksquashfs"
		fi
	fi

	if [ -n "${missing_utils}" ]; then
		echo "The integrated utils don't contain ${missing_utils}."
		echo "Or your file system is mounted with noexec."
		exit 1
	fi

	tools_wrapper () {
		"${update_temp_dir}"/utils/ld-linux-x86-64.so.2 --library-path "${update_temp_dir}"/utils "$@"
	}

	# Since Conty is used here to update itself, it's necessary to disable
	# some environment variables for this to work properly
	unset NVIDIA_FIX
	unset DISABLE_NET
	unset HOME_DIR
	unset BIND
	unset BIND_RO
	unset SANDBOX_LEVEL

	# Enable SANDBOX
	export SANDBOX=1

	export QUIET_MODE=1

	# Extract the image
	clear
	echo "Extracting the image"
	if [ "${dwarfs_image}" = 1 ]; then
		mkdir sqfs
		tools_wrapper "${update_temp_dir}"/utils/dwarfsextract \
		-i "${script}" -o sqfs -O ${offset} --cache-size "${dwarfs_cache_size}" \
		--num-workers "${dwarfs_num_workers}"
	else
		tools_wrapper "${update_temp_dir}"/utils/unsquashfs \
		-o ${offset} -user-xattrs -d sqfs "${script}"
	fi

	# Download or extract the utils.tar.gz and the init script depending
	# on what command line argument is used (-u or -U)
	clear
	if [ "$1" = "-U" ] && command -v wget 1>/dev/null; then
		if [ "${dwarfs_image}" = 1 ]; then
			utils="utils_dwarfs.tar.gz"
		else
			utils="utils.tar.gz"
		fi

		echo "Downloading the init script and the utils"
		wget -q --show-progress "https://github.com/Kron4ek/Conty/raw/master/conty-start.sh"
		wget -q --show-progress -O utils.tar.gz "https://github.com/Kron4ek/Conty/raw/master/${utils}"
	fi

	if [ ! -s conty-start.sh ] || [ ! -s utils.tar.gz ]; then
		echo "Extracting the init script and the integrated utils"
		tail -c +$((scriptsize+1)) "${script}" | head -c ${utilssize} > utils.tar.gz
		head -c ${scriptsize} "${script}" > conty-start.sh
	fi

	# Check if there are additional arguments passed
	shift
	if [ -n "$1" ]; then
		packagelist="$@"

		# Check which packages to install and which ones to remove
		for i in ${packagelist}; do
			if [ "$(echo "${i}" | head -c 1)" = "-" ]; then
				export pkgsremove="${pkgsremove} $(echo "${i}" | tail -c +2)"
			else
				export pkgsinstall="${pkgsinstall} ${i}"
			fi
		done
	fi

	# Generate a script to perform inside Conty
	# It updates Arch mirrorlist
	# Updates keyrings
	# Updates all installed packages
	# Installs additional packages (if requested)
	# Removes packages (if requested)
	# Clears package cache
	# Updates SSL CA certificates
	# Generates locales
	cat <<EOF > container-update.sh
reflector --protocol https --score 5 --sort rate --save /etc/pacman.d/mirrorlist
fakeroot -- pacman -Syy 2>/dev/null
date -u +"%d-%m-%Y %H:%M (DMY UTC)" > /version
fakeroot -- pacman --noconfirm -S archlinux-keyring 2>/dev/null
fakeroot -- pacman --noconfirm -S chaotic-keyring 2>/dev/null
rm -rf /etc/pacman.d/gnupg
fakeroot -- pacman-key --init
echo "keyserver hkps://keyserver.ubuntu.com" >> /etc/pacman.d/gnupg/gpg.conf
fakeroot -- pacman-key --populate archlinux
fakeroot -- pacman-key --populate chaotic
fakeroot -- pacman --noconfirm --overwrite "*" -Su 2>/dev/null
fakeroot -- pacman --noconfirm -Runs ${pkgsremove} 2>/dev/null
fakeroot -- pacman --noconfirm -S ${pkgsinstall} 2>/dev/null
rm -f /var/cache/pacman/pkg/*
pacman -Qn > /pkglist.x86_64.txt
pacman -Qm >> /pkglist.x86_64.txt
update-ca-trust
locale-gen
EOF

    rm -f sqfs/etc/resolv.conf
    cp /etc/resolv.conf sqfs/etc/resolv.conf
    mkdir -p sqfs/run/shm

	# Execute the previously generated script
	clear
	echo "Updating and installing packages"
	bash "${script}" --bind sqfs / --ro-bind /sys /sys --dev-bind /dev /dev \
				--proc /proc --bind "${update_temp_dir}" "${update_temp_dir}" \
				bash container-update.sh

	# Create an image
	clear
	echo "Creating an image"
	if [ "${dwarfs_image}" = 1 ]; then
		tools_wrapper "${update_temp_dir}"/utils/mkdwarfs \
		-i sqfs -o image ${dwarfs_comp_arguments}
	else
		tools_wrapper "${update_temp_dir}"/utils/mksquashfs \
		sqfs image ${squashfs_comp_arguments}
	fi

	# Combine into a single executable
	clear
	echo "Combining everything into a single executable"
	cat conty-start.sh utils.tar.gz image > conty_updated.sh
	chmod +x conty_updated.sh

	mv -f "${script}" "${script}".old."${script_md5}" 2>/dev/null
	mv -f conty_updated.sh "${script}" 2>/dev/null || move_failed=1

	if [ "${move_failed}" = 1 ]; then
		mv -f conty_updated.sh "${OLD_PWD}" 2>/dev/null || \
		mv -f conty_updated.sh "${HOME}" 2>/dev/null
	fi

	chmod -R 700 sqfs 2>/dev/null
	rm -rf "${update_temp_dir}"

	clear
	echo "Conty has been updated!"

	if [ "${move_failed}" = 1 ]; then
		echo
		echo "Replacing ${script} with the new one failed!"
		echo
		echo "You can find conty_updated.sh in the current working"
		echo "directory or in your HOME."
	fi

	exit
fi

run_bwrap () {
	unset sandbox_params
	unset unshare_net
	unset custom_home
	unset bind_items

	if [ -n "${WAYLAND_DISPLAY}" ]; then
		wayland_socket="${WAYLAND_DISPLAY}"
	else
		wayland_socket="wayland-0"
	fi

	if [ "${SANDBOX}" = 1 ]; then
		sandbox_params="--tmpfs /home \
                        --dir ${HOME} \
                        --tmpfs /opt \
                        --tmpfs /mnt \
                        --tmpfs /media \
                        --tmpfs /var \
                        --tmpfs /run \
                        --symlink /run /var/run \
                        --tmpfs /tmp \
                        --new-session"

		if [ -n "${SANDBOX_LEVEL}" ] && [ "${SANDBOX_LEVEL}" -ge 2 ]; then
			sandbox_level_msg="(level 2)"
			sandbox_params="${sandbox_params} \
                            --dir /run/user/${EUID} \
                            --ro-bind-try /run/user/${EUID}/${wayland_socket} /run/user/${EUID}/${wayland_socket} \
                            --unshare-pid \
                            --unshare-user-try \
                            --unsetenv DBUS_SESSION_BUS_ADDRESS"
		else
			sandbox_level_msg="(level 1)"
			sandbox_params="${sandbox_params} \
                            --bind-try /run/user /run/user \
                            --bind-try /run/dbus /run/dbus"
		fi

		if [ -n "${SANDBOX_LEVEL}" ] && [ "${SANDBOX_LEVEL}" -ge 3 ]; then
			sandbox_level_msg="(level 3)"
			DISABLE_NET=1
			sandbox_params="${sandbox_params} \
                            --ro-bind-try /tmp/.X11-unix/X${xephyr_display} /tmp/.X11-unix/X${xephyr_display} \
                            --setenv DISPLAY :${xephyr_display}"
		else
			sandbox_params="${sandbox_params} \
                            --ro-bind-try /tmp/.X11-unix /tmp/.X11-unix"
		fi

		show_msg "Sandbox is enabled ${sandbox_level_msg}"
	fi

	if [ "${DISABLE_NET}" = 1 ]; then
		show_msg "Network is disabled"

		unshare_net="--unshare-net"
	fi

	if [ -n "${HOME_DIR}" ]; then
		show_msg "Set home directory to ${HOME_DIR}"

		custom_home="--bind ${HOME_DIR} ${HOME}"
	fi

	if [ -n "${BIND}" ]; then
		show_msg "Mounted items: ${BIND}"

		for i in ${BIND}; do
			bind_items="${bind_items} --bind ${i} ${i}"
		done
	fi

	if [ -n "${BIND_RO}" ]; then
		show_msg "Read-only mounted items: ${BIND_RO}"

		for i in ${BIND_RO}; do
			bind_items="${bind_items} --ro-bind ${i} ${i}"
		done
	fi

	# Set the XAUTHORITY variable if it's missing (which is unlikely)
	if [ -z "${XAUTHORITY}" ]; then
		XAUTHORITY="${HOME}"/.Xauthority
	fi

	show_msg

	launch_wrapper "${bwrap}" \
			--ro-bind "${mount_point}" / \
			--dev-bind /dev /dev \
			--ro-bind /sys /sys \
			--bind-try /tmp /tmp \
			--proc /proc \
			--bind-try /home /home \
			--bind-try /mnt /mnt \
			--bind-try /opt /opt \
			--bind-try /media /media \
			--bind-try /run /run \
			--bind-try /var /var \
			--ro-bind-try /usr/share/steam/compatibilitytools.d /usr/share/steam/compatibilitytools.d \
			--ro-bind-try /etc/resolv.conf /etc/resolv.conf \
			--ro-bind-try /etc/hosts /etc/hosts \
			--ro-bind-try /etc/nsswitch.conf /etc/nsswitch.conf \
			--ro-bind-try /etc/passwd /etc/passwd \
			--ro-bind-try /etc/group /etc/group \
			--ro-bind-try /etc/machine-id /etc/machine-id \
			--ro-bind-try /etc/asound.conf /etc/asound.conf \
			--ro-bind-try /etc/localtime /etc/localtime \
			${sandbox_params} \
			${custom_home} \
			${bind_items} \
			${unshare_net} \
			${nvidia_driver_bind} \
			--ro-bind-try "${XAUTHORITY}" "${XAUTHORITY}" \
			--setenv PATH "${CUSTOM_PATH}" \
			"$@"
}

# A function that checks if the Nvidia kernel module loaded in the
# system matches the version of the Nvidia libraries inside the container
# and downloads corresponding Nvidia libs from the official site if they
# are not the same. Also binds the downloaded libraries to the container.

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
				done

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
			fi
		fi
	fi
}

trap_exit () {
	rm -f "${working_dir}"/running_"${script_id}"

	if [ ! "$(ls "${working_dir}"/running_* 2>/dev/null)" ]; then
		fusermount${fuse_version} -uz "${mount_point}" 2>/dev/null || \
		${use_sudo} umount --lazy "${mount_point}" 2>/dev/null

		rm -rf "${working_dir}"
	fi

	exit
}

trap 'trap_exit' EXIT

if [ "$(ls "${working_dir}"/running_* 2>/dev/null)" ] && [ ! "$(ls "${mount_point}" 2>/dev/null)" ]; then
	rm -f "${working_dir}"/running_*
fi

# Mount the image
mkdir -p "${mount_point}"

# Since mounting dwarfs images is relatively slow on HDDs, it's better
# to show a message when the mounting is in process
if [ "${dwarfs_image}" = 1 ] && [ ! "$(ls "${mount_point}" 2>/dev/null)" ]; then
	show_msg "Mounting the image, please wait..."
fi

if [ "$(ls "${mount_point}" 2>/dev/null)" ] || \
	( [ "${dwarfs_image}" != 1 ] && launch_wrapper "${mount_tool}" -o offset="${offset}",ro "${script}" "${mount_point}" ) || \
	launch_wrapper "${mount_tool}" "${script}" "${mount_point}" -o offset="${offset}" -o debuglevel=error -o workers="${dwarfs_num_workers}" \
	-o mlock=try -o no_cache_image -o cache_files -o cachesize="${dwarfs_cache_size}"; then

	if [ "$1" = "-m" ]; then
		if [ ! -f "${working_dir}"/running_mount ]; then
			echo 1 > "${working_dir}"/running_mount
			echo "The image has been mounted to ${mount_point}"
		else
			rm -f "${working_dir}"/running_mount
			echo "The image has been unmounted"
		fi

		exit
	fi

	if [ "$1" = "-V" ]; then
		if [ -f "${mount_point}"/version ]; then
			cat "${mount_point}"/version
		else
			echo "Unknown version"
		fi

		exit
	fi

	echo 1 > "${working_dir}"/running_"${script_id}"

	if [ "${dwarfs_image}" = 1 ] && [ "${QUIET_MODE}" != 1 ]; then
		clear
	fi

	show_msg "Running Conty"

	if [ "${NVIDIA_FIX}" = 1 ]; then
		bind_nvidia_driver
	fi

	export CUSTOM_PATH="/bin:/sbin:/usr/bin:/usr/sbin:/usr/lib/jvm/default/bin:/usr/local/bin:/usr/local/sbin:${PATH}"

	if [ "$1" = "-l" ]; then
		run_bwrap --ro-bind "${mount_point}"/var /var \
                  bash -c "pacman -Qn; pacman -Qm"
		exit
	fi

	# If SANDBOX_LEVEL is 3, run Xephyr and openbox before running applications
	if [ "${SANDBOX}" = 1 ] && [ -n "${SANDBOX_LEVEL}" ] && [ "${SANDBOX_LEVEL}" -ge 3 ]; then
		if [ -f "${mount_point}"/usr/bin/Xephyr ]; then
			if [ -z "${XEPHYR_SIZE}" ]; then
				XEPHYR_SIZE="800x600"
			fi

			xephyr_display="$((${script_id}+2))"

			if [ -S /tmp/.X11-unix/X${xephyr_display} ]; then
				xephyr_display="$((${script_id}+10))"
			fi

			QUIET_MODE=1 DISABLE_NET=1 SANDBOX_LEVEL=2 run_bwrap \
			--bind /tmp/.X11-unix /tmp/.X11-unix \
			Xephyr -noreset -ac -br -screen ${XEPHYR_SIZE} :${xephyr_display} &>/dev/null & sleep 1
			xephyr_pid=$!

			QUIET_MODE=1 run_bwrap openbox & sleep 1
		else
			echo "SANDBOX_LEVEL is set to 3, but Xephyr is not present inside the container."
			echo "Xephyr is required for this SANDBOX_LEVEL."

			exit 1
		fi
	fi

	if [ -L "${script_literal}" ] && [ -f "${mount_point}"/usr/bin/"${script_name}" ]; then
		export CUSTOM_PATH="/bin:/sbin:/usr/bin:/usr/sbin:/usr/lib/jvm/default/bin"

		show_msg "Autostarting ${script_name}"
		run_bwrap "${script_name}" "$@"
	else
		run_bwrap "$@"
	fi

	if [ -n "${xephyr_pid}" ]; then
		wait ${xephyr_pid}
	fi
else
	echo "Mounting the image failed!"

	exit 1
fi

exit
