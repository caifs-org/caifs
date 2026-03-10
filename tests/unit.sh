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

test_str_splitting() {
    var="target@collection"
    split=$(str_before_char "$var")
    assertSame "String should match target" "target" "$split"

    split=$(str_after_char "$var")
    assertSame "String should match collection" "collection" "$split"


    var="target"
    split=$(str_before_char "$var")
    assertSame "No collection specified, so target should be returned" "target" "$split"

    split=$(str_after_char "$var")
    assertSame "No collection specified, so target should be returned" "target" "$split"

    var="@collection"
    split=$(str_before_char "$var")
    assertSame "No target specified, but the collection is, should return empty" "" "$split"

    split=$(str_after_char "$var")
    assertSame "No target specified, but the collection is, should return collection" "collection" "$split"
}

test_target_and_collection() {

    target1="ruff@python-utils"
    target2="ruff"

    t=$(get_target "$target1")
    c=$(get_collection "$target1")

    assertSame "Target should be ruff" "ruff" "$t"
    assertSame "Collection should be python-utils" "python-utils" "$c"

    t=$(get_target "$target2")
    c=$(get_collection "$target2")

    assertSame "Target should be ruff" "ruff" "$t"
    assertSame "Collection should be empty" "" "$c"
}

test_valid_for_collection_path() {

    collection="my-collection"
    collection_path="/path/my-collection"

    valid_for_collection_path "$collection" "$collection_path"
    rc=$?
    assertSame "collection $collection should be valid for $collection_path" "0" "$rc"

    collection_path="/path/my-collection2"
    valid_for_collection_path "$collection" "$collection_path"
    rc=$?
    assertSame "collection $collection should NOT be valid for $collection_path" "1" "$rc"
}

test_first_char() {
    str="*"
    char=$(first_char "$str")
    assertSame "First character of $str should be *" "*" "$char"

    str="*@hello"
    char=$(first_char "$str")
    assertSame "First character of $str should be *" "*" "$char"
}

test_hooks_subshell() {

    _touchpath "$TMPDIR/my-collection/target1/hooks/pre.sh"

    cat << EOF > $TMPDIR/my-collection/target1/hooks/pre.sh
generic() {
  echo "$CAIFS_TARGET" > generic_marker0.txt
  export GENERIC_VARIABLE=test

  echo "DRY_RUN=$DRY_RUN"
  export -p

  echo "target=$target"

  if [ -z "$CAIFS_TARGET" ]; then
     echo "$CAIFS_TARGET does not exist"
     exit 1
  fi
}

linux() {
  echo "$CAIFS_TARGET" > linux_marker0.txt
  export LINUX_VARIABLE=test
}
EOF

    assertTrue "The variables should not be set" "[ -z "$GENERIC_VARIABLE" ]"

    type "generic" 2>/dev/null | grep -q 'function'
    is_function_rc=$?

    DRY_RUN=1
    assertSame "The function generic shouldn't exist prior to running hooks" "1" "$is_function_rc"
    run_hook "$TMPDIR/my-collection" "target1" "pre"

    type "generic" 2>/dev/null | grep -q 'function'
    is_function_rc=$?
    assertTrue "The variables \$GENERIC_VARIABLE and \$LINUX_VARIABLE should not be set after the run " "[ -z "$GENERIC_VARIABLE" ]"
    assertSame "The function generic shouldn't exist after running hooks" "1" "$is_function_rc"

    assertTrue "The CAIFS_TARGET variable should be set after a run" "[ -z "$CAIFS_TARGET" ]"
}

. ./shunit2/shunit2
