#!/bin/sh

INSTALL_PREFIX=${INSTALL_PREFIX:=$HOME/.local/}
LATEST_VERSION=$(curl -sL https://api.github.com/repos/caifs-org/caifs/releases/latest?per_page=1 \
                     | tr -d '[:space:]' \
                     | sed -E 's/.*"tag_name":"v?([^"]+)".*/\1/')

curl -sL https://github.com/caifs-org/caifs/releases/download/v"$LATEST_VERSION"/release.tar.gz | tar zxf -

cp -r caifs/config/bin "$INSTALL_PREFIX"
cp -r caifs/config/lib "$INSTALL_PREFIX"

curl -sL https://raw.githubusercontent.com/caifs-org/caifs-common/refs/heads/main/install.sh | sh

# The old way was to use caifs to install, but it left the caifs-common target around
# #./caifs/config/bin/caifs add caifs -d . --link-root="$INSTALL_PREFIX"
rm -rf caifs
