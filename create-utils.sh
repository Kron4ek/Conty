#!/usr/bin/env bash

# Dependencies: lz4 zstd wget gcc make autoconf libtool pkgconf libcap fuse2 (or fuse3)

script_dir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

squashfuse_version="0.1.104"
bwrap_version="0.4.1"
lz4_version="1.9.3"
zstd_version="1.5.0"

export CC=gcc
export CXX=g++

export CFLAGS="-O2"
export CXXFLAGS="${CFLAGS}"

mkdir -p "${script_dir}"/build-utils
cd "${script_dir}"/build-utils || exit 1

wget -q --show-progress -O lz4.tar.gz https://github.com/lz4/lz4/archive/refs/tags/v${lz4_version}.tar.gz
wget -q --show-progress -O zstd.tar.gz https://github.com/facebook/zstd/archive/refs/tags/v${zstd_version}.tar.gz
wget -q --show-progress -O squashfuse.tar.gz https://github.com/vasi/squashfuse/archive/refs/tags/${squashfuse_version}.tar.gz
wget -q --show-progress -O bwrap.tar.gz https://github.com/containers/bubblewrap/archive/refs/tags/v${bwrap_version}.tar.gz

tar xf lz4.tar.gz
tar xf zstd.tar.gz
tar xf squashfuse.tar.gz
tar xf bwrap.tar.gz

cd bubblewrap-${bwrap_version}
./autogen.sh
./configure --disable-selinux --disable-man
make -j$(nproc) DESTDIR="${script_dir}"/build-utils/bin install

cd ../lz4-${lz4_version}
make -j$(nproc) DESTDIR="${script_dir}"/build-utils/bin install

cd ../zstd-${zstd_version}
make -j$(nproc) DESTDIR="${script_dir}"/build-utils/bin install

cd ../squashfuse-${squashfuse_version}
./autogen.sh
./configure
make -j$(nproc) DESTDIR="${script_dir}"/build-utils/bin install

cd "${script_dir}"/build-utils
mkdir utils
mv bin/usr/local/bin/bwrap utils
mv bin/usr/local/bin/squashfuse utils
mv bin/usr/local/bin/squashfuse_ll utils
mv bin/usr/local/lib/liblz4.so.${lz4_version} utils/liblz4.so.1
mv bin/usr/local/lib/libzstd.so.${zstd_version} utils/libzstd.so.1
mv bin/usr/local/lib/libfuseprivate.so.0.0.0 utils/libfuseprivate.so.0
mv bin/usr/local/lib/libsquashfuse.so.0.0.0 utils/libsquashfuse.so.0

if [ ! "$(ldd utils/squashfuse | grep libfuse.so.2)" ]; then
	mv utils/squashfuse utils/squashfuse3
	mv utils/squashfuse_ll utils/squashfuse3_ll
fi

libs_list="ld-linux-x86-64.so.2 libcap.so.2 libc.so.6 libdl.so.2 \
		libfuse.so.2 libfuse3.so.3 libpthread.so.0 libz.so.1 \
		liblzma.so.5 liblzo2.so.2"

if [ -d /lib/x86_64-linux-gnu ]; then
	syslib_path="/lib/x86_64-linux-gnu /usr/lib/x86_64-linux-gnu"
else
	syslib_path="/usr/lib /usr/lib64"
fi

for i in ${libs_list}; do
	for j in ${syslib_path}; do
		if [ -f "${j}"/"${i}" ]; then
			cp -L "${j}"/"${i}" utils
			break
		fi
	done
done

find utils -type f -exec strip --strip-unneeded {} \; 2>/dev/null

cat <<EOF > utils/info
squashfuse ${squashfuse_version}
bubblewrap ${bwrap_version}
lz4 ${lz4_version}
zstd ${zstd_version}
EOF

tar -cf utils.tar utils
mv "${script_dir}"/utils.tar "${script_dir}"/utils_old.tar
mv utils.tar "${script_dir}"
cd "${script_dir}" || exit 1
rm -rf build-utils

clear
echo "Done!"
