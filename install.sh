#!/bin/sh

INSTALL_PREFIX=${INSTALL_PREFIX:=$HOME/.local}
INCLUDE_COMMON="0"
CAIFS_VERSION="latest"
CAIFS_COMMON_VERSION="latest"

mkdir -p "$INSTALL_PREFIX"

if [ "${CAIFS_VERSION}" = "latest" ]; then
    DOWNLOAD_URL="https://github.com/caifs-org/caifs/releases/${CAIFS_VERSION}/download/release.tar.gz"
else
    DOWNLOAD_URL="https://github.com/caifs-org/caifs/releases/download/${CAIFS_VERSION}/release.tar.gz"
fi

curl -sL "${DOWNLOAD_URL}" | tar zvxf - -C "$INSTALL_PREFIX"

if [ "${INCLUDE_COMMON}" -eq 0 ]; then
    mkdir -p "$INSTALL_PREFIX"/share/caifs-collections

    if [ "${CAIFS_COMMON_VERSION}" = "latest" ]; then
        DOWNLOAD_URL="https://github.com/caifs-org/caifs-common/releases/${CAIFS_COMMON_VERSION}/download/release.tar.gz"
    else
        DOWNLOAD_URL="https://github.com/caifs-org/caifs-common/releases/download/${CAIFS_COMMON_VERSION}/release.tar.gz"
    fi

    curl -sL "${DOWNLOAD_URL}" | tar zvxf - -C "${INSTALL_PREFIX}"/share/caifs-collections
fi
