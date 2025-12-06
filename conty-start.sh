#!/usr/bin/env bash
## Dependencies: bash gzip fuse2 (or fuse3) tar coreutils

LD_PRELOAD_ORIG="${LD_PRELOAD}"
LD_LIBRARY_PATH_ORIG="${LD_LIBRARY_PATH}"
unset LD_PRELOAD LD_LIBRARY_PATH

LC_ALL_ORIG="${LC_ALL}"
export LC_ALL=C

export PATH="/usr/sbin:${PATH}"

msg_root="
Do not run this script as root!

If you really need to run it as root and know what you are doing, set
the ALLOW_ROOT environment variable.
"

# Refuse to run as root unless environment variable is set
if (( EUID == 0 )) && [ -z "$ALLOW_ROOT" ]; then
    echo "${msg_root}"
    exit 1
fi

# Conty version
script_version="1.28"

# Important variables to manually adjust after modification!
# Needed to avoid problems with mounting due to an incorrect offset.
#
# If you build Conty without some of the components, you can set their
# size to 0
init_size=50000
bash_size=1752808
script_size=42559
busybox_size=1181592
utils_size=4393102

# Full path to the script
if [ -n "${BASH_SOURCE[0]}" ]; then
	script_literal="${BASH_SOURCE[0]}"
else
	script_literal="${0}"

	if [ "${script_literal}" = "$(basename "${script_literal}")" ]; then
		script_literal="$(command -v "${0}")"
	fi
fi
script_name="$(basename "${script_literal}")"
script="$(readlink -f "${script_literal}")"

# Check if head supports -c argument

unset HEAD_C_SUPPORTED
head -c 0 /dev/null &>/dev/null && HEAD_C_SUPPORTED=1

# MD5 of the first 4 MB and the last 1 MB of the script
if [ "${HEAD_C_SUPPORTED}" = 1 ]; then
	script_md5="$(head -c 4000000 "${script}" | md5sum | head -c 7)"_"$(tail -c 1000000 "${script}" | md5sum | head -c 7)"
else
	script_md5="$(dd if="${script}" bs=4000000 count=1 2>/dev/null | md5sum | cut -c1-7)"_"$(dd if="${script}" bs=1000000 skip=100 count=1 2>/dev/null | md5sum | cut -c1-7)"
fi

script_id="$$"

# Working directory where the utils will be extracted
# And where the image will be mounted
# The default path is /tmp/conty_username_scriptmd5
# And if /tmp is mounted with noexec, the default path
# is ~/.local/share/Conty/conty_username_scriptmd5
conty_dir_name=conty_"${USER}"_"${script_md5}"

if  [ -z "${BASE_DIR}" ]; then
	export working_dir=/tmp/"${conty_dir_name}"
else
	export working_dir="${BASE_DIR}"/"${conty_dir_name}"
fi

if [ "${USE_SYS_UTILS}" != 1 ] && [[ "${busybox_size}" -gt 0 ]]; then
	busybox_bin_dir="${working_dir}"/busybox_bins
	busybox_path="${busybox_bin_dir}"/busybox

	if [ ! -f "${busybox_bin_dir}"/echo ]; then
		mkdir -p "${busybox_bin_dir}"

		if [ "${HEAD_C_SUPPORTED}" = 1 ]; then
			tail -c +$((init_size+bash_size+script_size+1)) "${script}" | head -c "${busybox_size}" > "${busybox_path}"
		else
			dd if="${script}" of="${busybox_path}" bs=1 skip=$((init_size+bash_size+script_size)) count="${busybox_size}" 2>/dev/null
		fi

		chmod +x "${busybox_path}" 2>/dev/null
		"${busybox_path}" --install -s "${busybox_bin_dir}" &>/dev/null
	fi

	if "${busybox_bin_dir}"/echo &>/dev/null; then
		export PATH="${busybox_bin_dir}:${PATH}"
	fi
fi

# Help output
msg_help="
Usage: ${script_name} [COMMAND] [ARGUMENTS]


Arguments:
  -e    Extract the image

  -h    Display this text

  -H    Display bubblewrap help

  -g    Run the Conty's graphical interface

  -l    Show a list of all installed packages

  -d    Export desktop files from Conty into the application menu of
        your desktop environment.
        Note that not all applications have desktop files, and also that
        desktop files are tied to the current location of Conty, so if
        you move or rename it, you will need to re-export them.
        To remove the exported files, use this argument again.

  -m    Mount/unmount the image
        The image will be mounted if it's not, unmounted otherwise.
        Mount point can be changed with the BASE_DIR env variable
        (the default is /tmp).

  -o    Show the image offset

  -v    Display version of this script

  -V    Display version of the image

Arguments that don't match any of the above will be passed directly to
bubblewrap, so all bubblewrap arguments are supported as well.


