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
    if ls -la /.dockerenv 2>/dev/null ; then
        cd tests/
        ./integration.sh
        ./unit.sh
    else
        echo "Does not appear to be within a docker container"
        exit 1
    fi

[script]
[arg("patch", long="patch", value="patch")]
[arg("minor", long="minor", value="minor")]
[arg("major", long="major", value="major")]
bump-version $patch="" $minor="" $major="" *args:
    bump-my-version bump $patch $minor $major {{ args }}

create-release-tar:
    tar -C src/ -czvf release.tar.gz -X .tarignore .

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
install-caifs link-root="$HOME/.local":
    mkdir -p {{link-root}}/share/caifs-collections
    cp -r ./src/* {{link-root}}/

    COLLECTIONS_DIR="$HOME/.local/share/caifs-collections"
    TARBALL=$(mktemp)
    trap 'rm -f "$TARBALL"' EXIT

    curl -L https://github.com/caifs-org/caifs-common/releases/latest/download/release.tar.gz -o "$TARBALL"

    # tar follows a symlinked directory when the archive holds a directory of the same
    # name, writing straight through it into whatever it points at. Collections are
    # commonly symlinked to live git checkouts, so refuse rather than clobber them.
    UNSAFE=""
    for entry in $(tar ztf "$TARBALL" | sed 's|/.*||' | sort -u); do
        if [ -L "$COLLECTIONS_DIR/$entry" ]; then
            UNSAFE="$UNSAFE $entry"
        fi
    done

    if [ -n "$UNSAFE" ]; then
        echo "" >&2
        echo "WARNING: skipping the caifs-common collection install." >&2
        echo "WARNING: these entries under $COLLECTIONS_DIR are symlinks, and extracting" >&2
        echo "WARNING: would write through them and overwrite what they point at:" >&2
        for entry in $UNSAFE; do
            echo "WARNING:   $entry -> $(readlink "$COLLECTIONS_DIR/$entry")" >&2
        done
        echo "WARNING: remove or rename them first if you want the released collection." >&2
        echo "WARNING: caifs itself installed fine to {{link-root}}." >&2
        echo "" >&2
        exit 0
    fi

    tar zxvf "$TARBALL" -C "$COLLECTIONS_DIR"

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
    ln -s $PWD/src/bin/caifs ~/.local/bin/caifs
    ln -s $PWD/src/lib/caifs ~/.local/lib/caifs

[doc('Run local CAIFS directly from just, overriding the default path to preference local.')]
caifs *args:
    ./src/bin/caifs {{ args }}
