#!/bin/sh

TMPDIR=$(mktemp -d)
NUM_TESTS=100

# Add local caifs to the path if it's not available
if ! command -v caifs &>/dev/null; then
    PATH="$PWD/src/bin/:$PATH"
fi

# A function
# $1: conditon eg "-f /path/to/file"
# $2: message
assert() {
    if [ $1 ]; then
        echo "Assertion [ $1 ] SUCCESS - $2"
    else
        echo "Assertion [ $1 ] FAILED - $2"
        return 1
    fi
}

check_and_exec_test() {
    func_name=$1
    if type $func_name > /dev/null 2>&1; then
        shift 1
        setup
        echo "Running $func_name"
        eval $func_name $*
        test_rc=$?
        teardown
        return $test_rc
    else
        return 255
    fi
}


# $1: number of collections to create [default 1]
setup() {

    num_collections=${1:-1}
    i=0
    while [ "$i" -le $num_collections ]; do
        mkdir -p dummy_${i}/bash/config/.bashrc.d/
        mkdir -p dummy_${i}/zsh/config/zsh/
        mkdir -p dummy_${i}/git/config/.gitconfig.d/
        mkdir -p dummy_${i}/git/hooks/

        touch dummy_${i}/bash/config/.bashrc.d/custom.bash
        touch dummy_${i}/bash/config/.bashrc.d/wsl.bash
        touch dummy_${i}/bash/config/.bashrc
        touch dummy_${i}/git/config/.gitconfig
        touch dummy_${i}/git/config/.gitconfig.d/custom.config
        touch dummy_${i}/git/hooks/pre.sh

        i=$(($i+1))
    done
}

teardown() {
    rm -rf $TMPDIR
}

main() {
    i=1
    test_rc=0
    while [ "$test_rc" -ne 255 ]; do
        TMPDIR=$(mktemp -d)
        # Subshell to avoid cd'ing back and forth
        (
            export CAIFS_LINK_ROOT=$(mktemp -d)
            cd $TMPDIR
            check_and_exec_test "test_$i"
            exit $?
        )
        test_rc=$?
        rm -rf $TMPDIR

        if [ "$test_rc" -eq 255 ]; then
            echo "Got test_rc=$test_rc"
            break
        elif [ "$test_rc" -eq 1 ]; then
            echo "Test test_$i had exit code $test_rc"
            global_rc=1
        else
            global_rc=0
        fi
        i=$(($i +1))
    done

    exit $global_rc
}

trap 'rm -rf $TMPDIR' EXIT INT

test_1() {
    assert "-f dummy_0/bash/config/.bashrc.d/custom.bash" "File should exist"
    assert "-f dummy_0/git/hooks/pre.sh" "File should exist"
    assert "-f dummy_1/git/hooks/pre.sh" "File should exist"
    assert "! -f dummy_0/git/hooks/post.sh" "File should not exist"
}

test_2() {
    caifs run git -d dummy_0 --links
    assert "-L $CAIFS_LINK_ROOT/.gitconfig" ".gitconfig should be linked to root dir"
}

test_3() {
    caifs run git -d dummy_0 --hooks
    assert "! -L $CAIFS_LINK_ROOT/.gitconfig" ".gitconfig should not be linked to root dir"
}

# Test removing of a links
test_4() {
    caifs run git -d dummy_0 --links
    assert "-L $CAIFS_LINK_ROOT/.gitconfig" ".gitconfig should be linked to root dir"

    caifs rm git -d dummy_0 --links
    assert "! -L $CAIFS_LINK_ROOT/.gitconfig" ".gitconfig should not be linked to root dir"
}

# Test multiple collections
test_5() {
    touch dummy_1/git/config/.gitconfig-private

    caifs run git -d dummy_0 -d dummy_1 --links
    assert "-f $CAIFS_LINK_ROOT/.gitconfig-private" "Private gitconfig should exist from the dummy_0 root"
}

main
