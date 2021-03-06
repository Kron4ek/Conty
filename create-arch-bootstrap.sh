#!/usr/bin/env bash

# Dependencies: wget tar gzip
# Root rights are required

if [ $EUID != 0 ]; then
	echo "Root rights are required!"

	exit 1
fi

if ! command -v wget 1>/dev/null; then
	echo "wget is required!"
	exit 1
fi

if ! command -v gzip 1>/dev/null; then
	echo "gzip is required!"
	exit 1
fi

script_dir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

mount_chroot () {
	# First unmount just in case
	umount -Rl "${bootstrap}"

	mount --bind "${bootstrap}" "${bootstrap}"
	mount -t proc /proc "${bootstrap}"/proc
	mount --bind /sys "${bootstrap}"/sys
	mount --make-rslave "${bootstrap}"/sys
	mount --bind /dev "${bootstrap}"/dev
	mount --bind /dev/pts "${bootstrap}"/dev/pts
	mount --bind /dev/shm "${bootstrap}"/dev/shm
	mount --make-rslave "${bootstrap}"/dev

	rm -f "${bootstrap}"/etc/resolv.conf
	cp /etc/resolv.conf "${bootstrap}"/etc/resolv.conf

	mkdir -p "${bootstrap}"/run/shm
}

unmount_chroot () {
	umount -l "${bootstrap}"
	umount "${bootstrap}"/proc
	umount "${bootstrap}"/sys
	umount "${bootstrap}"/dev/pts
	umount "${bootstrap}"/dev/shm
	umount "${bootstrap}"/dev
}

run_in_chroot () {
	chroot "${bootstrap}" /usr/bin/env LANG=en_US.UTF-8 TERM=xterm PATH="/bin:/sbin:/usr/bin:/usr/sbin" "$@"
}

generate_localegen () {
	cat <<EOF > locale.gen
ar_EG.UTF-8 UTF-8
en_US.UTF-8 UTF-8
en_GB.UTF-8 UTF-8
en_CA.UTF-8 UTF-8
es_MX.UTF-8 UTF-8
zh_CN.UTF-8 UTF-8
fr_FR.UTF-8 UTF-8
ru_RU.UTF-8 UTF-8
ru_UA.UTF-8 UTF-8
es_ES.UTF-8 UTF-8
de_DE.UTF-8 UTF-8
pt_BR.UTF-8 UTF-8
it_IT.UTF-8 UTF-8
ja_JP.UTF-8 UTF-8
bg_BG.UTF-8 UTF-8
pl_PL.UTF-8 UTF-8
da_DK.UTF-8 UTF-8
ko_KR.UTF-8 UTF-8
tr_TR.UTF-8 UTF-8
hu_HU.UTF-8 UTF-8
cs_CZ.UTF-8 UTF-8
bn_IN UTF-8
EOF
}

generate_mirrorlist () {
	cat <<EOF > mirrorlist
Server = https://mirror.pkgbuild.com/\$repo/os/\$arch
Server = https://mirror.f4st.host/archlinux/\$repo/os/\$arch
Server = https://arch.jensgutermuth.de/\$repo/os/\$arch
Server = https://mirror.pseudoform.org/\$repo/os/\$arch
Server = https://mirror.chaoticum.net/arch/\$repo/os/\$arch
EOF
}

cd "${script_dir}" || exit 1

bootstrap="${script_dir}"/root.x86_64

# Package groups

audio_pkgs="alsa-lib lib32-alsa-lib alsa-plugins lib32-alsa-plugins libpulse \
	lib32-libpulse jack2 lib32-jack2 alsa-tools alsa-utils"

video_pkgs="mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon \
	vulkan-intel lib32-vulkan-intel nvidia-utils lib32-nvidia-utils \
	vulkan-icd-loader lib32-vulkan-icd-loader vulkan-mesa-layers \
	lib32-vulkan-mesa-layers libva-mesa-driver lib32-libva-mesa-driver \
	libva-intel-driver lib32-libva-intel-driver intel-media-driver \
	mesa-demos vulkan-tools nvidia-prime libva-utils"

wine_pkgs="wine-tkg-staging-fsync-git winetricks-git wine-nine wineasio \
	giflib lib32-giflib libpng lib32-libpng libldap lib32-libldap \
	gnutls lib32-gnutls mpg123 lib32-mpg123 openal lib32-openal \
	v4l-utils lib32-v4l-utils libpulse lib32-libpulse alsa-plugins \
	lib32-alsa-plugins alsa-lib lib32-alsa-lib libjpeg-turbo \
	lib32-libjpeg-turbo libxcomposite lib32-libxcomposite libxinerama \
	lib32-libxinerama libxslt lib32-libxslt libva lib32-libva gtk3 \
	lib32-gtk3 vulkan-icd-loader lib32-vulkan-icd-loader sdl2 lib32-sdl2 \
	vkd3d lib32-vkd3d libgphoto2 ffmpeg gst-plugins-good gst-plugins-bad \
	gst-plugins-ugly gst-plugins-base lib32-gst-plugins-good lib32-gst-plugins-base"

