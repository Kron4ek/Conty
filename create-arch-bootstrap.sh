#!/usr/bin/env bash

set -e

bold='\033[1m'
blue_bold="\033[1;34m"
clear='\033[0m'

stage() {
	if [ -n "$NESTING_LEVEL" ] && [ "$NESTING_LEVEL" -gt 0 ]; then
		printf "$blue_bold:%.0s$clear" $(seq "$NESTING_LEVEL")
	fi
	printf "$bold> %s$clear\n" "$@"
}
info() { NESTING_LEVEL=$((NESTING_LEVEL + 1)) stage "$@"; }

check_command_available() {
	for cmd in "$@"; do
		! command -v "$cmd" &>/dev/null && missing_executables+=("$cmd");
	done
	if [ "${#missing_executables[@]}" -ne 0 ]; then
		info "Following commands are required: ${missing_executables[*]}"
		exit 1
	fi
}

# Script is reexecuted from within chroot with INSIDE_BOOTSTRAP set to perform bootstrap
if [ -z "$INSIDE_BOOTSTRAP" ]; then
	source settings.sh
	NESTING_LEVEL=0
	stage "Preparing bootstrap"

	check_command_available curl tar unshare

	script_dir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
	build_dir="$script_dir/$BUILD_DIR"
	bootstrap="$build_dir"/root.x86_64
	mkdir -p "$build_dir"
	cd "$build_dir"

	info "Downloading Arch Linux bootstrap sha256sum from $BOOTSTRAP_SHA256SUM_FILE_URL"
	curl -#LO "$BOOTSTRAP_SHA256SUM_FILE_URL"
	for link in "${BOOTSTRAP_DOWNLOAD_URLS[@]}"; do
		info "Downloading Arch Linux archive bootstrap from $link"
		curl -#LO "$link"

		info "Verifying the integrity of the bootstrap"
		if sha256sum --ignore-missing -c sha256sums.txt &>/dev/null; then
			bootstrap_is_good=1
			break 1
		fi
		info "Download failed, trying again with different mirror"
	done
	if [ -z "$bootstrap_is_good" ]; then
		info "Bootstrap download failed or its checksum is incorrect"
		exit 1
	fi

	run_unshared() {
		unshare --uts --ipc --user --mount --map-auto --map-root-user --pid --fork -- "$@"
	}

	info "Removing previous bootstrap"
	run_unshared rm -rf "$bootstrap"
	info "Extracting bootstrap from archive"
	run_unshared tar xf archlinux-bootstrap-x86_64.tar.zst

	# shellcheck disable=2317
	prepare_bootstrap() {
		set -e
		mount --bind "$bootstrap"/ "$bootstrap"/
		mount -t proc proc "$bootstrap"/proc
		mount -o ro --rbind /dev "$bootstrap"/dev
		mount none -t devpts "$bootstrap"/dev/pts
		mount none -t tmpfs "$bootstrap"/dev/shm
		if [ -d /var/cache/pacman/pkg ]; then
			mkdir -p "$bootstrap"/var/cache/pacman/host_pkg
			mount -o ro --bind /var/cache/pacman/pkg "$bootstrap"/var/cache/pacman/host_pkg
		fi
		rm -f "$bootstrap"/etc/resolv.conf
		cp /etc/resolv.conf "$bootstrap"/etc/resolv.conf
		# Default machine-id is unitialized and systemd-tmpfiles throws some warnings
		# about it so initialize it to a value here
		rm -r "$bootstrap"/etc/machine-id
		tr -d '-' < /proc/sys/kernel/random/uuid \
			| install -Dm0444 /dev/fd/0 "$bootstrap"/etc/machine-id
		mkdir -p "$bootstrap"/opt/conty
		install -Dm755 -t "$bootstrap"/opt/conty -- "$script_dir"/*.sh
	}
	# shellcheck disable=2317
	run_bootstrap() {
		exec chroot "$bootstrap" /usr/bin/env -i \
			   USER='root' HOME='/root' NESTING_LEVEL=2 INSIDE_BOOTSTRAP=1 \
			   /opt/conty/create-arch-bootstrap.sh
	}

	export bootstrap script_dir
	export -f prepare_bootstrap run_bootstrap
	info "Entering bootstrap namespace"
	if run_unshared bash -c "prepare_bootstrap; run_bootstrap"; then
		info "Done!"
		exit
	else
		info "Error occured while building bootstrap"
		exit 1
	fi
fi
# From here on we are running inside bootstrap
# Populate PATH and LANG environment variables with defaults
source /etc/profile

# shellcheck source=settings.sh
source /opt/conty/settings.sh

install_aur_packages() {
	useradd -m aurbuilder
	echo 'aurbuilder ALL=(ALL) NOPASSWD: /usr/bin/pacman' \
		| install -Dm0440 /dev/fd/0 /etc/sudoers.d/aurbuilder

	pushd /home/aurbuilder &>/dev/null
	if ! pacman -Q yay-bin &>/dev/null; then
		if [ -n "$ENABLE_CHAOTIC_AUR" ]; then
			info "Installing base-devel and yay"
			pacman --noconfirm --needed -S base-devel yay
		else
			info "Installing base-devel"
			pacman --noconfirm --needed -S base-devel
			info "Building yay-bin"
			sudo -u aurbuilder -- curl -LO 'https://aur.archlinux.org/cgit/aur.git/snapshot/yay-bin.tar.gz'
			sudo -u aurbuilder -- tar -xf yay-bin.tar.gz
			pushd yay-bin &>/dev/null
			sudo -u aurbuilder -- makepkg --noconfirm -sri
			popd &>/dev/null
		fi
	fi
	for p in "$@"; do
		info "Building and installing $p"
		sudo -u aurbuilder -- yay --needed --removemake --noconfirm -S "$p"
	done

	info "Cleaning up"
	popd &>/dev/null
	# GPG leaves hanging processes when package with signing keys is installed
	pkill -SIGKILL -u aurbuilder || true
	userdel -r aurbuilder &>/dev/null
	rm /etc/sudoers.d/aurbuilder
}

stage "Generating locales"
printf '%s\n' "${LOCALES[@]}" > /etc/locale.gen
locale-gen

stage "Setting up default mirrorlist"
printf 'Server = %s\n' "${DEFAULT_MIRRORS[@]}" > /etc/pacman.d/mirrorlist

stage "Setting up pacman config"
if [ "${#AUR_PACKAGES[@]}" -ne 0 ]; then
	info "Disabling debug option in makepkg"
	sed -i 's/\(OPTIONS=(.*\)\(debug.*)\)/\1!\2/' /etc/makepkg.conf
fi
info "Enabling fetch of packages from host pacman cache"
sed -i 's!#CacheDir.*!CacheDir = /var/cache/pacman/pkg /var/cache/pacman/host_pkg!' /etc/pacman.conf
info "Disabling extraction of nvidia firmware and man pages"
sed -i 's!#NoExtract.*!NoExtract = usr/lib/firmware/nvidia/\* usr/share/man/\*!' /etc/pacman.conf
info "Enabling multilib repository"
echo '
[multilib]
Include = /etc/pacman.d/mirrorlist' >> /etc/pacman.conf
pacman --noconfirm -Sy

stage "Setting up pacman keyring"
pacman-key --init
pacman-key --populate archlinux
pacman --noconfirm -Sy archlinux-keyring

if [ -n "$ENABLE_CHAOTIC_AUR" ]; then
	stage "Setting up Chaotic-AUR"
	chaotic_aur_key='3056513887B78AEB'
	pacman-key --recv-key "$chaotic_aur_key" --keyserver keyserver.ubuntu.com
	pacman-key --lsign-key "$chaotic_aur_key"
	pacman --noconfirm -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'
	echo '
[chaotic-aur]
Include = /etc/pacman.d/chaotic-mirrorlist' >> /etc/pacman.conf
	pacman --noconfirm -Sy
fi

if [ -n "$ENABLE_ALHP_REPO" ]; then
	stage "Setting up ALHP"
	if [ -n "$ENABLE_CHAOTIC_AUR" ]; then
		pacman --noconfirm --needed -Sy alhp-keyring alhp-mirrorlist
	else
		install_aur_packages alhp-keyring alhp-mirrorlist
	fi
	sed -i "s/#\[multilib\]/#/" /etc/pacman.conf
	sed -i "s/\[core\]/\[core-x86-64-v$ALHP_FEATURE_LEVEL\]\nInclude = \/etc\/pacman.d\/alhp-mirrorlist\n\n\[extra-x86-64-v$ALHP_FEATURE_LEVEL\]\nInclude = \/etc\/pacman.d\/alhp-mirrorlist\n\n\[core\]/" /etc/pacman.conf
	sed -i "s/\[multilib\]/\[multilib-x86-64-v$ALHP_FEATURE_LEVEL\]\nInclude = \/etc\/pacman.d\/alhp-mirrorlist\n\n\[multilib\]/" /etc/pacman.conf
	pacman --noconfirm -Sy
fi

stage "Upgrading base system"
pacman --noconfirm -Syu

stage "Installing base packages"
pacman --noconfirm --needed -S base reflector squashfs-tools fakeroot

stage "Generating mirrorlist using reflector"
reflector --connection-timeout 10 --download-timeout 10 --protocol https --score 10 --sort rate --save /etc/pacman.d/mirrorlist

if [ "${#PACKAGES[@]}" -ne 0 ]; then
	stage "Installing packages defined in settings.sh"
	info "Checking if packages are present in the repos"
	declare -a missing_packages
	mapfile -t missing_packages < <(comm -23 \
										 <(printf '%s\n' "${PACKAGES[@]}" | sort -u) \
										 <(pacman -Slq | sort -u))
	if [ "${#missing_packages[@]}" -ne 0 ]; then
		info "Following packages are not available in repository:" "${missing_packages[@]}"
		exit 1
	fi
	for _ in {1..10}; do
		pacman --noconfirm --needed -S "${PACKAGES[@]}"
		exit_code="$?"
		[ "$exit_code" -eq 0 ] && break
		# Received interrupt signal
		[ "$exit_code" -gt 128 ] && exit "$exit_code"
	done
fi

if [ "${#AUR_PACKAGES[@]}" -ne 0 ]; then
	stage "Installing AUR packages defined in settings.sh"
	# Parsing json with grep is ugly it but saves us from installing devel packages unnecesarily
	info "Checking if packages are present in AUR"
	declare -a grep_arguments
	for pkg in $(printf '%s\n' "${AUR_PACKAGES[@]}" | sort -u); do
		grep_arguments+=(-e "\"Name\":\"$pkg\"")
	done
	declare -a missing_packages
	mapfile -t missing_packages < <(comm -23 \
										 <(printf '%s\n' "${AUR_PACKAGES[@]}" | sort -u) \
										 <(curl -s 'https://aur.archlinux.org/packages-meta-v1.json.gz' | gunzip |
											   grep -o "${grep_arguments[@]}" | sed 's/".*":"\(.*\)"/\1/g' | sort -u))
	if [ "${#missing_packages[@]}" -ne 0 ]; then
		info "Following packages are not available in AUR:" "${missing_packages[@]}"
		exit 1
	fi
	install_aur_packages "${AUR_PACKAGES[@]}"
fi

stage "Clearing pacman cache"
yes y | pacman -Scc &>/dev/null

stage "Enabling font hinting"
mkdir -p /etc/fonts/conf.d
rm -f /etc/fonts/conf.d/10-hinting-slight.conf
ln -s /usr/share/fontconfig/conf.avail/10-hinting-full.conf /etc/fonts/conf.d

stage "Creating files and directories for application compatibility"
# Create some empty files and directories
# This is needed for bubblewrap to be able to bind real files/dirs to them
# later in the conty-start.sh script
mkdir /media
mkdir /initrd
mkdir -p /usr/share/steam/compatibilitytools.d
touch /etc/asound.conf
touch /etc/localtime
chmod 755 /root

stage "Generating install info"
info "Writing list of all installed packages to /pkglist.x86_64.txt"
pacman -Q > /pkglist.x86_64.txt
info "Writing list of licenses for installed packages to /pkglicenses.txt"
pacman -Qi | grep -E '^Name|Licenses' | cut -d ":" -f 2 | paste -d ' ' - - > /pkglicenses.txt
info "Writing build date to /version"
date -u +"%d-%m-%Y %H:%M (DMY UTC)" > /version
