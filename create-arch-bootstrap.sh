#!/usr/bin/env bash

# Dependencies: curl tar gzip grep sha256sum
# Root rights are required

if [ $EUID != 0 ]; then
	echo "Root rights are required!"

	exit 1
fi

if ! command -v curl 1>/dev/null; then
	echo "curl is required!"
	exit 1
fi

if ! command -v gzip 1>/dev/null; then
	echo "gzip is required!"
	exit 1
fi

if ! command -v grep 1>/dev/null; then
	echo "grep is required!"
	exit 1
fi

if ! command -v sha256sum 1>/dev/null; then
	echo "sha256sum is required!"
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
Server = https://geo.mirror.pkgbuild.com/\$repo/os/\$arch
Server = https://archlinux.uk.mirror.allworldit.com/archlinux/\$repo/os/\$arch
Server = https://mirror.osbeck.com/archlinux/\$repo/os/\$arch
Server = https://archlinux.mailtunnel.eu/\$repo/os/\$arch
Server = https://europe.mirror.pkgbuild.com/\$repo/os/\$arch
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
	mesa-utils vulkan-tools nvidia-prime libva-utils lib32-mesa-utils"

wine_pkgs="wine-staging winetricks-git wine-nine wineasio \
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
export packagelist="${audio_pkgs} ${video_pkgs} ${wine_pkgs} \
	base-devel nano ttf-dejavu ttf-liberation lutris steam firefox \
	mpv geany pcmanfm ppsspp dolphin-emu git wget htop qbittorrent \
	speedcrunch gpicview file-roller xorg-xwayland steam-native-runtime \
	meson mingw-w64-gcc gamemode lib32-gamemode cmake jre-openjdk \
	lxterminal steamtinkerlaunch mangohud lib32-mangohud qt6-wayland \
	wayland lib32-wayland qt5-wayland retroarch xorg-server-xephyr \
	openbox obs-studio gamehub minigalaxy legendary gamescope \
	pcsx2-git multimc5 yt-dlp bottles playonlinux minizip"

curl -#LO 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst'
curl -#LO 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'

if [ ! -s chaotic-keyring.pkg.tar.zst ] || [ ! -s chaotic-mirrorlist.pkg.tar.zst ]; then
	echo "Seems like Chaotic-AUR keyring or mirrorlist is currently unavailable"
	echo "Please try again later"
	exit 1
fi

bootstrap_urls=("mirror.osbeck.com" \
                "mirror.f4st.host" \
                "mirror.luzea.de")

echo "Downloading Arch Linux bootstrap"

for link in "${bootstrap_urls[@]}"; do
	curl -#LO "https://${link}/archlinux/iso/latest/archlinux-bootstrap-x86_64.tar.gz"
	curl -#LO "https://${link}/archlinux/iso/latest/sha256sums.txt"

	if [ -s sha256sums.txt ]; then
		grep bootstrap-x86_64 sha256sums.txt > sha256.txt

		echo "Verifying the integrity of the bootstrap"
		if sha256sum -c sha256.txt &>/dev/null; then
			bootstrap_is_good=1
			break
		fi
	fi

	echo "Download failed, trying again with different mirror"
done

if [ -z "${bootstrap_is_good}" ]; then
	echo "Bootstrap download failed or its checksum is incorrect"
	exit 1
fi

tar xf archlinux-bootstrap-x86_64.tar.gz
rm archlinux-bootstrap-x86_64.tar.gz sha256sums.txt sha256.txt

mount_chroot

generate_localegen

if command -v reflector 1>/dev/null; then
	reflector --protocol https --score 5 --sort rate --save mirrorlist
else
	generate_mirrorlist
fi

rm "${bootstrap}"/etc/locale.gen
mv locale.gen "${bootstrap}"/etc/locale.gen

rm "${bootstrap}"/etc/pacman.d/mirrorlist
mv mirrorlist "${bootstrap}"/etc/pacman.d/mirrorlist

