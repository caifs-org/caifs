#!/bin/sh

INSTALL_PREFIX=${INSTALL_PREFIX:=$HOME/.local/}
curl -sL https://github.com/vasdee/caifs/releases/download/v0.0.1/release.tar.gz | tar zxf -

cp bin/caifs $INSTALL_PREFIX/bin/caifs
cp lib/caifs-lib.sh $INSTALL_PREFIX/lib/caifs-lib.sh

chmod +x $INSTALL_PREFIX/bin/caifs
chmod +x $INSTALL_PREFIX/lib/caifs-lib.sh