# List of packages to install
# You can remove packages that you don't need
# Besides packages from the official Arch repos, you can list
# packages from the Chaotic-AUR repo here
packagelist="${audio_pkgs} ${video_pkgs} ${wine_pkgs} \
	base-devel nano ttf-dejavu ttf-liberation lutris steam firefox \
	mpv geany pcmanfm ppsspp dolphin-emu git wget htop qbittorrent \
	speedcrunch gpicview qpdfview file-roller xorg-xwayland steam-native-runtime \
	meson mingw-w64-gcc gamemode lib32-gamemode cmake jre-openjdk \
	playonlinux lxterminal steamtinkerlaunch mangohud lib32-mangohud \
	zsync2-git wayland lib32-wayland qt5-wayland retroarch python-magic-ahupp"

current_release="$(wget -q "https://archlinux.org/download/" -O - | grep "Current Release" | tail -c -16 | head -c +10)"

echo "Downloading ${current_release} release"
wget -q --show-progress -O arch.tar.gz "https://mirror.rackspace.com/archlinux/iso/${current_release}/archlinux-bootstrap-${current_release}-x86_64.tar.gz"
tar xf arch.tar.gz
rm arch.tar.gz

mount_chroot

generate_localegen

if command -v reflector 1>/dev/null; then
	reflector --protocol https --score 5 --sort rate --save mirrorlist
else
	generate_mirrorlist
fi

rm "${bootstrap}"/etc/locale.gen
cp locale.gen "${bootstrap}"/etc/locale.gen
rm locale.gen

rm "${bootstrap}"/etc/pacman.d/mirrorlist
cp mirrorlist "${bootstrap}"/etc/pacman.d/mirrorlist
rm mirrorlist

echo >> "${bootstrap}"/etc/pacman.conf
echo "[multilib]" >> "${bootstrap}"/etc/pacman.conf
echo "Include = /etc/pacman.d/mirrorlist" >> "${bootstrap}"/etc/pacman.conf

run_in_chroot pacman-key --init
echo "keyserver hkps://keyserver.ubuntu.com" >> "${bootstrap}"/etc/pacman.d/gnupg/gpg.conf
run_in_chroot pacman-key --populate archlinux

# Add Chaotic-AUR repo
run_in_chroot pacman-key --recv-key 3056513887B78AEB
run_in_chroot pacman-key --lsign-key 3056513887B78AEB
run_in_chroot pacman --noconfirm -U 'https://mirrors.fossho.st/garuda/repos/chaotic-aur/x86_64/chaotic-keyring-20210617-1-any.pkg.tar.zst'
run_in_chroot pacman --noconfirm -U 'https://mirrors.fossho.st/garuda/repos/chaotic-aur/x86_64/chaotic-mirrorlist-20210716-1-any.pkg.tar.zst'

echo >> "${bootstrap}"/etc/pacman.conf
echo "[chaotic-aur]" >> "${bootstrap}"/etc/pacman.conf
echo "Include = /etc/pacman.d/chaotic-mirrorlist" >> "${bootstrap}"/etc/pacman.conf

# Enable ParallelDownloads feature of pacman
sed -i 's/#ParallelDownloads = 5/ParallelDownloads = 5/g' "${bootstrap}"/etc/pacman.conf

run_in_chroot pacman -Syu --noconfirm

# These packages are required for the self-update feature to work properly
run_in_chroot pacman --noconfirm --needed -S base reflector squashfs-tools fakeroot

run_in_chroot pacman --noconfirm --needed -S ${packagelist}

run_in_chroot locale-gen

unmount_chroot

# Clear pacman package cache
rm -f "${bootstrap}"/var/cache/pacman/pkg/*

# Create some empty files and directories
# This is needed for bubblewrap to be able to bind real files/dirs to them
# later in the conty-start.sh script
mkdir "${bootstrap}"/media
touch "${bootstrap}"/etc/asound.conf
touch "${bootstrap}"/etc/localtime
chmod 755 "${bootstrap}"/root

# Enable full font hinting
rm -f "${bootstrap}"/etc/fonts/conf.d/10-hinting-slight.conf
ln -s /usr/share/fontconfig/conf.avail/10-hinting-full.conf "${bootstrap}"/etc/fonts/conf.d

clear
echo "Done"