{
	echo
	echo "[multilib]"
	echo "Include = /etc/pacman.d/mirrorlist"
} >> "${bootstrap}"/etc/pacman.conf

run_in_chroot pacman-key --init
echo "keyserver hkps://keyserver.ubuntu.com" >> "${bootstrap}"/etc/pacman.d/gnupg/gpg.conf
run_in_chroot pacman-key --populate archlinux

# Add Chaotic-AUR repo
run_in_chroot pacman-key --recv-key FBA220DFC880C036
run_in_chroot pacman-key --lsign-key FBA220DFC880C036

mv chaotic-keyring.pkg.tar.zst chaotic-mirrorlist.pkg.tar.zst "${bootstrap}"/opt
run_in_chroot pacman --noconfirm -U /opt/chaotic-keyring.pkg.tar.zst /opt/chaotic-mirrorlist.pkg.tar.zst
rm "${bootstrap}"/opt/chaotic-keyring.pkg.tar.zst "${bootstrap}"/opt/chaotic-mirrorlist.pkg.tar.zst

{
	echo
	echo "[chaotic-aur]"
	echo "Include = /etc/pacman.d/chaotic-mirrorlist"
} >> "${bootstrap}"/etc/pacman.conf

# The ParallelDownloads feature of pacman
# Speeds up packages installation, especially when there are many small packages to install
sed -i 's/#ParallelDownloads = 5/ParallelDownloads = 3/g' "${bootstrap}"/etc/pacman.conf

run_in_chroot pacman -Sy archlinux-keyring --noconfirm
run_in_chroot pacman -Su --noconfirm

date -u +"%d-%m-%Y %H:%M (DMY UTC)" > "${bootstrap}"/version

# These packages are required for the self-update feature to work properly
run_in_chroot pacman --noconfirm --needed -S base reflector squashfs-tools fakeroot

cat <<EOF > "${bootstrap}"/opt/install_packages.sh
echo "Checking if packages are present in the repos, please wait..."
for p in \${packagelist}; do
	if pacman -Sp "\${p}" &>/dev/null; then
		good_pkglist="\${good_pkglist} \${p}"
	else
		bad_pkglist="\${bad_pkglist} \${p}"
	fi
done

if [ -n "\${bad_pkglist}" ]; then
	echo \${bad_pkglist} > /opt/bad_pkglist.txt
fi

pacman --noconfirm --needed -S \${good_pkglist}
EOF

chmod +x "${bootstrap}"/opt/install_packages.sh
run_in_chroot bash /opt/install_packages.sh
rm "${bootstrap}"/opt/install_packages.sh

run_in_chroot locale-gen

# Generate a list of installed packages
run_in_chroot pacman -Qn > "${bootstrap}"/pkglist.x86_64.txt

unmount_chroot

# Clear pacman package cache
rm -f "${bootstrap}"/var/cache/pacman/pkg/*

# Create some empty files and directories
# This is needed for bubblewrap to be able to bind real files/dirs to them
# later in the conty-start.sh script
mkdir "${bootstrap}"/media
mkdir -p "${bootstrap}"/usr/share/steam/compatibilitytools.d
touch "${bootstrap}"/etc/asound.conf
touch "${bootstrap}"/etc/localtime
chmod 755 "${bootstrap}"/root

# Enable full font hinting
rm -f "${bootstrap}"/etc/fonts/conf.d/10-hinting-slight.conf
ln -s /usr/share/fontconfig/conf.avail/10-hinting-full.conf "${bootstrap}"/etc/fonts/conf.d

clear
echo "Done"

if [ -f "${bootstrap}"/opt/bad_pkglist.txt ]; then
	echo
	echo "These packages are not in the repos and have not been installed:"
	cat "${bootstrap}"/opt/bad_pkglist.txt
	rm "${bootstrap}"/opt/bad_pkglist.txt
fi
