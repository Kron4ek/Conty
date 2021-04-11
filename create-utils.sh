#!/usr/bin/env bash

script_dir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

squashfuse_version="0.1.103"
bwrap_version="0.4.1"
lz4_version="1.9.3"
zstd_version="1.4.9"

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
./configure --without-zlib --without-xz --without-lzo
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

if [ -f /usr/lib/libcap.so.2 ]; then
	cp -L /usr/lib/libcap.so.2 utils/libcap.so.2
elif [ -f  /lib/x86_64-linux-gnu/libcap.so.2 ]; then
	cp -L /lib/x86_64-linux-gnu/libcap.so.2 utils/libcap.so.2
fi

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
echo
echo "Keep in mind that your glibc version is: $(ldd --version | head -n 1)"
echo "The compiled utils will not work with older glibc versions!"