Environment variables:
  BASE_DIR          Sets a custom directory where Conty will extract its
                    builtin utilities and mount the image.
                    The default is /tmp.

  DISABLE_NET       Disables network access.

  DISABLE_X11       Disables access to X server.

                    Note: Even with this variable enabled applications
                    can still access your X server if it doesn't use
                    XAUTHORITY and listens to the abstract socket. This
                    can be solved by enabling XAUTHORITY, disabling the
                    abstract socket or by disabling network access.

  HOME_DIR          Sets the home directory to a custom location.
                    For example: HOME_DIR=\"$HOME/custom_home\"
                    Note: If this variable is set the home directory
                    inside the container will still appear as $HOME,
                    even though the custom directory is used.

  QUIET_MODE        Disables all non-error Conty messages.
                    Doesn't affect the output of applications.

  SANDBOX           Enables a sandbox.
                    To control which files and directories are available
                    inside the container, you can use the --bind and
                    --ro-bind launch arguments.
                    (See bubblewrap help for more info).

  SANDBOX_LEVEL     Controls the strictness of the sandbox.
                    Available levels:
                      1: Isolates all user files.
                      2: Additionally disables dbus and hides all
                         running processes.
                      3: Additionally disables network access and
                         isolates X11 server with Xephyr.
                    The default is 1.

  USE_OVERLAYFS     Mounts a writable unionfs-fuse filesystem on top
                    of the read-only squashfs/dwarfs image, allowing to
                    modify files inside it.
                    Overlays are stored in ~/.local/share/Conty. If you
                    want to undo any changes, delete the entire
                    directory from there.

  NVIDIA_HANDLER    Fixes issues with graphical applications on Nvidia
                    GPUs with the proprietary driver. At least 2 GB of
                    free disk space is required for this function.
                    This function is enabled by default on systems with
                    an Nvidia GPU.
                    Available modes:
                      1. In this mode Conty downloads the
                         driver from the official Nvidia website and
                         installs it inside the container.
                      2. In this mode Conty copies Nvidia libraries from
                         the host system into the container.
                    The default is 1 if there is an internet
                    connection and the Nvidia website is accessible,
                    otherwise the default is 2.

  USE_SYS_UTILS     Tells the script to use squashfuse/dwarfs and bwrap
                    installed on the system instead of the builtin ones.

  XEPHYR_SIZE       Sets the size of the Xephyr window. The default is
                    800x600.

  CUSTOM_MNT        Sets a custom mount point for the Conty. This allows
                    Conty to be used with already mounted filesystems.
                    Conty will not mount its image on this mount point,
                    but it will use files that are already present
                    there.

Additional notes:
System directories/files will not be available inside the container if
you set the SANDBOX variable but don't bind (mount) any items or set
HOME_DIR. A fake temporary home directory will be used instead.

If the executed script is a symlink with a different name, said name
will be used as the command name.
For instance, if the script is a symlink with the name \"wine\" it will
automatically run wine during launch.

Running Conty without any arguments from a graphical interface (for
example, from a file manager) will automatically launch the Conty's
graphical interface.
"

if [ -n "${CUSTOM_MNT}" ] && [ -d "${CUSTOM_MNT}" ]; then
	mount_point="${CUSTOM_MNT}"
else
	mount_point="${working_dir}"/mnt
fi

export overlayfs_dir="${HOME}"/.local/share/Conty/overlayfs_"${script_md5}"
export nvidia_drivers_dir="${overlayfs_dir}"/nvidia

export overlayfs_shared_dir="${HOME}"/.local/share/Conty/overlayfs_shared
export nvidia_drivers_shared_dir="${overlayfs_shared_dir}"/nvidia

# Offset where the image is stored
offset=$((init_size+bash_size+script_size+busybox_size+utils_size))

# Detect if the image is compressed with DwarFS or SquashFS
if [ "$(tail -c +$((offset+1)) "${script}" | head -c 6)" = "DWARFS" ]; then
	dwarfs_image=1
fi

# Enable NVIDIA_HANDLER by default
NVIDIA_HANDLER="${NVIDIA_HANDLER:-1}"

unset script_is_symlink
if [ -L "${script_literal}" ]; then
    script_is_symlink=1
fi

if [ -z "${script_is_symlink}" ]; then
    if [ -t 0 ] && ([ "$1" = "-h" ] || [ -z "$1" ]); then
        echo "${msg_help}"
        exit
    elif [ "$1" = "-v" ]; then
        echo "${script_version}"
        exit
    elif [ "$1" = "-o" ]; then
        echo "${offset}"
        exit
    fi
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
	if [ "${USE_SYS_UTILS}" = 1 ]; then
		"$@"
	else
		"${working_dir}"/utils/ld-linux-x86-64.so.2 --library-path "${working_dir}"/utils "$@"
	fi
}

gui () {
	if ! command -v zenity 1>/dev/null; then
		exit 1
	fi

	gui_response=$(zenity --title="Conty" \
		--entry \
		--text="Enter a command or select a file you want to run" \
		--ok-label="Run" \
		--cancel-label="Quit" \
		--extra-button="Select a file" \
		--extra-button="Open a terminal")

	gui_exit_code=$?

	if [ "${gui_response}" = "Select a file" ]; then
		filepath="$(zenity --title="A file to run" --file-selection)"

		if [ -f "${filepath}" ]; then
			[ -x "${filepath}" ] || chmod +x "${filepath}"
			"${filepath}"
		else
			zenity --error --text="You did not select a file"
		fi
	elif [ "${gui_response}" = "Open a terminal" ]; then
		if command -v lxterminal 1>/dev/null; then
			lxterminal -T "Conty terminal" --command="bash -c 'echo Welcome to Conty; echo Enter any commands you want to execute; bash'"
		else
			zenity --error --text="A terminal emulator is not installed in this instance of Conty"
		fi
	elif [ "${gui_exit_code}" = 0 ]; then
		if [ -z "${gui_response}" ]; then
			zenity --error --text="You need to enter a command to execute"
		else
			for a in ${gui_response}; do
				if [ "${a:0:1}" = "\"" ] || [ "${a:0:1}" = "'" ] || [ -n "${combined_args}" ]; then
					combined_args="${combined_args} ${a}"

					if [ "${a: -1}" = "\"" ] || [ "${a: -1}" = "'" ]; then
						combined_args="${combined_args:2}"
						combined_args="${combined_args%?}"

						launch_command+=("${combined_args}")
						unset combined_args
					fi

					continue
				fi

				launch_command+=("${a}")
			done

			"${launch_command[@]}"
		fi
	fi
}

