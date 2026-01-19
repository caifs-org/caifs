#!/bin/sh

INSTALL_PREFIX=${INSTALL_PREFIX:=$HOME/.local/}
LATEST_VERSION=$(curl -sL https://api.github.com/repos/caifs-org/caifs/releases/latest?per_page=1 \
                     | tr -d '[:space:]' \
                     | sed -E 's/.*"tag_name":"v?([^"]+)".*/\1/')

curl -sL https://github.com/caifs-org/caifs/releases/download/v"$LATEST_VERSION"/release.tar.gz | tar zxf -

./caifs/config/bin/caifs add caifs -d . --link-root="$INSTALL_PREFIX"
