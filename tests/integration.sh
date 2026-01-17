#!/bin/sh

oneTimeSetUp() {
    #export CAIFS_VERBOSE=0
    # Add local caifs to the path if it's not available
    if ! command -v caifs &>/dev/null; then
        PATH="$(dirname $0)/../src/bin/:$PATH"
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

    #tree -a $COLLECTION_BASE_DIR
}

tearDown() {
    rm -rf $TMPDIR $CAIFS_LINK_ROOT
    unset CAIFS_LINK_ROOT
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

testEnvVarInConfigPathMissing() {
    path_with_env=$COLLECTION_BASE_DIR/dummy_1/editorconfig/config/%CODE_DIR%/.editorconfig
    _touchpath $path_with_env
    assertTrue "$path_with_env should exist on the file system" "[ -f $path_with_env ]"

    assertTrue "CODE_DIR should be empty" "[ -z $CODE_DIR ]"

    caifs add editorconfig -d $COLLECTION_BASE_DIR/dummy_1 --links
    rc=$?
    assertTrue "caifs should fail with missing env var" "[ $rc -ne 0 ]"
}

testEnvVarInConfigPathVarSet() {
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

testReplaceVarsInString() {
    echo 1
}




. ./shunit2/shunit2
