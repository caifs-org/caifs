#!/bin/sh
# shellcheck disable=all

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
    TMPDIR=$(mktemp -d)
    cd $TMPDIR
}

tearDown() {
    rm -rf $TMPDIR
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

test_is_portable() {
    CAIFS_IS_PORTABLE=1
    is_portable
    rc="$?"
    assertTrue "Test should not be portable when CAIFS_IS_PORTABLE=1" "[ $rc -ne 0  ]"

    CAIFS_IS_PORTABLE=0
    is_portable
    rc="$?"
    assertTrue "Test should be forced to result in true using CAIFS_IS_PORTABLE=0" "[ $rc -eq 0  ]"
}

# Ensure stripping the first char from a string, returns the original string, sans first char
test_strip_leading_char() {

    the_string="^hello/root/path"
    stripped_string=$(strip_leading_char "$the_string")

    assertNotSame "String should not match after string" "$the_string" "$stripped_string"

    assertSame "String should match when the first ^ char is added back" "$the_string" "^$stripped_string"
}

# Ensure stripping the leading char from a string, by default the / is removed from the original
# or left intact
test_strip_trailing_char() {

    set_verbose 0
    str_with_slash="hello/slashy/path/"
    str_without_slash="hello/no-slashy/path"

    stripped_string=$(strip_trailing "$str_with_slash")

    assertNotSame "String $str_with_slash should not match after strip $stripped_string" "$str_with_slash" "$stripped_string"
    assertSame "String should match when the first ^ char is added back" "$str_with_slash" "$stripped_string/"

    stripped_string=$(strip_trailing "$str_without_slash")
    assertSame "String $str_without_slash should match after strip $stripped_string" "$str_without_slash" "$stripped_string"
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
    CAIFS_IS_PORTABLE=1

    config_dirs=$(config_directories "$prefix_path")
    assertSame "Not in container, WSL, or portable should only be a single config path" "$config_dirs" "$prefix_path/config"

    CAIFS_IN_CONTAINER=1
    CAIFS_IN_WSL=0
    CAIFS_IS_PORTABLE=1

    config_dirs=$(config_directories "$prefix_path")

    assertSame "Not in container or portable, but in WSL should be wsl and config path" "$prefix_path/config_wsl $prefix_path/config" "$config_dirs"

    CAIFS_IN_CONTAINER=0
    CAIFS_IN_WSL=1
    CAIFS_IS_PORTABLE=1

    config_dirs=$(config_directories "$prefix_path")

    assertSame "In container but not in WSL or portable should be a container and config path" "$prefix_path/config_container $prefix_path/config" "$config_dirs"

    CAIFS_IN_CONTAINER=1
    CAIFS_IN_WSL=1
    CAIFS_IS_PORTABLE=0

    config_dirs=$(config_directories "$prefix_path")

    assertSame "Portable only should be portable and config path" "$prefix_path/config_portable $prefix_path/config" "$config_dirs"

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

test_is_root_config() {
    caret_path="^etc/profile/test.conf"
    root_path="/usr/sbin/test"
    local_path="~/home/bin/test"
    set_verbose 0

    is_root_config "$caret_path"
    rc=$?
    assertSame "Caret path $caret_path should be considered a root path" "0" "$rc"

    is_root_config "$root_path"
    rc=$?
    assertSame "Root path $root_path should be considered a root path" "0" "$rc"

    is_root_config "$local_path"
    rc=$?
    assertSame "Local path $local_path should NOT be considered a root path" "1" "$rc"
}

test_has_config() {

    _paths="target1/config/.local/bin/test"
    _paths="$_paths target2/config_wsl/.local/bin/test"
    _paths="$_paths target3/config_container/.local/bin/test"
    _paths="$_paths target4/hooks/.local/bin/test"
    for c in $_paths; do
        _touchpath "$c"
    done

    has_config "target1"
    rc=$?
    assertSame "should return true" "0" "$rc"

    has_config "target2"
    rc=$?
    assertSame "should return true" "0" "$rc"

    has_config "target3"
    rc=$?
    assertSame "should return true" "0" "$rc"

    has_config "target4"
    rc=$?
    assertSame "should return false" "1" "$rc"

}

test_valid_caifs_structure() {

    _paths="target1/config/.local/bin/test"
    _paths="$_paths target2/hooks/pre.sh"
    _paths="$_paths target3/config/.local/bin/test"
    _paths="$_paths target3/hooks/post.sh"
    _paths="$_paths target4/hooks/random.sh"

    for c in $_paths; do
        _touchpath "$c"
    done

    is_valid_caifs_structure "target1"
    rc=$?
    assertSame "should be a valid caifs structure" "0" "$rc"

    is_valid_caifs_structure "target2"
    rc=$?
    assertSame "should be a valid caifs structure" "0" "$rc"

    is_valid_caifs_structure "target3"
    rc=$?
    assertSame "should be a valid caifs structure" "0" "$rc"

    is_valid_caifs_structure "target4"
    rc=$?
    assertSame "should NOT be a valid caifs structure" "1" "$rc"
}

test_files_in_dir() {
    _paths="target1/config/.local/bin/test"
    _paths="$_paths target1/config/.local/share/file.txt"
    _paths="$_paths target1/config/.local/bin/test2"
    _paths="$_paths target1/hooks/post.sh"
    expected_files=3

    for c in $_paths; do
        _touchpath "$c"
    done

    file_count=0
    for f in $(files_in_dir "target1/config/"); do
        file_count=$((file_count+1))
    done
    assertSame "Number of config files should be $expected_files" "$expected_files" "$file_count"
}

test_cert_handler() {
    :
}

. ./shunit2/shunit2
