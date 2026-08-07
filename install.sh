#!/bin/sh

INSTALL_PREFIX=${INSTALL_PREFIX:=$HOME/.local}
INCLUDE_COMMON="0"
CAIFS_VERSION="latest"
CAIFS_COMMON_VERSION="latest"

# Downloads a release tarball and extracts it, refusing to write through any top-level
# entry that is a symlink. tar follows a symlinked directory when the archive holds a
# directory of the same name, which silently overwrites whatever it points at -- a real
# hazard since collections are commonly symlinked to live git checkouts.
# $1: download url
# $2: destination directory
# Returns 1 without extracting if any top-level entry would be written through a symlink
download_and_extract() {
    url=$1
    dest=$2
    tarball=$(mktemp)

    if ! curl -sL "$url" -o "$tarball"; then
        echo "ERROR: failed to download $url" >&2
        rm -f "$tarball"
        return 1
    fi

    unsafe=""
    for entry in $(tar ztf "$tarball" | sed 's|/.*||' | sort -u); do
        if [ -L "$dest/$entry" ]; then
            unsafe="$unsafe $entry"
        fi
    done

    if [ -n "$unsafe" ]; then
        echo "" >&2
        echo "WARNING: skipping extraction into $dest" >&2
        echo "WARNING: these entries are symlinks, and extracting would write through" >&2
        echo "WARNING: them and overwrite what they point at:" >&2
        for entry in $unsafe; do
            echo "WARNING:   $entry -> $(readlink "$dest/$entry")" >&2
        done
        echo "WARNING: remove or rename them first to install the released version." >&2
        echo "" >&2
        rm -f "$tarball"
        return 1
    fi

    tar zvxf "$tarball" -C "$dest"
    rm -f "$tarball"
}

mkdir -p "$INSTALL_PREFIX"

if [ "${CAIFS_VERSION}" = "latest" ]; then
    DOWNLOAD_URL="https://github.com/caifs-org/caifs/releases/${CAIFS_VERSION}/download/release.tar.gz"
else
    DOWNLOAD_URL="https://github.com/caifs-org/caifs/releases/download/${CAIFS_VERSION}/release.tar.gz"
fi

download_and_extract "${DOWNLOAD_URL}" "$INSTALL_PREFIX"

if [ "${INCLUDE_COMMON}" -eq 0 ]; then
    mkdir -p "$INSTALL_PREFIX"/share/caifs-collections

    if [ "${CAIFS_COMMON_VERSION}" = "latest" ]; then
        DOWNLOAD_URL="https://github.com/caifs-org/caifs-common/releases/${CAIFS_COMMON_VERSION}/download/release.tar.gz"
    else
        DOWNLOAD_URL="https://github.com/caifs-org/caifs-common/releases/download/${CAIFS_COMMON_VERSION}/release.tar.gz"
    fi

    download_and_extract "${DOWNLOAD_URL}" "${INSTALL_PREFIX}"/share/caifs-collections
fi
