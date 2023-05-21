#!/usr/bin/env bash
## Dependencies: bash gzip fuse2 (or fuse3) tar coreutils

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
script_version="1.23"

# Important variables to manually adjust after modification!
# Needed to avoid problems with mounting due to an incorrect offset.
script_size=33659
utils_size=2564623

# Full path to the script
script_literal="${BASH_SOURCE[0]}"
script_name="$(basename "${script_literal}")"
script="$(readlink -f "${script_literal}")"

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

  -u    Update all packages inside the container
        This requires a rebuild of the image, which may take quite
        a lot of time, depending on your hardware and internet speed.
        Additional disk space (about 6x the size of the current file)
        is needed during the update process.

  -U    Same as -u with the addition of updating the init script and
        the integrated utils. This option may break Conty in some cases,
        use with caution!

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

  NVIDIA_HANDLER    Fixes issues with graphical applications on Nvidia
                    GPUs with the proprietary driver. Enable this only
                    if you are using an Nvidia GPU, the proprietary
                    driver and encountering issues running graphical
                    applications. Fuse3 is required for this to work.

  USE_SYS_UTILS     Tells the script to use squashfuse/dwarfs and bwrap
                    installed on the system instead of the builtin ones.

  XEPHYR_SIZE       Sets the size of the Xephyr window. The default is
                    800x600.

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

Besides updating all packages, you can also install and remove packages
using the same -u (or -U) argument. To install packages add them as
additional arguments, to remove add a minus sign (-) before their names.
  To install: ${script_name} -u pkgname1 pkgname2 pkgname3 ...
  To remove: ${script_name} -u -pkgname1 -pkgname2 -pkgname3 ...
In this case Conty will update all packages and additionally install
and/or remove specified packages.

If you are using an Nvidia GPU, please read the following:
https://github.com/Kron4ek/Conty#known-issues
"

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

export overlayfs_dir="${HOME}"/.local/share/Conty/overlayfs
export nvidia_drivers_dir="${HOME}"/.local/share/Conty/nvidia

# Offset where the image is stored
offset=$((script_size+utils_size))

# Detect if the image is compressed with DwarFS or SquashFS
if [ "$(tail -c +$((offset+1)) "${script}" | head -c 6)" = "DWARFS" ]; then
	dwarfs_image=1
fi

dwarfs_cache_size="128M"
dwarfs_num_workers="2"

# These arguments are used to rebuild the image when using the self-update function
squashfs_comp_arguments=(-b 1M -comp zstd -Xcompression-level 19)
dwarfs_comp_arguments=(-l7 -C zstd:level=19 --metadata-compression null \
                       -S 22 -B 2 --order nilsimsa:255:60000:60000 \
                       --bloom-filter-size 11 -W 15 -w 3 --no-create-timestamp)

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
	if [ "${script_md5}" != "$(cat "${overlayfs_dir}"/current-image-version 2>/dev/null)" ]; then
		rm -rf "${overlayfs_dir}"/up "${overlayfs_dir}"/work \
		       "${nvidia_drivers_dir}"/current-nvidia-version
	fi

	mkdir -p "${overlayfs_dir}"/up
	mkdir -p "${overlayfs_dir}"/work
	mkdir -p "${overlayfs_dir}"/merged

	echo "${script_md5}" > "${overlayfs_dir}"/current-image-version

	if [ ! "$(ls "${overlayfs_dir}"/merged 2>/dev/null)" ]; then
		if command -v "${fuse_overlayfs}" 1>/dev/null; then
			if command -v fusermount3 1>/dev/null; then
				"${fuse_overlayfs}" -o squash_to_uid="$(id -u)" -o squash_to_gid="$(id -g)" -o lowerdir="${mount_point}",upperdir="${overlayfs_dir}"/up,workdir="${overlayfs_dir}"/work "${overlayfs_dir}"/merged
			else
				echo "Fuse3 is required for fuse-overlayfs"
			fi
		else
			echo "fuse-overlayfs not found"
		fi
	fi
}