mount_overlayfs () {
	mkdir -p "${overlayfs_dir}"/up
	mkdir -p "${overlayfs_dir}"/work
	mkdir -p "${overlayfs_dir}"/merged
	mkdir -p "${nvidia_drivers_dir}"

	if [ ! "$(ls "${overlayfs_dir}"/merged 2>/dev/null)" ]; then
		if command -v "${unionfs_fuse}" 1>/dev/null; then
			if [ "${1}" = "share_nvidia" ]; then
				launch_wrapper "${unionfs_fuse}" -o relaxed_permissions,cow,noatime "${overlayfs_dir}"/up=RW:"${overlayfs_shared_dir}"/up=RO:"${mount_point}"=RO "${overlayfs_dir}"/merged
			else
				launch_wrapper "${unionfs_fuse}" -o relaxed_permissions,cow,noatime "${overlayfs_dir}"/up=RW:"${mount_point}"=RO "${overlayfs_dir}"/merged
			fi
		else
			echo "unionfs-fuse not found"
			return 1
		fi
	fi
}

nvidia_driver_handler () {
	OLD_PWD="${PWD}"

	rm -rf "${nvidia_drivers_dir}"/nvidia.run "${nvidia_drivers_dir}"/nvidia-driver
	mkdir -p "${nvidia_drivers_dir}"
	cd "${nvidia_drivers_dir}"

	echo "Found Nvidia driver ${nvidia_driver_version}"
	echo "Downloading the Nvidia driver ${nvidia_driver_version}..."

	# Try to download the driver from the default Nvidia URL
	driver_url="https://download.nvidia.com/XFree86/Linux-x86_64/${nvidia_driver_version}/NVIDIA-Linux-x86_64-${nvidia_driver_version}.run"
	curl -#Lo nvidia.run "${driver_url}"

	# If the previous download failed, get the URL from FlatHub repo
	if [ ! -s nvidia.run ] || [[ "$(stat -c%s nvidia.run)" -lt 30000000 ]]; then
		rm -f nvidia.run
		driver_url="https:$(curl -#Lo - "https://raw.githubusercontent.com/flathub/org.freedesktop.Platform.GL.nvidia/master/data/nvidia-${nvidia_driver_version}-x86_64.data" | cut -d ':' -f 6)"
		curl -#Lo nvidia.run "${driver_url}"
	fi

	if [ -s nvidia.run ]; then
		echo "Installing the Nvidia driver, please wait..."
		chmod +x nvidia.run
		./nvidia.run --target nvidia-driver -x &>/dev/null

		if [ -f nvidia-driver/nvidia-installer ]; then
			cd nvidia-driver || exit 1
			chmod +x nvidia-installer
			fakeroot ./nvidia-installer --silent --no-x-check --no-kernel-module &>/dev/null
			rm -rf "${nvidia_drivers_dir}"/nvidia.run "${nvidia_drivers_dir}"/nvidia-driver

			if [ -s /usr/lib/libGLX_nvidia.so."${nvidia_driver_version}" ] || \
			   [ -s /usr/lib/libGL.so."${nvidia_driver_version}" ] || \
                           [ -s /usr/lib/libnvidia-glcore.so."${nvidia_driver_version}" ] || \
			   [ -s /usr/lib/libnvidia-eglcore.so."${nvidia_driver_version}" ]; then
				cp /usr/lib/tls/libnvidia-tls.so.* /usr/lib &>/dev/null
				cp /usr/lib32/tls/libnvidia-tls.so.* /usr/lib32 &>/dev/null
				echo "${nvidia_driver_version}" > "${nvidia_drivers_dir}"/current-nvidia-version
				echo "The driver installed successfully"
				nvidia_install_success=1
			else
				echo "Failed to install the driver"
			fi
		else
			echo "Failed to extract the driver"
		fi
	else
		echo "Failed to download the driver"
	fi

	if [ "${nvidia_install_success}" != 1 ]; then
		rm -f "${nvidia_drivers_dir}"/current-nvidia-version
	fi

	cd "${OLD_PWD}"
}

# Check if FUSE is installed
if ! command -v fusermount3 1>/dev/null && ! command -v fusermount 1>/dev/null; then
	echo "Please install fuse2 or fuse3 and run the script again."
	exit 1
fi

if command -v fusermount3 1>/dev/null; then
	fuse_version=3
fi

# Set the dwarfs block cache size depending on how much RAM is available
# Also set the number of workers depending on the number of CPU cores

dwarfs_cache_size="128M"
dwarfs_num_workers="2"

if [ "${dwarfs_image}" = 1 ]; then
	if getconf _PHYS_PAGES &>/dev/null && getconf PAGE_SIZE &>/dev/null; then
		memory_size="$(($(getconf _PHYS_PAGES) * $(getconf PAGE_SIZE) / (1024 * 1024)))"

		if [[ "${memory_size}" -ge 45000 ]]; then
			dwarfs_cache_size="4096M"
		elif [[ "${memory_size}" -ge 23000 ]]; then
			dwarfs_cache_size="2048M"
		elif [[ "${memory_size}" -ge 15000 ]]; then
			dwarfs_cache_size="1024M"
		elif [[ "${memory_size}" -ge 7000 ]]; then
			dwarfs_cache_size="512M"
		elif [[ "${memory_size}" -ge 3000 ]]; then
			dwarfs_cache_size="256M"
		elif [[ "${memory_size}" -ge 1500 ]]; then
			dwarfs_cache_size="128M"
		else
			dwarfs_cache_size="64M"
		fi
	fi

	if getconf _NPROCESSORS_ONLN &>/dev/null; then
		dwarfs_num_workers="$(getconf _NPROCESSORS_ONLN)"

		if [[ "${dwarfs_num_workers}" -ge 8 ]]; then
			dwarfs_num_workers=8
		fi
	fi
