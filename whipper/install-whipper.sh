#!/bin/sh

SCRIPT_DIR="$(realpath ${0%/*})" && cd ${SCRIPT_DIR}

WHIPPER_URL=https://api.github.com/repos/whipper-team/whipper/tags

TMPDIR=$(mktemp -p . -d)
for latest in $(curl -sL ${WHIPPER_URL} | jq -r '.[0].tarball_url'); do
    WHIPPER_VERSION=${latest##*\/v}
    if [[ -e ${SCRIPT_DIR}/whipper-${WHIPPER_VERSION}.tar.gz ]]; then
        tar -zxvf ${SCRIPT_DIR}/whipper-${WHIPPER_VERSION}.tar.gz --strip 1 -C ${TMPDIR}
    else
        echo "Downloading whipper-${WHIPPER_VERSION}.tar.gz..."
        curl -# -L ${latest} | tar xz --strip 1 -C ${TMPDIR}
    fi
done

cd ${TMPDIR}

echo "Version: ${WHIPPER_VERSION}" > PKG-INFO
for patch in ../*.patch; do patch -p0 < ${patch}; done
pip3 install --no-cache-dir -r requirements.txt
python3 setup.py install
