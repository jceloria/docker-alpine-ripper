#!/bin/sh

SCRIPT_DIR="$(realpath ${0%/*})" && cd ${SCRIPT_DIR}

CCEXTRACTOR_URL=https://api.github.com/repos/CCExtractor/ccextractor/releases/latest

TMPDIR=$(mktemp -p . -d)
for latest in $(curl -sL ${CCEXTRACTOR_URL} | jq -r '.tarball_url'); do
    CCEXTRACTOR_VERSION=${latest##*\/v}
    if [[ -e ${SCRIPT_DIR}/ccextractor-${CCEXTRACTOR_VERSION}.tar.gz ]]; then
        tar -zxvf ${SCRIPT_DIR}/ccextractor-${CCEXTRACTOR_VERSION}.tar.gz --strip 1 -C ${TMPDIR}
    else
        echo "Downloading ccextractor-${CCEXTRACTOR_VERSION}.tar.gz..."
        curl -# -L ${latest} | tar xz --strip 1 -C ${TMPDIR}
    fi
done

mkdir -p ${TMPDIR}/build && cd ${TMPDIR}/build && cmake ../src && make
cd ../../ && install -m755 ${TMPDIR}/build/ccextractor /usr/local/bin
strip /usr/local/bin/ccextractor