fi

# Extract utils.tar.gz
mkdir -p "${working_dir}"

if [ "${USE_SYS_UTILS}" != 1 ] && [[ "${utils_size}" -gt 0 ]]; then
	# Check if filesystem of the working_dir is mounted without noexec
	if ! exec_test; then
		if [ -z "${BASE_DIR}" ]; then
			export working_dir="${HOME}"/.local/share/Conty/"${conty_dir_name}"

			if [ -z "${CUSTOM_MNT}" ]; then
				mount_point="${working_dir}"/mnt
			fi
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
		mount_tool="${working_dir}"/utils/dwarfs"${fuse_version}"
		extraction_tool="${working_dir}"/utils/dwarfsextract
		compression_tool="${working_dir}"/utils/mkdwarfs
	else
		mount_tool="${working_dir}"/utils/squashfuse"${fuse_version}"
		extraction_tool="${working_dir}"/utils/unsquashfs
		compression_tool="${working_dir}"/utils/mksquashfs
	fi

	bwrap="${working_dir}"/utils/bwrap
	unionfs_fuse="${working_dir}"/utils/unionfs"${fuse_version}"

	if [ ! -f "${mount_tool}" ] || [ ! -f "${bwrap}" ]; then
		tail -c +$((init_size+bash_size+script_size+busybox_size+1)) "${script}" | head -c "${utils_size}" | tar -C "${working_dir}" -zxf -

		if [ ! -f "${mount_tool}" ] || [ ! -f "${bwrap}" ]; then
			clear
			echo "The integrated utils were not extracted!"
			echo "Perhaps something is wrong with the integrated utils.tar.gz."

			exit 1
		fi

		chmod +x "${mount_tool}" 2>/dev/null
		chmod +x "${bwrap}" 2>/dev/null
		chmod +x "${extraction_tool}" 2>/dev/null
		chmod +x "${unionfs_fuse}" 2>/dev/null
		chmod +x "${compression_tool}" 2>/dev/null
	fi
else
	if ! command -v bwrap 1>/dev/null; then
		echo "USE_SYS_UTILS is enabled, but bubblewrap is not installed!"
		echo "Please install it and run the script again."

		exit 1
	fi

	bwrap=bwrap
	unionfs_fuse=unionfs

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

		extraction_tool=dwarfsextract
	else
		if ! command -v squashfuse 1>/dev/null; then
			echo "USE_SYS_UTILS is enabled, but squashfuse is not installed!"
			echo "Please install it and run the script again."

			exit 1
		fi

		mount_tool=squashfuse
		extraction_tool=unsquashfs
	fi

	show_msg "Using system-wide ${mount_tool} and bwrap"
fi

if [ "$1" = "-e" ] && [ -z "${script_is_symlink}" ]; then
	if command -v "${extraction_tool}" 1>/dev/null; then
		if [ "${dwarfs_image}" = 1 ]; then
			echo "Extracting the image..."
			mkdir "$(basename "${script}")"_files
			launch_wrapper "${extraction_tool}" -i "${script}" -o "$(basename "${script}")"_files -O "${offset}"
			echo "Done"
		else
			launch_wrapper "${extraction_tool}" -o "${offset}" -user-xattrs -d "$(basename "${script}")"_files "${script}"
		fi
	else
		echo "Extraction tool not found"
		exit 1
	fi

	exit
fi

if [ "$1" = "-H" ] && [ -z "${script_is_symlink}" ]; then
	launch_wrapper "${bwrap}" --help
	exit
fi

