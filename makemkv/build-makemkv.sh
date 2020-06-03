#!/bin/bash

set -e
set -o pipefail

export DEBIAN_FRONTEND=noninteractive

SCRIPT_DIR="$(realpath ${0%/*})"

MAKEMKV_URL='https://www.makemkv.com/forum/viewtopic.php?f=3&t=224'
FFMPEG_URL='https://ffmpeg.org/releases'
FDK_AAC_URL='https://api.github.com/repos/mstorsjo/fdk-aac/tags'

usage() {
    echo "usage: $(basename $0) ROOT_EXEC_DIR OUTPUT_DIR

  Arguments:
    ROOT_EXEC_DIR  Root directory where MakeMKV will be located at execution
                   time.  Default: '/opt/makemkv'.
    OUTPUT_DIR     Directory where the tarball will be copied to, if specified.
"
}

if [[ -n "$1" ]] && [[ $1 != /* ]]; then
    echo "ERROR: Invalid root execution directory."
    usage
    exit 1
fi

ROOT_EXEC_DIR="${1:-/opt/makemkv}"
TARBALL_DIR="$2"
BUILD_DIR=/tmp/makemkv-build
INSTALL_BASEDIR=/tmp/makemkv-install
INSTALL_DIR=${INSTALL_BASEDIR}${ROOT_EXEC_DIR}

rm -rf "${INSTALL_DIR}"
mkdir -p "${BUILD_DIR}"
mkdir -p "${INSTALL_DIR}"
[[ ! -z "${TARBALL_DIR}" ]] && mkdir -p "${TARBALL_DIR}"

echo "Updating APT cache..."
apt-get update

# NOTE: zlib is needed by Qt and MakeMKV.
# NOTE: xkb-data is needed for Qt to detect the correct XKB config path.
echo "Installing build prerequisites..."
apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    curl \
    dh-autoreconf \
    file \
    jq \
    libc6-dev \
    libdrm-dev \
    libexpat1-dev \
    libssl-dev \
    libx11-dev \
    libx11-xcb-dev \
    libxcb1-dev \
    patchelf \
    pkg-config \
    python \
    xkb-data \
    zlib1g-dev

#
# fdk-aac
#
cd "${BUILD_DIR}"
FDK_AAC_URL=$(curl -sL ${FDK_AAC_URL} | jq -r '.[0].tarball_url')
FDK_AAC_VERSION=${FDK_AAC_URL##*\/v}
if [[ -e ${SCRIPT_DIR}/fdk-aac-${FDK_AAC_VERSION}.tar.gz ]]; then
    tar -zxvf ${SCRIPT_DIR}/fdk-aac-${FDK_AAC_VERSION}.tar.gz
else
    echo "Downloading fdk-aac..."
    mkdir -p fdk-aac-${FDK_AAC_VERSION}
    curl -# -L ${FDK_AAC_URL} | tar -xz --strip 1 -C fdk-aac-${FDK_AAC_VERSION}
fi
echo "Compiling fdk-aac..."
cd fdk-aac-${FDK_AAC_VERSION}
./autogen.sh
./configure --prefix="$BUILD_DIR/fdk-aac" \
            --enable-static \
            --disable-shared \
            --with-pic
make -j$(nproc) install

#
# ffmpeg
#
cd "${BUILD_DIR}"
for latest in $(curl -sL ${FFMPEG_URL} | grep -Eo 'href="([^"#]+)"' | awk -F\" '$0~/xz"/{print $2}' | sort -V | tail -1); do
    if [[ -e ${SCRIPT_DIR}/${latest} ]]; then
        tar -Jxvf ${SCRIPT_DIR}/${latest}
    else
        echo "Downloading ${latest}..."
        curl -# -L ${FFMPEG_URL}/${latest} | tar -xJ
    fi
done
echo "Compiling ffmpeg..."
cd ffmpeg-*
PKG_CONFIG_PATH="${BUILD_DIR}/fdk-aac/lib/pkgconfig" ./configure \
        --prefix="${BUILD_DIR}/ffmpeg" \
        --enable-static \
        --disable-shared \
        --enable-pic \
        --enable-libfdk-aac \
        --disable-x86asm \
        --disable-doc \
        --disable-programs
make -j$(nproc) install

#
# MakeMKV - get/extract latest release
#
cd "${BUILD_DIR}"
for latest in $(curl -sL ${MAKEMKV_URL} | grep -Eo 'href="([^"#]+)"' | awk -F\" '$0~/makemkv-(oss|bin)/{print $2}'); do
    if [[ -e ${SCRIPT_DIR}/${latest##*/} ]]; then
        tar -zxvf ${SCRIPT_DIR}/${latest##*/}
    else
        echo "Downloading ${latest##*/}..."
        curl -# -L ${latest} | tar -xz
    fi
done

#
# MakeMKV OSS
#
cd "${BUILD_DIR}"
echo "Compiling MakeMKV OSS..."
cd makemkv-oss-*
patch -p0 < "${SCRIPT_DIR}/launch-url.patch"
DESTDIR="${INSTALL_DIR}" PKG_CONFIG_PATH="${BUILD_DIR}/ffmpeg/lib/pkgconfig" ./configure --disable-gui --prefix=
make -j$(nproc) install

#
# MakeMKV bin
#
cd "${BUILD_DIR}"
echo "Installing MakeMKV bin..."
cd makemkv-bin-*
patch -p0 < "${SCRIPT_DIR}/makemkv-bin-makefile.patch"
DESTDIR="${INSTALL_DIR}" make install

#
# Umask Wrapper
#
echo "Compiling umask wrapper..."
gcc -o "${BUILD_DIR}"/umask_wrapper.so "${SCRIPT_DIR}/umask_wrapper.c" -fPIC -shared
echo "Installing umask wrapper..."
cp -v "${BUILD_DIR}"/umask_wrapper.so "${INSTALL_DIR}/lib/"

echo "Patching ELF of binaries..."
find "${INSTALL_DIR}"/bin -type f -executable -exec echo "  -> Setting interpreter of {}..." \; -exec patchelf --set-interpreter "${ROOT_EXEC_DIR}/lib/ld-linux-x86-64.so.2" {} \;
find "${INSTALL_DIR}"/bin -type f -executable -exec echo "  -> Setting rpath of {}..." \; -exec patchelf --set-rpath '$ORIGIN/../lib' {} \;

EXTRA_LIBS="/lib/x86_64-linux-gnu/libnss_compat.so.2 \
            /lib/x86_64-linux-gnu/libnsl.so.1 \
            /lib/x86_64-linux-gnu/libnss_nis.so.2 \
            /lib/x86_64-linux-gnu/libnss_files.so.2 \
"

# Package library dependencies
echo "Extracting shared library dependencies..."
find "${INSTALL_DIR}" -type f -executable -or -name 'lib*.so*' | while read BIN; do
    RAW_DEPS="$(LD_LIBRARY_PATH="${INSTALL_DIR}/lib:${BUILD_DIR}/jdk/lib/jli" ldd "${BIN}")"
    echo "Dependencies for ${BIN}:"
    echo "================================"
    echo "${RAW_DEPS}"
    echo "================================"

    if echo "${RAW_DEPS}" | grep -q " not found"; then
        echo "ERROR: Some libraries are missing!"
        exit 1
    fi

    DEPS="$(LD_LIBRARY_PATH="${INSTALL_DIR}/lib" ldd "${BIN}" | (grep " => " || true) | cut -d'>' -f2 | sed 's/^[[:space:]]*//' | cut -d'(' -f1)"
    for dep in ${DEPS} ${EXTRA_LIBS}; do
        dep_real="$(realpath "${dep}")"
        dep_basename="$(basename "${dep_real}")"

        # Skip already-processed libraries.
        [ ! -f "${INSTALL_DIR}/lib/${dep_basename}" ] || continue

        echo "  -> Found library: ${dep}"
        cp "${dep_real}" "${INSTALL_DIR}/lib/"
        while true; do
            [ -L "${dep}" ] || break;
            ln -sf "${dep_basename}" "${INSTALL_DIR}"/lib/$(basename ${dep})
            dep="$(readlink -f "${dep}")"
        done
    done
done

echo "Patching ELF of libraries..."
find "${INSTALL_DIR}" \
    -type f \
    -name "lib*" \
    -exec echo "  -> Setting rpath of {}..." \; -exec patchelf --set-rpath '$ORIGIN' {} \;

echo "Finished building and installing MakeMKV and its dependencies."

if [[ ! -z "${TARBALL_DIR}" ]]; then
    echo "Creating tarball..."
    tar -zcf "${TARBALL_DIR}/makemkv.tar.gz" -C "${INSTALL_BASEDIR}" "${ROOT_EXEC_DIR:1}" --owner=0 --group=0

    echo "${TARBALL_DIR}/makemkv.tar.gz has been created successfully!"
fi

# vim:ft=sh:ts=4:sw=4:et:sts=4
