#!/bin/sh
# shellcheck disable=all

oneTimeSetUp() {
    #export CAIFS_VERBOSE=0
    # Add local caifs to the path if it's not available
    if ! command -v caifs &>/dev/null; then
        PATH="$(dirname $0)/../caifs/config/bin/:$PATH"
    fi
}

oneTimeTearDown() {
    :
}

_touchpath() {
    mkdir -p "$(dirname "$1")"
    touch "$1"
}

# $1: number of collections to create [default 1]
setUp() {
    export CAIFS_IN_CONTAINER=1
    export CAIFS_IN_WSL=1
    COLLECTION_BASE_DIR=$(mktemp -d)
    export CAIFS_LINK_ROOT=$(mktemp -d)

    num_collections=${1:-1}
    i=0
    while [ "$i" -le $num_collections ]; do
        _touchpath "$COLLECTION_BASE_DIR/dummy_${i}/bash/config/.bashrc.d/custom.bash"
        _touchpath "$COLLECTION_BASE_DIR/dummy_${i}/bash/config/.bashrc.d/wsl.bash"
        _touchpath "$COLLECTION_BASE_DIR/dummy_${i}/bash/config/.bashrc"
        _touchpath "$COLLECTION_BASE_DIR/dummy_${i}/git/config/.gitconfig"
        _touchpath "$COLLECTION_BASE_DIR/dummy_${i}/git/config/.gitconfig.d/custom.config"
        _touchpath "$COLLECTION_BASE_DIR/dummy_${i}/git/hooks/pre.sh"

        i=$(($i+1))
    done

    cat << EOF > $COLLECTION_BASE_DIR/dummy_0/git/hooks/pre.sh
generic() {
  touch ${COLLECTION_BASE_DIR}/generic_marker0.txt
}

linux() {
  touch ${COLLECTION_BASE_DIR}/linux_marker0.txt
}
EOF


    #tree -a $COLLECTION_BASE_DIR
}

tearDown() {
    rm -rf $TMPDIR $CAIFS_LINK_ROOT
    unset CAIFS_LINK_ROOT
    unset CAIFS_VERBOSE
    unset CAIFS_DRY_RUN
}

testFilesExists() {
    assertTrue "$COLLECTION_BASE_DIR/dummy_0/bash/config/.bashrc.d/custom.bash should exist!" "[ -f $COLLECTION_BASE_DIR/dummy_0/bash/config/.bashrc.d/custom.bash ]"
    assertTrue "$COLLECTION_BASE_DIR/dummy_0/git/hooks/pre.sh should exist" "[ -f $COLLECTION_BASE_DIR/dummy_0/git/hooks/pre.sh ]"
    assertTrue "[ -f $COLLECTION_BASE_DIR/dummy_1/git/hooks/pre.sh ]"
    assertTrue "[ ! -f $COLLECTION_BASE_DIR/dummy_0/git/hooks/post.sh ]"
}

testCheckBasicLinking() {
    caifs add git -d $COLLECTION_BASE_DIR/dummy_0 --links
    assertTrue ".gitconfig should be linked to $CAIFS_LINK_ROOT/.gitconfig" "[ -L $CAIFS_LINK_ROOT/.gitconfig ]"
}


testHooksRunWithoutLinks() {
    caifs add git -d $COLLECTION_BASE_DIR/dummy_0 --hooks
    assertTrue ".gitconfig should not be linked to root dir" "[ ! -L $CAIFS_LINK_ROOT/.gitconfig ]"
}

test_hooks_lib_sourced() {
    # Create a target with lib.sh and post.sh
    mkdir -p "$COLLECTION_BASE_DIR/dummy_0/libtest/hooks"
    mkdir -p "$COLLECTION_BASE_DIR/dummy_0/libtest/config"
    touch "$COLLECTION_BASE_DIR/dummy_0/libtest/config/.libtest"

    # lib.sh defines a function that creates a marker file
    cat > "$COLLECTION_BASE_DIR/dummy_0/libtest/hooks/lib.sh" << 'EOF'
create_marker() {
    touch "$CAIFS_LINK_ROOT/.lib_marker"
}
EOF

    # post.sh calls the function from lib.sh
    cat > "$COLLECTION_BASE_DIR/dummy_0/libtest/hooks/post.sh" << 'EOF'
generic() {
    create_marker
}
EOF

    caifs add libtest -d $COLLECTION_BASE_DIR/dummy_0

    assertTrue "lib.sh function should have been called and created marker" "[ -f $CAIFS_LINK_ROOT/.lib_marker ]"
}