run_bwrap () {
	unset sandbox_params
	unset unshare_net
	unset custom_home
	unset non_standard_home
	unset xsockets
	unset mount_opt
	unset command_line

	command_line=("${@}")

	if [ -n "${WAYLAND_DISPLAY}" ]; then
		wayland_socket="${WAYLAND_DISPLAY}"
	else
		wayland_socket="wayland-0"
	fi

	if [ -z "${XDG_RUNTIME_DIR}" ]; then
		XDG_RUNTIME_DIR="/run/user/${EUID}"
	fi

	# Handle non-standard HOME locations that are outside of our default
	# visibility scope
	if [ -n "${HOME}" ] && [ "$(echo "${HOME}" | head -c 6)" != "/home/" ]; then
		HOME_BASE_DIR="$(echo "${HOME}" | cut -d '/' -f2)"

		case "${HOME_BASE_DIR}" in
			tmp|mnt|media|run|var)
				;;
			*)
				NEW_HOME=/home/"${USER}"
				non_standard_home+=(--tmpfs /home \
							--bind "${HOME}" "${NEW_HOME}" \
							--setenv "HOME" "${NEW_HOME}" \
	 						--setenv "XDG_CONFIG_HOME" "${NEW_HOME}"/.config \
							--setenv "XDG_DATA_HOME" "${NEW_HOME}"/.local/share)

				unset command_line
				for arg in "$@"; do
					if [[ "${arg}" == *"${HOME}"* ]]; then
						arg="$(echo "${arg/"$HOME"/"$NEW_HOME"}")"
					fi

					command_line+=("${arg}")
				done
				;;
		esac
	fi

	if [ "${SANDBOX}" = 1 ]; then
		sandbox_params+=(--tmpfs /home \
						 --tmpfs /mnt \
						 --tmpfs /initrd \
						 --tmpfs /media \
						 --tmpfs /var \
						 --tmpfs /run \
						 --symlink /run /var/run \
						 --tmpfs /tmp \
						 --new-session)

		if [ -n "${non_standard_home[*]}" ]; then
			sandbox_params+=(--dir "${NEW_HOME}")
		else
			sandbox_params+=(--dir "${HOME}")
		fi

		if [ -n "${SANDBOX_LEVEL}" ] && [[ "${SANDBOX_LEVEL}" -ge 2 ]]; then
			sandbox_level_msg="(level 2)"
			sandbox_params+=(--dir "${XDG_RUNTIME_DIR}" \
                             --ro-bind-try "${XDG_RUNTIME_DIR}"/"${wayland_socket}" "${XDG_RUNTIME_DIR}"/"${wayland_socket}" \
                             --ro-bind-try "${XDG_RUNTIME_DIR}"/pulse "${XDG_RUNTIME_DIR}"/pulse \
                             --ro-bind-try "${XDG_RUNTIME_DIR}"/pipewire-0 "${XDG_RUNTIME_DIR}"/pipewire-0 \
                             --unshare-pid \
                             --unshare-user-try \
                             --unsetenv "DBUS_SESSION_BUS_ADDRESS")
		else
			sandbox_level_msg="(level 1)"
			sandbox_params+=(--bind-try "${XDG_RUNTIME_DIR}" "${XDG_RUNTIME_DIR}" \
							 --bind-try /run/dbus /run/dbus)
		fi

		if [ -n "${SANDBOX_LEVEL}" ] && [[ "${SANDBOX_LEVEL}" -ge 3 ]]; then
			sandbox_level_msg="(level 3)"
			DISABLE_NET=1
		fi

		show_msg "Sandbox is enabled ${sandbox_level_msg}"
	fi

	if [ "${DISABLE_NET}" = 1 ]; then
		show_msg "Network is disabled"

		unshare_net=(--unshare-net)
	fi

	if [ -n "${HOME_DIR}" ]; then
		show_msg "Home directory is set to ${HOME_DIR}"

		if [ -n "${non_standard_home[*]}" ]; then
			custom_home+=(--bind "${HOME_DIR}" "${NEW_HOME}")
		else
			custom_home+=(--bind "${HOME_DIR}" "${HOME}")
		fi

		[ ! -d "${HOME_DIR}" ] && mkdir -p "${HOME_DIR}"
	fi

	# Set the XAUTHORITY variable if it's missing
	if [ -z "${XAUTHORITY}" ]; then
		XAUTHORITY="${HOME}"/.Xauthority
	fi

	# Mount X server sockets and XAUTHORITY
	xsockets+=(--tmpfs /tmp/.X11-unix)

	if [ -n "${non_standard_home[*]}" ] && [ "${XAUTHORITY}" = "${HOME}"/.Xauthority ]; then
		xsockets+=(--ro-bind-try "${XAUTHORITY}" "${NEW_HOME}"/.Xauthority \
		           --setenv "XAUTHORITY" "${NEW_HOME}"/.Xauthority)
	else
		xsockets+=(--ro-bind-try "${XAUTHORITY}" "${XAUTHORITY}")
	fi

	if [ "${DISABLE_X11}" != 1 ]; then
		if [ "$(ls /tmp/.X11-unix 2>/dev/null)" ]; then
			if [ -n "${SANDBOX_LEVEL}" ] && [[ "${SANDBOX_LEVEL}" -ge 3 ]]; then
				xsockets+=(--ro-bind-try /tmp/.X11-unix/X"${xephyr_display}" /tmp/.X11-unix/X"${xephyr_display}" \
						   --setenv "DISPLAY" :"${xephyr_display}")
			else
				for s in /tmp/.X11-unix/*; do
					xsockets+=(--bind-try "${s}" "${s}")
				done
			fi
		fi
	else
		show_msg "Access to X server is disabled"

		# Unset the DISPLAY and XAUTHORITY env variables and mount an
		# empty file to XAUTHORITY to invalidate it
		xsockets+=(--ro-bind-try "${working_dir}"/running_"${script_id}" "${XAUTHORITY}" \
				   --unsetenv "DISPLAY" \
                   --unsetenv "XAUTHORITY")
	fi

	if [ ! "$(ls "${mount_point}"/opt 2>/dev/null)" ] && [ -z "${SANDBOX}" ]; then
		mount_opt=(--bind-try /opt /opt)
	fi

	if ([[ "${NVIDIA_HANDLER}" -ge 1 ]] || [ "${USE_OVERLAYFS}" = 1 ]) && \
		[ "$(ls "${overlayfs_dir}"/merged 2>/dev/null)" ]; then
		newroot_path="${overlayfs_dir}"/merged
	else
		newroot_path="${mount_point}"
	fi

	if [ "${RW_ROOT}" = 1 ]; then
		bind_root=(--bind "${newroot_path}" /)
	else
		bind_root=(--ro-bind "${newroot_path}" /)
	fi

	conty_variables="BASE_DIR DISABLE_NET DISABLE_X11 HOME_DIR QUIET_MODE \
					SANDBOX SANDBOX_LEVEL USE_OVERLAYFS NVIDIA_HANDLER \
					USE_SYS_UTILS XEPHYR_SIZE CUSTOM_MNT"

	for v in ${conty_variables}; do
		set_vars+=(--unsetenv "${v}")
	done

	[ -n "${LD_PRELOAD_ORIG}" ] && set_vars+=(--setenv LD_PRELOAD "${LD_PRELOAD_ORIG}")
	[ -n "${LD_LIBRARY_PATH_ORIG}" ] && set_vars+=(--setenv LD_LIBRARY_PATH "${LD_LIBRARY_PATH_ORIG}")

	if [ -n "${LC_ALL_ORIG}" ]; then
		set_vars+=(--setenv LC_ALL "${LC_ALL_ORIG}")
	else
		set_vars+=(--unsetenv LC_ALL)
	fi

	show_msg

	launch_wrapper "${bwrap}" \
			"${bind_root[@]}" \
			--dev-bind /dev /dev \
			--ro-bind /sys /sys \
			--bind-try /tmp /tmp \
			--proc /proc \
			--bind-try /home /home \
			--bind-try /mnt /mnt \
			--bind-try /initrd /initrd \
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
			"${non_standard_home[@]}" \
			"${sandbox_params[@]}" \
			"${custom_home[@]}" \
			"${mount_opt[@]}" \
			"${xsockets[@]}" \
			"${unshare_net[@]}" \
			"${set_vars[@]}" \
			--setenv PATH "${CUSTOM_PATH}" \
   			--setenv XDG_DATA_DIRS "/usr/local/share:/usr/share:${XDG_DATA_DIRS}" \
			"${command_line[@]}"
}

exit_function () {
	sleep 3

	rm -f "${working_dir}"/running_"${script_id}"

	if [ ! "$(ls "${working_dir}"/running_* 2>/dev/null)" ]; then
		if [ -d "${overlayfs_dir}"/merged ]; then
			fusermount"${fuse_version}" -uz "${overlayfs_dir}"/merged 2>/dev/null || \
			umount --lazy "${overlayfs_dir}"/merged 2>/dev/null
		fi

		if [ -z "${CUSTOM_MNT}" ]; then
			fusermount"${fuse_version}" -uz "${mount_point}" 2>/dev/null || \
			umount --lazy "${mount_point}" 2>/dev/null
		fi

		if [ ! "$(ls "${mount_point}" 2>/dev/null)" ] || [ -n "${CUSTOM_MNT}" ]; then
			rm -rf "${working_dir}"
		fi
	fi

	exit
}

trap_exit () {
	exit_function &
}

trap 'trap_exit' EXIT

if [ "$(ls "${working_dir}"/running_* 2>/dev/null)" ] && [ ! "$(ls "${mount_point}" 2>/dev/null)" ]; then
	rm -f "${working_dir}"/running_*
fi

if [ -f "${nvidia_drivers_dir}"/lock ] && [ ! "$(ls "${working_dir}"/running_* 2>/dev/null)" ]; then
	rm -f "${nvidia_drivers_dir}"/lock
fi

if [ "${dwarfs_image}" = 1 ]; then
	mount_command=("${mount_tool}" \
	               "${script}" "${mount_point}" \
	               -o offset="${offset}" \
	               -o debuglevel=error \
	               -o workers="${dwarfs_num_workers}" \
	               -o mlock=try \
	               -o no_cache_image \
	               -o cache_files \
	               -o cachesize="${dwarfs_cache_size}" \
	               -o decratio=0.6 \
	               -o tidy_strategy=swap \
	               -o tidy_interval=5m)
else
	mount_command=("${mount_tool}" \
	               -o offset="${offset}",ro \
	               "${script}" "${mount_point}")
fi

# Increase file descriptors limit in case soft and hard limits are different
# Useful for unionfs-fuse and for some games
ulimit -n $(ulimit -Hn) &>/dev/null

# Mount the image
mkdir -p "${mount_point}"

if [ "$(ls "${mount_point}" 2>/dev/null)" ] || launch_wrapper "${mount_command[@]}"; then
	if [ "$1" = "-m" ] && [ -z "${script_is_symlink}" ]; then
		if [ ! -f "${working_dir}"/running_mount ]; then
			echo 1 > "${working_dir}"/running_mount
			echo "The image has been mounted to ${mount_point}"
		else
			rm -f "${working_dir}"/running_mount
			echo "The image has been unmounted"
		fi

		exit
	fi

	if [ "$1" = "-V" ] && [ -z "${script_is_symlink}" ]; then
		if [ -f "${mount_point}"/version ]; then
			cat "${mount_point}"/version
		else
			echo "Unknown version"
		fi

		exit
	fi

	if [ "$1" = "-d" ] && [ -z "${script_is_symlink}" ]; then
		applications_dir="${HOME}"/.local/share/applications/Conty

		if [ -d "${applications_dir}" ]; then
			rm -rf "${applications_dir}"

			echo "Desktop files have been removed"
			exit
		fi

		mkdir -p "${applications_dir}"
		cp -fr "${mount_point}"/usr/share/applications "${applications_dir}"_temp
		cd "${applications_dir}"_temp || exit 1

		unset variables
		vars="BASE_DIR DISABLE_NET DISABLE_X11 HOME_DIR SANDBOX SANDBOX_LEVEL USE_SYS_UTILS CUSTOM_MNT"
		for v in ${vars}; do
			if [ -n "${!v}" ]; then
				variables="${v}=\"${!v}\" ${variables}"
			fi
		done

		if [ -n "${variables}" ]; then
			variables="env ${variables} "
		fi

		echo "Exporting..."
		shift
		for f in *.desktop */ */*.desktop; do
			if [ "${f}" != "*.desktop" ] && [ "${f}" != "*/*.desktop" ] && [ "${f}" != "*/" ]; then
				if [ -d "${f}" ]; then
					mkdir -p "${applications_dir}"/"${f}"
					continue
				fi

				if [ -L "${f}" ]; then
					cp --remove-destination "${mount_point}"/"$(readlink "${f}")" "${f}"
				fi

				while read -r line; do
					line_function="$(echo "${line}" | head -c 4)"

					if [ "${line_function}" = "Name" ]; then
						line="${line} (Conty)"
					elif [ "${line_function}" = "Exec" ]; then
						line="Exec=${variables}\"${script}\" $@ $(echo "${line}" | tail -c +6)"
					elif [ "${line_function}" = "TryE" ]; then  # pragma: codespell-ignore
						continue
					fi

					echo $line >> "${applications_dir}"/"${f%.desktop}"-conty.desktop
				done < "${f}"
			fi
		done

		mkdir -p "${HOME}"/.local/share
		cp -fr "${mount_point}"/usr/share/icons "${HOME}"/.local/share 2>/dev/null
		rm -rf "${applications_dir}"_temp

		echo "Desktop files have been exported"

		exit
	fi

	echo 1 > "${working_dir}"/running_"${script_id}"

	show_msg "Running Conty"

	export CUSTOM_PATH="/bin:/sbin:/usr/bin:/usr/sbin:/usr/lib/jvm/default/bin:/usr/local/bin:/usr/local/sbin:${PATH}"

	if [ "$1" = "-l" ] && [ -z "${script_is_symlink}" ]; then
		run_bwrap --ro-bind "${mount_point}"/var /var pacman -Q
		exit
	fi

	if [[ "${NVIDIA_HANDLER}" -ge 1 ]]; then
		if [ -f /sys/module/nvidia/version ]; then
			unset NVIDIA_SHARED

			if [ ! "$(ls "${mount_point}"/usr/lib/libGLX_nvidia.so.*.* 2>/dev/null)" ]; then
				export overlayfs_dir="${overlayfs_shared_dir}"
				export nvidia_drivers_dir="${nvidia_drivers_shared_dir}"
				export NVIDIA_SHARED=1
			fi

			if [ -f "${nvidia_drivers_dir}"/lock ]; then
				echo "Nvidia driver is currently installing"
				echo "Please wait a moment and run Conty again"
				exit 1
			fi

			if mount_overlayfs; then
				show_msg "Nvidia driver handler is enabled"

				unset nvidia_skip_install
				unset nvidia_driver_version

				nvidia_driver_version="$(cat /sys/module/nvidia/version)"

				if [ "$(ls "${mount_point}"/usr/lib/libGLX_nvidia.so.*.* 2>/dev/null)" ]; then
					container_nvidia_version="$(basename "${mount_point}"/usr/lib/libGLX_nvidia.so.*.* | tail -c +18)"
				fi

				if [ -f "${nvidia_drivers_dir}"/current-nvidia-version ] && \
					[ ! "$(ls "${overlayfs_dir}"/up 2>/dev/null)" ]; then
					rm -f "${nvidia_drivers_dir}"/current-nvidia-version
				fi

				if [ -z "${nvidia_driver_version}" ] || [ "${nvidia_driver_version}" = "" ]; then
					echo "Unable to determine Nvidia driver version"
					rm -f "${nvidia_drivers_dir}"/current-nvidia-version
					nvidia_skip_install=1
				fi

				if [ "${nvidia_driver_version}" = "${container_nvidia_version}" ]; then
					rm -f "${nvidia_drivers_dir}"/current-nvidia-version
					nvidia_skip_install=1
				fi

				if [ "$(cat "${nvidia_drivers_dir}"/current-nvidia-version 2>/dev/null)" = "${nvidia_driver_version}" ]; then
					nvidia_skip_install=1
				fi

				if [ -z "${nvidia_skip_install}" ]; then
					mkdir -p "${nvidia_drivers_dir}"
					echo > "${nvidia_drivers_dir}"/lock

					if [ "${NVIDIA_HANDLER}" = 1 ]; then
						export nvidia_driver_version
						export -f nvidia_driver_handler
						DISABLE_NET=0 QUIET_MODE=1 RW_ROOT=1 run_bwrap --tmpfs /tmp --tmpfs /var --tmpfs /run \
						--bind "${nvidia_drivers_dir}" "${nvidia_drivers_dir}" \
						bash -c nvidia_driver_handler
					fi

					if [ "${NVIDIA_HANDLER}" = 2 ] || [ ! -f "${nvidia_drivers_dir}"/current-nvidia-version ]; then
						if [ -f "${nvidia_drivers_dir}"/host_nvidia_libs ]; then
							for f in $(cat "${nvidia_drivers_dir}"/host_nvidia_libs); do
								libname="$(basename "${f}")"
								rm -f "${overlayfs_dir}"/merged/usr/lib/"${libname}" \
								      "${overlayfs_dir}"/merged/usr/lib32/"${libname}"
							done
						fi

						rm -f "${nvidia_drivers_dir}"/host_nvidia_libs \
						      "${nvidia_drivers_dir}"/host_libs

						ldconfig -p > "${nvidia_drivers_dir}"/host_libs

						if [ -s "${nvidia_drivers_dir}"/host_libs ]; then
							grep -i "nvidia" "${nvidia_drivers_dir}"/host_libs | cut -d ">" -f 2 >> "${nvidia_drivers_dir}"/host_nvidia_libs

							if [ -s "${nvidia_drivers_dir}"/host_nvidia_libs ]; then
								echo "Copying Nvidia libraries from the host system, please wait..."

 								grep -i "libcuda" "${nvidia_drivers_dir}"/host_libs | cut -d ">" -f 2 >> "${nvidia_drivers_dir}"/host_nvidia_libs

								for f in $(grep "libnv" "${nvidia_drivers_dir}"/host_libs | cut -d ">" -f 2); do
									if strings "${f}" | grep -qi -m 1 "nvidia" &>/dev/null; then
										echo "${f}" >> "${nvidia_drivers_dir}"/host_nvidia_libs
									fi
								done

								nvidia_lib_copied=0
								for f in $(cat "${nvidia_drivers_dir}"/host_nvidia_libs); do
									libname="$(basename "${f}")"

									if file "$(readlink -f "${f}")" | grep "32-bit" &>/dev/null; then
										cp -fL "${f}" "${overlayfs_dir}"/merged/usr/lib32/"${libname}" 2>/dev/null
									else
										cp -fL "${f}" "${overlayfs_dir}"/merged/usr/lib/"${libname}" 2>/dev/null && nvidia_lib_copied=1
									fi
								done

								nvidia_other_files="/usr/share/vulkan/icd.d/nvidia_icd.json \
								                    /usr/share/vulkan/implicit_layer.d/nvidia_layers.json \
								                    /usr/lib/nvidia/wine/nvngx.dll \
								                    /usr/lib/nvidia/wine/_nvngx.dll \
								                    /usr/share/egl/egl_external_platform.d/20_nvidia_xcb.json \
								                    /usr/share/glvnd/egl_vendor.d/10_nvidia.json \
								                    /usr/share/nvidia/nvidia-application-profiles-${nvidia_driver_version}-rc"

								for f in ${nvidia_other_files}; do
									filedir="$(dirname "${f}")"

									if [ -f "${f}" ]; then
										filepath="${f}"
									else
										filepath="$(find /usr /run /nix -name "$(basename "${f}")" -type f -print -quit 2>/dev/null)"
									fi

									if [ -f "${filepath}" ]; then
										mkdir -p "${overlayfs_dir}"/merged/"${filedir}"
										cp -fL "${filepath}" "${overlayfs_dir}"/merged/"${filedir}" &>/dev/null
										cp -fL "$(dirname "${filepath}")"/*nvidia* "${overlayfs_dir}"/merged/"${filedir}" &>/dev/null
									fi
								done

								if [ "${nvidia_lib_copied}" = 1 ]; then
									echo "${nvidia_driver_version}" > "${nvidia_drivers_dir}"/current-nvidia-version
	 							else
	 								echo "Failed to copy Nvidia libraries"
	  							fi
							else
       								echo "Nvidia libraries not found on the host system"
	       						fi
						fi
					fi

					rm -f "${nvidia_drivers_dir}"/lock
				fi

				if [ -n "${NVIDIA_SHARED}" ]; then
					fusermount"${fuse_version}" -uz "${overlayfs_dir}"/merged 2>/dev/null || \
					umount --lazy "${overlayfs_dir}"/merged 2>/dev/null

					rm -f "${overlayfs_shared_dir}"/up/etc/ld.so.cache

					export overlayfs_dir="${HOME}"/.local/share/Conty/overlayfs_"${script_md5}"
					export nvidia_drivers_dir="${overlayfs_dir}"/nvidia

					mount_overlayfs share_nvidia

					if [ "$(cat "${nvidia_drivers_dir}"/ld.so.cache.nvidia 2>/dev/null)" != "${nvidia_driver_version}" ]; then
						QUIET_MODE=1 RW_ROOT=1 run_bwrap ldconfig
						echo "${nvidia_driver_version}" > "${nvidia_drivers_dir}"/ld.so.cache.nvidia
					fi
				fi
			else
				echo "Nvidia driver handler disabled due to unionfs errors"
				unset NVIDIA_HANDLER
			fi
		else
			unset NVIDIA_HANDLER
		fi

		if [ -z "${NVIDIA_SHARED}" ] && [ ! -f "${nvidia_drivers_dir}"/current-nvidia-version ]; then
			unset NVIDIA_HANDLER
		fi
	fi

	if [ "${USE_OVERLAYFS}" = 1 ]; then
		if mount_overlayfs; then
			show_msg "Using unionfs"
			RW_ROOT=1
		else
			echo "Failed to mount unionfs"
			unset USE_OVERLAYFS
		fi
	fi

	# If SANDBOX_LEVEL is 3, run Xephyr and openbox before running applications
	if [ "${SANDBOX}" = 1 ] && [ -n "${SANDBOX_LEVEL}" ] && [[ "${SANDBOX_LEVEL}" -ge 3 ]]; then
		if [ -f "${mount_point}"/usr/bin/Xephyr ]; then
			if [ -z "${XEPHYR_SIZE}" ]; then
				XEPHYR_SIZE="800x600"
			fi

			xephyr_display="$((script_id+2))"

			if [ -S /tmp/.X11-unix/X"${xephyr_display}" ]; then
				xephyr_display="$((script_id+10))"
			fi

			QUIET_MODE=1 DISABLE_NET=1 SANDBOX_LEVEL=2 run_bwrap \
			--bind-try /tmp/.X11-unix /tmp/.X11-unix \
			Xephyr -noreset -ac -br -screen "${XEPHYR_SIZE}" :"${xephyr_display}" &>/dev/null & sleep 1
			xephyr_pid=$!

			QUIET_MODE=1 run_bwrap openbox & sleep 1
		else
			echo "SANDBOX_LEVEL is set to 3, but Xephyr is not present inside the container."
			echo "Xephyr is required for this SANDBOX_LEVEL."

			exit 1
		fi
	fi

	# Disable lsfg-vk by default

	if [ -z "${ENABLE_LSFG}" ] || [ "${ENABLE_LSFG}" = 0 ]; then
		export DISABLE_LSFG=1
	else
		unset DISABLE_LSFG
	fi

	if [ -n "${script_is_symlink}" ] && [ -f "${mount_point}"/usr/bin/"${script_name}" ]; then
		export CUSTOM_PATH="/bin:/sbin:/usr/bin:/usr/sbin:/usr/lib/jvm/default/bin"

		show_msg "Autostarting ${script_name}"
		run_bwrap "${script_name}" "$@"
	elif [ "$1" = "-g" ] || ([ ! -t 0 ] && [ -z "${1}" ] && [ -z "${script_is_symlink}" ]); then
		export -f gui
		run_bwrap bash -c gui
	else
		run_bwrap "$@"
	fi

	if [ -n "${xephyr_pid}" ]; then
		wait "${xephyr_pid}"
	fi
else
	echo "Mounting the image failed!"

	exit 1
fi

exit
