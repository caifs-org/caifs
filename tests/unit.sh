#!/bin/sh

. ./$(dirname $0)/../src/lib/caifslib.sh

oneTimeSetUp() {
    :
}

oneTimeTearDown() {
    :
}

_touchpath() {
    mkdir -p "$(dirname "$1")"
    touch "$1"
}

setUp() {
    :
}

tearDown() {
    :
}

test_dry_run_or_exec() {
    DRY_RUN=1
    VERBOSE=1

    output=$(dry_or_exec "echo 'hello world'")
    assertSame "DRY RUN was not in effect, output should be present" "$output" "'hello world'"

    DRY_RUN=0
    output=$(dry_or_exec "echo 'hello world'")
    assertNotSame "DRY RUN was in effect, INFO log should be present" "$output" "'hello world'"

}

test_validate_path() {
    VERBOSE=0
    correct_path="this/is/a/good/path"

    rc=$(validate_path "$correct_path")

    echo "rc=$rc"
    #assertSame "Path should be correct and return an rc of 0" "$rc" 0

}


. ./shunit2/shunit2