nvidia_driver_handler () {
	if lsmod | grep nvidia 1>/dev/null || nvidia-smi 1>/dev/null; then
		if [ "$(ls /tmp/hostlibs/x86_64-linux-gnu/libGLX_nvidia.so.* 2>/dev/null)" ]; then
			nvidia_driver_version="$(basename /tmp/hostlibs/x86_64-linux-gnu/libGLX_nvidia.so.*.* | tail -c +18)"
		elif [ "$(ls /tmp/hostlibs/libGLX_nvidia.so.* 2>/dev/null)" ]; then
			nvidia_driver_version="$(basename /tmp/hostlibs/libGLX_nvidia.so.*.* | tail -c +18)"
		elif nvidia-smi 1>/dev/null; then
			nvidia_driver_version="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader)"
		elif modinfo nvidia &>/dev/null; then
			nvidia_driver_version="$(modinfo -F version nvidia 2>/dev/null)"
		fi
	else
		echo "Seems like your system has no Nvidia driver loaded"
		exit 1
	fi

	if [ "$(cat "${nvidia_drivers_dir}"/current-nvidia-version 2>/dev/null)" = "${nvidia_driver_version}" ]; then
		exit
	fi

	if [ -z "${nvidia_driver_version}" ]; then
		echo "Unable to determine the Nvidia driver version"
		exit 1
	fi

	OLD_PWD="${PWD}"

	mkdir -p "${nvidia_drivers_dir}"
	cd "${nvidia_drivers_dir}"

	echo "Found Nvidia driver ${nvidia_driver_version}"
	echo "Downloading the Nvidia driver ${nvidia_driver_version}, please wait..."

	# Try to download the driver from the default Nvidia URL
	driver_url="https://us.download.nvidia.com/XFree86/Linux-x86_64/${nvidia_driver_version}/NVIDIA-Linux-x86_64-${nvidia_driver_version}.run"
	curl -#Lo nvidia.run "${driver_url}"

	# If the previous download failed, get the URL from FlatHub repo
	if [ ! -s nvidia.run ]; then
		rm -f nvidia.run
		driver_url="https:$(curl -#Lo - "https://raw.githubusercontent.com/flathub/org.freedesktop.Platform.GL.nvidia/master/data/nvidia-${nvidia_driver_version}-i386.data" | cut -d ':' -f 6)"
		curl -#Lo nvidia.run "${driver_url}"
	fi

	if [ -s nvidia.run ]; then
		echo "Installing the Nvidia driver, please wait..."
		chmod +x nvidia.run
		./nvidia.run --target nvidia-driver -x &>/dev/null
		cd nvidia-driver || exit 1
		fakeroot ./nvidia-installer --silent --no-x-check --no-kernel-module &>/dev/null
		cd "${nvidia_drivers_dir}"
		echo "${nvidia_driver_version}" > current-nvidia-version
		rm -rf nvidia.run nvidia-driver
		echo "The driver has been installed"
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
if [ "${dwarfs_image}" = 1 ]; then
	if getconf _PHYS_PAGES &>/dev/null && getconf PAGE_SIZE &>/dev/null; then
		memory_size="$(($(getconf _PHYS_PAGES) * $(getconf PAGE_SIZE) / (1024 * 1024)))"

		if [ "${memory_size}" -ge 23000 ]; then
			dwarfs_cache_size="1024M"
		elif [ "${memory_size}" -ge 15000 ]; then
			dwarfs_cache_size="512M"
		elif [ "${memory_size}" -ge 7000 ]; then
			dwarfs_cache_size="256M"
		elif [ "${memory_size}" -ge 3000 ]; then
			dwarfs_cache_size="128M"
		elif [ "${memory_size}" -ge 1500 ]; then
			dwarfs_cache_size="64M"
		else
			dwarfs_cache_size="32M"
		fi
	fi

	if getconf _NPROCESSORS_ONLN &>/dev/null; then
		dwarfs_num_workers="$(getconf _NPROCESSORS_ONLN)"

		if [ "${dwarfs_num_workers}" -ge 8 ]; then
			dwarfs_num_workers=8
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
		mount_tool="${working_dir}"/utils/dwarfs"${fuse_version}"
		extraction_tool="${working_dir}"/utils/dwarfsextract
	else
		mount_tool="${working_dir}"/utils/squashfuse"${fuse_version}"
		extraction_tool="${working_dir}"/utils/unsquashfs
	fi

	bwrap="${working_dir}"/utils/bwrap
	fuse_overlayfs="${working_dir}"/utils/fuse-overlayfs

	if [ ! -f "${mount_tool}" ] || [ ! -f "${bwrap}" ]; then
		tail -c +$((script_size+1)) "${script}" | head -c "${utils_size}" | tar -C "${working_dir}" -zxf -

		if [ ! -f "${mount_tool}" ] || [ ! -f "${bwrap}" ]; then
			clear
			echo "The integrated utils were not extracted!"
			echo "Perhaps something is wrong with the integrated utils.tar.gz."

			exit 1
		fi

		chmod +x "${mount_tool}" 2>/dev/null
		chmod +x "${bwrap}" 2>/dev/null
		chmod +x "${extraction_tool}" 2>/dev/null
		chmod +x "${fuse_overlayfs}" 2>/dev/null
	fi
else
	if ! command -v bwrap 1>/dev/null; then
		echo "USE_SYS_UTILS is enabled, but bubblewrap is not installed!"
		echo "Please install it and run the script again."

		exit 1
	fi

	bwrap=bwrap
	fuse_overlayfs=fuse-overlayfs

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

if { [ "$1" = "-u" ] || [ "$1" = "-U" ]; } && [ -z "${script_is_symlink}" ]; then
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

	if command -v awk 1>/dev/null; then
		current_file_size="$(stat -c "%s" "${script}")"
		available_disk_space="$(df -P -B1 "${update_temp_dir}" | awk 'END {print $4}')"
		required_disk_space="$((current_file_size*7))"

		if [ "${available_disk_space}" -lt "${required_disk_space}" ]; then
			echo "Not enough free disk space"
			echo "You need at least $((required_disk_space/1024/1024)) MB of free space"
			exit 1
		fi
	fi

	tail -c +$((script_size+1)) "${script}" | head -c "${utils_size}" | tar -C "${update_temp_dir}" -zxf -

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
	unset DISABLE_NET
	unset HOME_DIR
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
		-i "${script}" -o sqfs -O "${offset}" --cache-size "${dwarfs_cache_size}" \
		--num-workers "${dwarfs_num_workers}"
	else
		tools_wrapper "${update_temp_dir}"/utils/unsquashfs \
		-o "${offset}" -user-xattrs -d sqfs "${script}"
	fi

	# Download or extract the utils.tar.gz and the init script depending
	# on what command line argument is used (-u or -U)
	clear
	if [ "$1" = "-U" ] && command -v curl 1>/dev/null; then
		if [ "${dwarfs_image}" = 1 ]; then
			utils="utils_dwarfs.tar.gz"
		else
			utils="utils.tar.gz"
		fi

		echo "Downloading the init script and the utils"
		curl -#LO "https://github.com/Kron4ek/Conty/raw/master/conty-start.sh"
		curl -#Lo utils.tar.gz "https://github.com/Kron4ek/Conty/raw/master/${utils}"
	fi

	if [ ! -s conty-start.sh ] || [ ! -s utils.tar.gz ]; then
		echo "Extracting the init script and the integrated utils"
		tail -c +$((script_size+1)) "${script}" | head -c "${utils_size}" > utils.tar.gz
		head -c "${script_size}" "${script}" > conty-start.sh
	fi

	# Check if there are additional arguments passed
	shift
	if [ -n "$1" ]; then
		packagelist=("$@")

		# Check which packages to install and which ones to remove
		for i in "${packagelist[@]}"; do
			if [ "$(echo "${i}" | head -c 1)" = "-" ]; then
				pkgsremove+=" ${i:1}"
			else
				pkgsinstall+=" ${i}"
			fi
		done

		export pkgsremove
		export pkgsinstall
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
ldconfig -C /etc/ld.so.cache
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
		-i sqfs -o image "${dwarfs_comp_arguments[@]}"
	else
		tools_wrapper "${update_temp_dir}"/utils/mksquashfs \
		sqfs image "${squashfs_comp_arguments[@]}"
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
	unset non_standard_home
	unset xsockets
	unset mount_opt

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
									--setenv "HOME" "${NEW_HOME}")
				;;
		esac
	fi

	if [ "${SANDBOX}" = 1 ]; then
		sandbox_params+=(--tmpfs /home \
						 --tmpfs /mnt \
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

		if [ -n "${SANDBOX_LEVEL}" ] && [ "${SANDBOX_LEVEL}" -ge 2 ]; then
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

		if [ -n "${SANDBOX_LEVEL}" ] && [ "${SANDBOX_LEVEL}" -ge 3 ]; then
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
			if [ -n "${SANDBOX_LEVEL}" ] && [ "${SANDBOX_LEVEL}" -ge 3 ]; then
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

	if [ "${NVIDIA_HANDLER}" = 1 ] && [ "$(ls "${overlayfs_dir}"/merged 2>/dev/null)" ]; then
		newroot_path="${overlayfs_dir}"/merged
	else
		newroot_path="${mount_point}"
	fi

	show_msg

	launch_wrapper "${bwrap}" \
			--bind "${newroot_path}" / \
			--dev-bind /dev /dev \
			--ro-bind /sys /sys \
			--bind-try /tmp /tmp \
			--proc /proc \
			--bind-try /home /home \
			--bind-try /mnt /mnt \
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
			--setenv PATH "${CUSTOM_PATH}" \
			"$@"
}

