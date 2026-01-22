#!/bin/sh

HOOK_SCRIPTS=$(find . -name "pre*" -or -name "post*" -or -name "rm*" -type f)
RET_CODE=0

for hs in $HOOK_SCRIPTS; do
    echo -n "Checking $hs for executable bit"
    if [ ! -x $hs ]; then
        chmod +x $hs
        RET_CODE=1
        echo "...not set, adding executable bit"
    else
        echo "...OK"
    fi
done

exit $RET_CODE