testRemovingLinks() {
    caifs add git -d $COLLECTION_BASE_DIR/dummy_0 --links
    assertTrue ".gitconfig should be linked to root dir after add a link" "[ -L $CAIFS_LINK_ROOT/.gitconfig ]"

    caifs rm git -d $COLLECTION_BASE_DIR/dummy_0 --links
    assertTrue ".gitconfig should not be linked to root dir" "[ ! -L $CAIFS_LINK_ROOT/.gitconfig ]"
}

testMultipleCollections() {
    _touchpath $COLLECTION_BASE_DIR/dummy_1/git/config/.gitconfig-private

    caifs add git -d $COLLECTION_BASE_DIR/dummy_0 -d $COLLECTION_BASE_DIR/dummy_1 --links
    assertTrue "Private gitconfig should exist from the dummy_0 root" "[ -f $CAIFS_LINK_ROOT/.gitconfig-private ]"
}

test_var_config_path_missing() {
    path_with_env=$COLLECTION_BASE_DIR/dummy_1/editorconfig/config/%CODE_DIR%/.editorconfig
    _touchpath $path_with_env
    assertTrue "$path_with_env should exist on the file system" "[ -f $path_with_env ]"

    assertTrue "CODE_DIR should be empty" "[ -z $CODE_DIR ]"

    caifs add editorconfig -d $COLLECTION_BASE_DIR/dummy_1 --links
    rc=$?
    assertTrue "caifs should not fail with missing env var" "[ $rc -eq 0 ]"
}

test_var_config_path_set() {
    path_with_env=$COLLECTION_BASE_DIR/dummy_1/editorconfig/config/.test/%CODE_DIR%/.editorconfig
    # Don't use ~ here, because we are in temp dirs. CAIFS_LINK_ROOT is the target
    export CODE_DIR="code/private"

    _touchpath $path_with_env
    assertTrue "$path_with_env should exist on the file system" "[ -f $path_with_env ]"

    assertTrue "CODE_DIR should not be empty" "[ -n $CODE_DIR ]"

    caifs add editorconfig -d $COLLECTION_BASE_DIR/dummy_1
    rc=$?
    assertTrue "caifs should process successfully" "[ $rc -eq 0 ]"
    assertTrue ".editorconfig should exist at $CAIFS_LINK_ROOT/code" "[ -f $CAIFS_LINK_ROOT/.test/code/private/.editorconfig ]"
}

# This test doesn't do anything really. It's a visual match until I can figure out chroot
test_root_config_file_create() {
    echo "need to add this test"
    export CAIFS_VERBOSE=0
    export CAIFS_DRY_RUN=1

    path_with_caret=$COLLECTION_BASE_DIR/dummy_1/my-sudoers/config/^etc/sudoers.d/test.conf
    _touchpath $path_with_caret
    assertTrue "$path_with_caret should exist on the file system" "[ -f $path_with_caret ]"

    caifs add my-sudoers -d $COLLECTION_BASE_DIR/dummy_1 --links --dry-run
}

# Test that the ^ linking is working
test_root_config_file_unlink() {
    export CAIFS_VERBOSE=0
    export CAIFS_DRY_RUN=1

}

# Test that wildcard expands to all targets in a collection
test_wildcard_add_all_targets() {
    caifs add '*' -d $COLLECTION_BASE_DIR/dummy_0 --links

    assertTrue ".gitconfig should be linked" "[ -L $CAIFS_LINK_ROOT/.gitconfig ]"
    assertTrue ".bashrc should be linked" "[ -L $CAIFS_LINK_ROOT/.bashrc ]"
}

# Test that wildcard removes all targets
test_wildcard_rm_all_targets() {
    caifs add '*' -d $COLLECTION_BASE_DIR/dummy_0 --links
    caifs rm '*' -d $COLLECTION_BASE_DIR/dummy_0 --links

    assertTrue ".gitconfig should not be linked" "[ ! -L $CAIFS_LINK_ROOT/.gitconfig ]"
    assertTrue ".bashrc should not be linked" "[ ! -L $CAIFS_LINK_ROOT/.bashrc ]"
}

# Test deduplication across multiple collections
test_wildcard_deduplicates_targets() {
    # Both dummy_0 and dummy_1 have 'git' target
    caifs add '*' -d $COLLECTION_BASE_DIR/dummy_0 -d $COLLECTION_BASE_DIR/dummy_1 --links

    # Should only link once (first collection wins)
    assertTrue ".gitconfig should be linked" "[ -L $CAIFS_LINK_ROOT/.gitconfig ]"
}

