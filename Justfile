set export

SHUNIT2_VERSION := '2.1.8'
CAIFS_VERBOSE := env('CAIFS_VERBOSE', '1')

help:
    just --list

[script]
download-shunit:
    cd tests/
    curl -sL https://github.com/kward/shunit2/archive/refs/tags/v${SHUNIT2_VERSION}.tar.gz | tar xzf -

    if [ -d shunit2 ]; then
        rm -rf shunit2
    fi
    mv shunit2-${SHUNIT2_VERSION} shunit2
    rm -rf shunit2-${SHUNIT2_VERSION}

[script]
test:
    cd tests/
    ./integration.sh
    ./unit.sh


pre-commit-install:
    pre-commit install --install-hooks

pre-commit-run:
    pre-commit run --all
