#!/bin/sh

INSTALL_PREFIX=${INSTALL_PREFIX:=$HOME/.local/}
LATEST_VERSION=$(curl -sL https://api.github.com/repos/vasdee/caifs/releases/latest | grep '"tag_name":' | sed -E 's/.*"v?([^"]+)".*/\1/')

curl -sL https://github.com/vasdee/caifs/releases/download/v"$LATEST_VERSION"/release.tar.gz | tar zxf -

./caifs/config/bin/caifs add caifs -d . --link-root="$INSTALL_PREFIX"
