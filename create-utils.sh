#!/usr/bin/env bash

# General build dependencies: gawk grep lz4 zstd curl gcc make autoconf
# 	libtool pkgconf libcap fuse2 (or fuse3) lzo xz zlib findutils musl
#	kernel-headers-musl sed
#
# Dwarfs build dependencies: fuse2 (or fuse3) openssl jemalloc
# 	xxhash boost lz4 xz zstd libarchive libunwind google-glod gtest fmt
#	gflags double-conversion cmake ruby-ronn libevent libdwarf git utf8cpp
#
# Dwarfs compilation is optional and disabled by default.

script_dir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

# Set to true to compile dwarfs instead of squashfuse
build_dwarfs="${build_dwarfs:-false}"

squashfuse_version="0.5.2"
bwrap_version="0.11.0"
lz4_version="1.10.0"
zstd_version="1.5.7"
squashfs_tools_version="4.6.1"
unionfs_fuse_version="3.3"
busybox_version="1.36.1"
bash_version="5.2.37"

export CC=clang
export CXX=clang++

export CFLAGS="-O3 -flto"
export CXXFLAGS="${CFLAGS}"
export LDFLAGS="-Wl,-O1,--sort-common,--as-needed"

mkdir -p "${script_dir}"/build-utils
cd "${script_dir}"/build-utils || exit 1

curl -#Lo lz4.tar.gz https://github.com/lz4/lz4/archive/refs/tags/v${lz4_version}.tar.gz
curl -#Lo zstd.tar.gz https://github.com/facebook/zstd/archive/refs/tags/v${zstd_version}.tar.gz
curl -#Lo bwrap.tar.gz https://github.com/containers/bubblewrap/archive/refs/tags/v${bwrap_version}.tar.gz
curl -#Lo unionfs-fuse.tar.gz https://github.com/rpodgorny/unionfs-fuse/archive/refs/tags/v${unionfs_fuse_version}.tar.gz
curl -#Lo busybox.tar.bz2 https://busybox.net/downloads/busybox-${busybox_version}.tar.bz2
curl -#Lo bash.tar.gz https://ftp.gnu.org/gnu/bash/bash-${bash_version}.tar.gz
cp "${script_dir}"/init.c init.c

tar xf lz4.tar.gz
tar xf zstd.tar.gz
tar xf bwrap.tar.gz
tar xf unionfs-fuse.tar.gz
tar xf busybox.tar.bz2
tar xf bash.tar.gz

if [ "${build_dwarfs}" != "true" ]; then
	curl -#Lo squashfuse.tar.gz https://github.com/vasi/squashfuse/archive/refs/tags/${squashfuse_version}.tar.gz
	curl -#Lo sqfstools.tar.gz https://github.com/plougher/squashfs-tools/archive/refs/tags/${squashfs_tools_version}.tar.gz

	tar xf squashfuse.tar.gz
	tar xf sqfstools.tar.gz
fi

cd bubblewrap-"${bwrap_version}" || exit 1
meson -Dselinux=disabled -Dman=disabled build
DESTDIR="${script_dir}"/build-utils/bin meson install -C build

cd ../unionfs-fuse-"${unionfs_fuse_version}" || exit 1
mkdir build-fuse3
cd build-fuse3
cmake ../ -DCMAKE_BUILD_TYPE=Release
make -j"$(nproc)" DESTDIR="${script_dir}"/build-utils/bin install
mv "${script_dir}"/build-utils/bin/usr/local/bin/unionfs "${script_dir}"/build-utils/bin/usr/local/bin/unionfs3
mkdir ../build-fuse2
cd ../build-fuse2
cmake ../ -DCMAKE_BUILD_TYPE=Release -DWITH_LIBFUSE3=FALSE
make -j"$(nproc)" DESTDIR="${script_dir}"/build-utils/bin install

cd ../../lz4-"${lz4_version}" || exit 1
make -j"$(nproc)" DESTDIR="${script_dir}"/build-utils/bin install

cd ../zstd-"${zstd_version}" || exit 1
ZSTD_LEGACY_SUPPORT=0 HAVE_ZLIB=0 HAVE_LZMA=0 HAVE_LZ4=0 BACKTRACE=0 make -j"$(nproc)" DESTDIR="${script_dir}"/build-utils/bin install

cd ../busybox-${busybox_version} || exit 1
make defconfig
sed -i 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/g' .config
make CC=musl-gcc -j"$(nproc)"

cd ../bash-${bash_version}
curl -#Lo bash.patch "https://raw.githubusercontent.com/robxu9/bash-static/master/custom/bash-musl-strtoimax-debian-1023053.patch"
patch -Np1 < ./bash.patch
CFLAGS="${CFLAGS} -std=gnu17 -Wno-error=implicit-function-declaration -static" CC=musl-gcc ./configure --without-bash-malloc
autoconf -f
CFLAGS="${CFLAGS} -std=gnu17 -Wno-error=implicit-function-declaration -static" CC=musl-gcc ./configure --without-bash-malloc
CFLAGS="${CFLAGS} -std=gnu17 -Wno-error=implicit-function-declaration -static" CC=musl-gcc make -j"$(nproc)"

