set export

SHUNIT2_VERSION := '2.1.8'
CAIFS_VERBOSE := env('CAIFS_VERBOSE', '1')

# List available recipes
help:
    just --list

# Download shunit2 test framework into tests/
[script]
download-shunit:
    cd tests/
    curl -sL https://github.com/kward/shunit2/archive/refs/tags/v${SHUNIT2_VERSION}.tar.gz | tar xzf -

    if [ -d shunit2 ]; then
        rm -rf shunit2
    fi
    mv shunit2-${SHUNIT2_VERSION} shunit2
    rm -rf shunit2-${SHUNIT2_VERSION}

# Run integration and unit tests
[script]
test:
    cd tests/
    ./integration.sh
    ./unit.sh

# Create a release tarball
[script]
create-release:
    tar -czvf release.tar.gz caifs/

# Install pre-commit hooks
pre-commit-install:
    pre-commit install --install-hooks

# Run pre-commit checks on all files
pre-commit-run:
    pre-commit run --all

# Install caifs to ~/.local/ (symlinks bin and lib)
install:
    ./caifs/config/bin/caifs add caifs -d . --link-root "$HOME/.local" --force
