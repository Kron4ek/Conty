#!/usr/bin/env bash

# General build dependencies: gawk grep lz4 zstd curl gcc make autoconf
# 	libtool pkgconf libcap fuse2 (or fuse3) lzo xz zlib findutils
#
# Dwarfs build dependencies: fuse2 (or fuse3) openssl jemalloc
# 	xxhash boost lz4 xz zstd libarchive libunwind google-glod gtest fmt
#	gflags double-conversion cmake ruby-ronn libevent libdwarf git
#
# Dwarfs compilation is optional and disabled by default.

script_dir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

# Set to true to compile dwarfs instead of squashfuse
build_dwarfs="false"

squashfuse_version="0.1.105"
bwrap_version="0.7.0"
lz4_version="1.9.4"
zstd_version="1.5.4"
squashfs_tools_version="4.5.1"

export CC=gcc
export CXX=g++

export CFLAGS="-O2"
export CXXFLAGS="${CFLAGS}"
export LDFLAGS="-Wl,-O1,--sort-common,--as-needed"

mkdir -p "${script_dir}"/build-utils
cd "${script_dir}"/build-utils || exit 1

curl -#Lo lz4.tar.gz https://github.com/lz4/lz4/archive/refs/tags/v${lz4_version}.tar.gz
curl -#Lo zstd.tar.gz https://github.com/facebook/zstd/archive/refs/tags/v${zstd_version}.tar.gz
curl -#Lo bwrap.tar.gz https://github.com/containers/bubblewrap/archive/refs/tags/v${bwrap_version}.tar.gz

tar xf lz4.tar.gz
tar xf zstd.tar.gz
tar xf bwrap.tar.gz

if [ "${build_dwarfs}" != "true" ]; then
	curl -#Lo squashfuse.tar.gz https://github.com/vasi/squashfuse/archive/refs/tags/${squashfuse_version}.tar.gz
	curl -#Lo sqfstools.tar.gz https://github.com/plougher/squashfs-tools/archive/refs/tags/${squashfs_tools_version}.tar.gz

	tar xf squashfuse.tar.gz
	tar xf sqfstools.tar.gz
fi

cd bubblewrap-"${bwrap_version}" || exit 1
./autogen.sh
./configure --disable-selinux --disable-man
make -j"$(nproc)" DESTDIR="${script_dir}"/build-utils/bin install

cd ../lz4-"${lz4_version}" || exit 1
make -j"$(nproc)" DESTDIR="${script_dir}"/build-utils/bin install

cd ../zstd-"${zstd_version}" || exit 1
ZSTD_LEGACY_SUPPORT=0 HAVE_ZLIB=0 HAVE_LZMA=0 HAVE_LZ4=0 BACKTRACE=0 make -j"$(nproc)" DESTDIR="${script_dir}"/build-utils/bin install

if [ "${build_dwarfs}" != "true" ]; then
	cd ../squashfuse-"${squashfuse_version}" || exit 1
	./autogen.sh
	./configure
	make -j"$(nproc)" DESTDIR="${script_dir}"/build-utils/bin install

	cd ../squashfs-tools-"${squashfs_tools_version}"/squashfs-tools || exit 1
	make -j"$(nproc)" GZIP_SUPPORT=1 XZ_SUPPORT=1 LZO_SUPPORT=1 LZMA_XZ_SUPPORT=1 \
			LZ4_SUPPORT=1 ZSTD_SUPPORT=1 XATTR_SUPPORT=1
	make INSTALL_DIR="${script_dir}"/build-utils/bin/usr/local/bin install
fi

cd "${script_dir}"/build-utils || exit 1
mkdir utils
mv bin/usr/local/bin/bwrap utils
mv bin/usr/local/bin/squashfuse utils
mv bin/usr/local/bin/squashfuse_ll utils
mv bin/usr/local/bin/mksquashfs utils
mv bin/usr/local/bin/unsquashfs utils
mv bin/usr/local/lib/liblz4.so."${lz4_version}" utils/liblz4.so.1
mv bin/usr/local/lib/libzstd.so."${zstd_version}" utils/libzstd.so.1
mv bin/usr/local/lib/libfuseprivate.so.0.0.0 utils/libfuseprivate.so.0
mv bin/usr/local/lib/libsquashfuse.so.0.0.0 utils/libsquashfuse.so.0

if ! ldd utils/squashfuse | grep -q libfuse.so.2; then
	mv utils/squashfuse utils/squashfuse3
	mv utils/squashfuse_ll utils/squashfuse3_ll
fi

if [ "${build_dwarfs}" = "true" ]; then
	git clone https://github.com/mhx/dwarfs.git --recursive

    # Revert commit aeeddae, because otherwise dwarfs might use
    # /usr/lib/locale/locale-archive file, which would break it
    # on systems using musl libc
    #
    # This can also be worked around by setting LC_ALL=C, but for now
    # let's revert the commit
    cd dwarfs || exit 1
    git revert --no-commit aeeddaecab5d4648780b0e11dc03fca19e23409a

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

cat <<EOF > utils/info
bubblewrap ${bwrap_version}
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
