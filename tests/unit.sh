#!/bin/sh

. ./$(dirname $0)/../caifs/config/lib/caifslib.sh

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
    correct_path="this/is/a/good/path"
    bad_path="folder\subfolder\file.txt"

    validate_path "$correct_path"
    rc=$?

    assertSame "Path should be correct and return an rc of 0" "$rc" 0

    validate_path "$bad_path"
    rc=$?
    assertNotSame "Path should not be valid and have returned non zero" "$rc" "0"

}

test_is_wsl() {
    CAIFS_IN_WSL=1
    is_wsl
    rc="$?"
    #echo "rc=$rc"
    assertTrue "Test should not be in a WSL env by default" "[ $rc -ne 0  ]"

    CAIFS_IN_WSL=0
    is_wsl
    rc="$?"
    #echo "rc=$rc"
    assertTrue "Test should be forced to result in true using CAIFS_IN_WSL" "[ $rc -eq 0  ]"

}

test_is_container() {
    CAIFS_IN_CONTAINER=1
    is_container
    rc="$?"
    #echo "rc=$rc"
    assertTrue "Test should not be in a Container env by default" "[ $rc -ne 0  ]"

    CAIFS_IN_CONTAINER=0
    is_container
    rc="$?"
    #echo "rc=$rc"
    assertTrue "Test should be forced to result in true using CAIFS_IN_CONTAINER" "[ $rc -eq 0  ]"
}

# Enesure stripping the first char from a string, returns the original string, sans first char
test_strip_char() {

    the_string="^hello/root/path"
    stripped_string=$(strip_leading_char "$the_string")

    assertNotSame "String should not match after string" "$the_string" "$stripped_string"

    assertSame "String should match when the first ^ char is added back" "$the_string" "^$stripped_string"
}

test_replace_vars_in_string() {
    unset VAR1 BOTTOM
    good_string1="%VAR1%/at/top/and/%BOTTOM%/file.txt"

    replace_vars_in_string
    rc=$?
    #echo "rc=$rc"
    assertTrue "No supplied parameter to function should return error" "[ $rc -ne 0 ]"

    replace_vars_in_string "$good_string1"
    rc=$?
    #echo "rc=$rc"
    assertTrue "Vars should not be present and function should fail" "[ $rc -ne 0 ]"


    VAR1="VAR_VALUE"
    BOTTOM="BOTTOM_VALUE"
    replaced_string=$(replace_vars_in_string "$good_string1")
    rc=$?
    #echo "rc=$rc"
    assertTrue "Vars should be present and function should return success" "[ $rc -eq 0 ]"
    assertSame "Vars should be expanded in the path" "$replaced_string" "VAR_VALUE/at/top/and/BOTTOM_VALUE/file.txt"

}

test_config_directories() {
    VERBOSE=0
    prefix_path="/fake/collection"

    CAIFS_IN_CONTAINER=1
    CAIFS_IN_WSL=1

    config_dirs=$(config_directories "$prefix_path")
    assertSame "Not in container or WSL should only be a single config path" "$config_dirs" "$prefix_path/config"

    CAIFS_IN_CONTAINER=1
    CAIFS_IN_WSL=0

    config_dirs=$(config_directories "$prefix_path")

    assertSame "Not in container, but in WSL should be wsl and config path" "$prefix_path/config_wsl $prefix_path/config" "$config_dirs"

    CAIFS_IN_CONTAINER=0
    CAIFS_IN_WSL=1

    config_dirs=$(config_directories "$prefix_path")

    assertSame "In container but not in WSL should be a container and config path" "$prefix_path/config_container $prefix_path/config" "$config_dirs"

}

test_github_latest() {
    tag=""
    assertTrue "Tag value should be initially empty" "[ -z $tag ]"
    tag=$(github_latest_tag "casey/just")

    echo $tag
    assertTrue "Tag value should now not be empty" "[ -n $tag ]"
}

test_gitlab_latest() {
    tag=""
    assertTrue "Tag value should be initially empty" "[ -z $tag ]"
    tag=$(gitlab_latest_tag "gitlab-org%2Fcli")

    echo $tag
    assertTrue "Tag value should now not be empty" "[ -n $tag ]"
}

. ./shunit2/shunit2