trap_exit () {
	rm -f "${working_dir}"/running_"${script_id}"

	if [ -d "${overlayfs_dir}"/merged ]; then
		fusermount"${fuse_version}" -uz "${overlayfs_dir}"/merged 2>/dev/null || \
		umount --lazy "${overlayfs_dir}"/merged 2>/dev/null
	fi

	if [ ! "$(ls "${working_dir}"/running_* 2>/dev/null)" ]; then
		fusermount"${fuse_version}" -uz "${mount_point}" 2>/dev/null || \
		umount --lazy "${mount_point}" 2>/dev/null

		if [ ! "$(ls "${mount_point}" 2>/dev/null)" ]; then
			rm -rf "${working_dir}"
		fi
	fi

	exit
}

trap 'trap_exit' EXIT

if [ "$(ls "${working_dir}"/running_* 2>/dev/null)" ] && [ ! "$(ls "${mount_point}" 2>/dev/null)" ]; then
	rm -f "${working_dir}"/running_*
fi

# Mount the image
mkdir -p "${mount_point}"

if [ "$(ls "${mount_point}" 2>/dev/null)" ] || \
	( [ "${dwarfs_image}" != 1 ] && launch_wrapper "${mount_tool}" -o offset="${offset}",ro "${script}" "${mount_point}" ) || \
	launch_wrapper "${mount_tool}" "${script}" "${mount_point}" -o offset="${offset}" -o debuglevel=error -o workers="${dwarfs_num_workers}" \
	-o mlock=try -o no_cache_image -o cache_files -o cachesize="${dwarfs_cache_size}"; then

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
		cd "${mount_point}"/usr/share/applications || exit 1

		unset variables
		vars="BASE_DIR DISABLE_NET DISABLE_X11 HOME_DIR SANDBOX SANDBOX_LEVEL USE_SYS_UTILS"
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

				while read -r line; do
					line_function="$(echo "${line}" | head -c 4)"

					if [ "${line_function}" = "Name" ]; then
						line="${line} (Conty)"
					elif [ "${line_function}" = "Exec" ]; then
						line="Exec=${variables}\"${script}\" $@ $(echo "${line}" | tail -c +6)"
					elif [ "${line_function}" = "TryE" ]; then
						continue
					fi

					echo $line >> "${applications_dir}"/"${f%.desktop}"-conty.desktop
				done < "${f}"
			fi
		done

		mkdir -p "${HOME}"/.local/share
		cp -nr "${mount_point}"/usr/share/icons "${HOME}"/.local/share 2>/dev/null

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

	if [ "${NVIDIA_HANDLER}" = 1 ]; then
		show_msg "Nvidia driver handler is enabled"

		mount_overlayfs
		mkdir -p "${nvidia_drivers_dir}"
		export -f nvidia_driver_handler
		run_bwrap --tmpfs /tmp --tmpfs /var --tmpfs /run \
		          --bind-try /usr/lib /tmp/hostlibs \
		          --bind-try /usr/lib64 /tmp/hostlibs \
		          --bind-try "${nvidia_drivers_dir}" "${nvidia_drivers_dir}" \
		          bash -c nvidia_driver_handler
	fi

	# If SANDBOX_LEVEL is 3, run Xephyr and openbox before running applications
	if [ "${SANDBOX}" = 1 ] && [ -n "${SANDBOX_LEVEL}" ] && [ "${SANDBOX_LEVEL}" -ge 3 ]; then
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