# Test that invalid directories are skipped
test_wildcard_skips_invalid_targets() {
    mkdir -p $COLLECTION_BASE_DIR/dummy_0/invalid_target  # No config/ or hooks/

    caifs add '*' -d $COLLECTION_BASE_DIR/dummy_0 --links

    # Valid targets still work
    assertTrue ".gitconfig should be linked" "[ -L $CAIFS_LINK_ROOT/.gitconfig ]"
}

# A marker file should be created when hooks are run
test_hooks() {
    caifs add git -d $COLLECTION_BASE_DIR/dummy_0 --hooks
    assertTrue "A marker file should be present" "[ -f ${COLLECTION_BASE_DIR}/generic_marker0.txt ]"
}


# A marker file should not be created when hooks are run with dry-run mode
test_hooks_dry_run() {

    caifs add git -d $COLLECTION_BASE_DIR/dummy_0 --hooks --dry-run
    assertFalse "A marker file should NOT be present" "[ -f ${COLLECTION_BASE_DIR}/generic_marker0.txt ]"

}

# Test the --collection constraint
# when normally run, the dummy_0 collection would usually run first, as it is first in order
test_caifs_collection_constraint() {
    # Override the CAIFS LOCAL COLLECTION var
    CAIFS_LOCAL_COLLECTIONS=$COLLECTION_BASE_DIR caifs add git --collection dummy_1 --links

    assertTrue ".gitconfig should be linked to root dir after add a link" "[ -L $CAIFS_LINK_ROOT/.gitconfig ]"

    link=$(readlink "$CAIFS_LINK_ROOT/.gitconfig")

    assertEquals "Only dummy_1 should be linked" "$COLLECTION_BASE_DIR/dummy_1/git/config/.gitconfig" "$link"

}

# Test explicit @collection-constrain syntax
test_caifs_explicit_constraint() {
    CAIFS_LOCAL_COLLECTIONS=$COLLECTION_BASE_DIR caifs add git@dummy_1 bash@dummy_0 --links

    assertTrue ".gitconfig should be linked to root dir after add a link" "[ -L $CAIFS_LINK_ROOT/.gitconfig ]"

    link=$(readlink "$CAIFS_LINK_ROOT/.gitconfig")

    assertEquals "Only dummy_1 should be linked" "$COLLECTION_BASE_DIR/dummy_1/git/config/.gitconfig" "$link"


    assertTrue ".bashrc should be linked to root dir after add a link" "[ -L $CAIFS_LINK_ROOT/.bashrc ]"

    link=$(readlink "$CAIFS_LINK_ROOT/.bashrc")

    assertEquals "Only dummy_0 should be linked" "$COLLECTION_BASE_DIR/dummy_0/bash/config/.bashrc" "$link"
}

test_wildcard_constraint() {
    CAIFS_LOCAL_COLLECTIONS=$COLLECTION_BASE_DIR caifs add --collection dummy_1 '*' --links

    assertTrue ".gitconfig should be linked to root dir after add a link" "[ -L $CAIFS_LINK_ROOT/.gitconfig ]"
    link=$(readlink "$CAIFS_LINK_ROOT/.gitconfig")
    assertEquals "Only dummy_1 should be linked" "$COLLECTION_BASE_DIR/dummy_1/git/config/.gitconfig" "$link"

    assertTrue ".bashrc should be linked to root dir after add a link" "[ -L $CAIFS_LINK_ROOT/.bashrc ]"
    link=$(readlink "$CAIFS_LINK_ROOT/.bashrc")
    assertEquals "Only dummy_1 should be linked" "$COLLECTION_BASE_DIR/dummy_1/bash/config/.bashrc" "$link"
}

test_wildcard_explicit_constraint() {
    CAIFS_LOCAL_COLLECTIONS=$COLLECTION_BASE_DIR caifs add '*@dummy_1' --links

    assertTrue ".gitconfig should be linked to root dir after add a link" "[ -L $CAIFS_LINK_ROOT/.gitconfig ]"
    link=$(readlink "$CAIFS_LINK_ROOT/.gitconfig")
    assertEquals "Only dummy_1 should be linked" "$COLLECTION_BASE_DIR/dummy_1/git/config/.gitconfig" "$link"

    assertTrue ".bashrc should be linked to root dir after add a link" "[ -L $CAIFS_LINK_ROOT/.bashrc ]"
    link=$(readlink "$CAIFS_LINK_ROOT/.bashrc")
    assertEquals "Only dummy_1 should be linked" "$COLLECTION_BASE_DIR/dummy_1/bash/config/.bashrc" "$link"
}

. ./shunit2/shunit2
