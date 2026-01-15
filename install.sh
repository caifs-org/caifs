#!/bin/sh

INSTALL_PREFIX=${INSTALL_PREFIX:=$HOME/.local/}
curl -sL0 https://github.com/vasdee/caifs/releases/latest.tar.gz | tar zx

cp bin/caifs $INSTALL_PREFIX/bin/caifs
cp lib/caifs/utils.sh $INSTALL_PREFIX/lib/caifs/utils.sh

chmod +x $INSTALL_PREFIX/bin/caifs
