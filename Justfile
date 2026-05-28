set export

SHUNIT2_VERSION := '2.1.8'
CAIFS_VERBOSE := env('CAIFS_VERBOSE', '1')

PATH := x"$HOME/.local/bin:$PATH"

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

[script]
test-in-docker:
    docker build \
    --progress=plain \
    --no-cache \
     -f Dockerfile.test \
     .

# Run integration and unit tests
[script]
test:
    cd tests/
    ./integration.sh
    ./unit.sh

[script]
[arg("patch", long="patch", value="patch")]
[arg("minor", long="minor", value="minor")]
[arg("major", long="major", value="major")]
bump-version $patch="" $minor="" $major="" *args:
    bump-my-version bump $patch $minor $major {{ args }}

create-release-tar:
    tar -czvf release.tar.gz -X .tarignore src/

[doc('List contents of release tarball')]
[script]
list-release-tar-files:
    tar -ztf release.tar.gz

# Install pre-commit hooks
pre-commit-install:
    pre-commit install --install-hooks

# Run pre-commit checks on all files
pre-commit-run:
    pre-commit run --all

# Install caifs to ~/.local/ via hard copy
[script]
install-caifs:
    ./src/bin/caifs add caifs -d .
    caifs add caifs-common -d . --hooks

[doc('Install CI runner dependencies (uv, pre-commit, rumdl)')]
[script]
install-caifs-runner-deps:
    caifs add uv pre-commit rumdl --hooks

[doc('Utility function to do a regex replacement on a string')]
[script]
replace-regex str regex replacement:
    echo {{ replace_regex(str, regex, replacement) }}

[doc('Utility function to do a regex replacement on a string')]
[script]
replace str from to:
    echo {{ replace(str, from, to) }}

[doc('Use symbolic link to install caifs directly from the git repo. Useful for local development')]
install-caifs-links:
    ln -s ~/.local/bin/caifs ~/path/to/caifs/src/bin/caifs
    ln -s ~/.local/lib/caifslib.sh ~/path/to/caifs/src/lib/caifslib.sh
