#!/bin/sh

INSTALL_PREFIX=${INSTALL_PREFIX:=$HOME/.local/}
LATEST_VERSION=$(curl -sL https://api.github.com/repos/vasdee/caifs/releases/latest | grep '"tag_name":' | sed -E 's/.*"v?([^"]+)".*/\1/')

curl -sL https://github.com/vasdee/caifs/releases/download/v$LATEST_VERSION/release.tar.gz | tar zxf -

cp bin/caifs $INSTALL_PREFIX/bin/caifs
cp lib/caifs-lib.sh $INSTALL_PREFIX/lib/caifslib.sh

chmod +x $INSTALL_PREFIX/bin/caifs
chmod +x $INSTALL_PREFIX/lib/caifslib.sh