if [ "${build_dwarfs}" != "true" ]; then
	cd ../squashfuse-"${squashfuse_version}" || exit 1
	./autogen.sh
	./configure
	make -j"$(nproc)" DESTDIR="${script_dir}"/build-utils/bin install

	cd ../squashfs-tools-"${squashfs_tools_version}"/squashfs-tools || exit 1
	CC=gcc CXX=g++ make -j"$(nproc)" GZIP_SUPPORT=1 XZ_SUPPORT=1 LZO_SUPPORT=1 LZMA_XZ_SUPPORT=1 \
			LZ4_SUPPORT=1 ZSTD_SUPPORT=1 XATTR_SUPPORT=1
	CC=gcc CXX=g++ make INSTALL_DIR="${script_dir}"/build-utils/bin/usr/local/bin install
fi

cd "${script_dir}"/build-utils || exit 1
mkdir utils
mv bin/usr/local/bin/bwrap utils
mv bin/usr/local/bin/squashfuse utils
mv bin/usr/local/bin/squashfuse_ll utils
mv bin/usr/local/bin/mksquashfs utils
mv bin/usr/local/bin/unsquashfs utils
mv bin/usr/local/bin/unionfs3 utils
mv bin/usr/local/bin/unionfs utils
mv bin/usr/local/lib/liblz4.so."${lz4_version}" utils/liblz4.so.1
mv bin/usr/local/lib/libzstd.so."${zstd_version}" utils/libzstd.so.1
mv bin/usr/local/lib/libfuseprivate.so.0.0.0 utils/libfuseprivate.so.0
mv bin/usr/local/lib/libsquashfuse.so.0.0.0 utils/libsquashfuse.so.0
mv "${script_dir}"/build-utils/busybox-${busybox_version}/busybox utils
mv "${script_dir}"/build-utils/bash-${bash_version}/bash utils
mv "${script_dir}"/build-utils/init utils

if ! ldd utils/squashfuse | grep -q libfuse.so.2; then
	mv utils/squashfuse utils/squashfuse3
	mv utils/squashfuse_ll utils/squashfuse3_ll
fi

if [ "${build_dwarfs}" = "true" ]; then
	git clone https://github.com/mhx/dwarfs.git --recursive

	cd dwarfs || exit 1
	mkdir build
	cd build || exit 1
	cmake .. -DCMAKE_BUILD_TYPE=Release \
			-DPREFER_SYSTEM_ZSTD=ON -DPREFER_SYSTEM_XXHASH=ON \
			-DPREFER_SYSTEM_GTEST=ON -DPREFER_SYSTEM_LIBFMT=ON

	make -j"$(nproc)"
	make DESTDIR="${script_dir}"/build-utils/bin install

	cd "${script_dir}"/build-utils || exit 1
	mv bin/usr/local/sbin/dwarfs2 utils/dwarfs
	mv bin/usr/local/sbin/dwarfs utils/dwarfs3
	mv bin/usr/local/bin/mkdwarfs utils
	mv bin/usr/local/bin/dwarfsextract utils
fi

mapfile -t libs_list < <(ldd utils/* | awk '/=> \// {print $3}')

for i in "${libs_list[@]}"; do
	if [ ! -f utils/"$(basename "${i}")" ]; then
		cp -L "${i}" utils
	fi
done

if [ ! -f utils/ld-linux-x86-64.so.2 ]; then
    cp -L /lib64/ld-linux-x86-64.so.2 utils
fi

find utils -type f -exec strip --strip-unneeded {} \; 2>/dev/null

init_program_size=50000
conty_script_size="$(($(stat -c%s "${script_dir}"/conty-start.sh)+2000))"
bash_size="$(stat -c%s utils/bash)"

sed -i "s/#define SCRIPT_SIZE 0/#define SCRIPT_SIZE ${conty_script_size}/g" init.c
sed -i "s/#define BASH_SIZE 0/#define BASH_SIZE ${bash_size}/g" init.c
sed -i "s/#define PROGRAM_SIZE 0/#define PROGRAM_SIZE ${init_program_size}/g" init.c

musl-gcc -o init -static init.c
strip --strip-unneeded init

padding_size="$((init_program_size-$(stat -c%s init)))"

if [ "${padding_size}" -gt 0 ]; then
	dd if=/dev/zero of=padding bs=1 count="${padding_size}" &>/dev/null
	cat init padding > init_new
	rm -f init padding
	mv init_new init
fi

mv init utils

cat <<EOF > utils/info
bubblewrap ${bwrap_version}
unionfs-fuse ${unionfs_fuse_version}
busybox ${busybox_version}
bash ${bash_version}
lz4 ${lz4_version}
zstd ${zstd_version}
EOF

if [ "${build_dwarfs}" = "true" ]; then
	echo "dwarfs $(git -C dwarfs rev-parse --short HEAD)-git" >> utils/info
	utils="utils_dwarfs.tar.gz"
else
	echo "squashfuse ${squashfuse_version}" >> utils/info
	echo "squashfs-tools ${squashfs_tools_version}" >> utils/info
	utils="utils.tar.gz"
fi

tar -zcf "${utils}" utils
mv "${script_dir}"/"${utils}" "${script_dir}"/"${utils}".old
mv "${utils}" "${script_dir}"
cd "${script_dir}" || exit 1
rm -rf build-utils

clear
echo "Done!"
