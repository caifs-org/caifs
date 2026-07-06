BINDIR=$(dirname "$0")
. "${BINDIR}"/../lib/caifs/utils.sh
. "${BINDIR}"/../lib/caifs/installers.sh

# Generic install script for installing per OS_ID based on the above global
# variables that determine cross platform OS infomation
#
# *_install functions are considered hooks, and should be developed per pre.sh or post.sh script as
# required
run_hook_functions() {

    case "$OS_TYPE" in
        Linux)
            if has_function "${OS_ID}"; then
                # Run the specific OS installers before the general purpose linux one
                check_and_exec_function "${OS_ID}"
            elif has_function linux; then
                check_and_exec_function linux
            fi
            ;;
        Darwin)
            check_and_exec_function macos
            ;;
        *)
            log_error "Not a supported OS"
            # This is invoked directly, we can safely ignore it, as it does actually work
            # shellcheck disable=SC2317
            exit 1
            ;;
    esac

    # only run the generic hook, if no OS_TYPE specific hooks exist, which imply they haven't been run
    if [ "$OS_TYPE" = "Linux" ] && ! (has_function "${OS_ID}" || has_function linux); then
        log_debug "No '${OS_ID}' or 'linux' hook function exists for OS_TYPE of $OS_TYPE, checking for 'generic'"
        check_and_exec_function generic
    elif [ "$OS_TYPE" = "Darwin" ] && ! (has_function "macos"); then
        log_debug "No '${OS_ID}' or 'linux' hook function exists for OS_TYPE of $OS_TYPE, checking for 'generic'"
        check_and_exec_function generic
    fi

    # Run container-specific hooks for cleanup, etc.
    if is_container; then
        log_debug "Container environment detected"
        check_and_exec_function container
    fi
}

# Run a specific type of hook for a given target.
# The script is sourced to give access to all the caifs runtime variables.
# $1: target specificer <target>@<collection>==<version info>
# $2: collection path
# $3: hook type [pre|post|rm]
run_hook() {
    _func="run_hook:"
    target=$(get_target "$1")
    collection=$(get_collection "$1")
    version_info=$(get_version_info "$1")
    collection_path=$2
    hook_type=$3

    collection_name=$(basename "$collection_path")

    if [ "$RUN_HOOKS" -ne 0 ]; then
        log_debug "$_func Not running ${hook_type}-hook for target '$target' in collection $collection_path"
        return 0
    fi

    if [ -f "$collection_path/$target/$HOOKS_DIR/${hook_type}.sh" ] && [ "$DRY_RUN" -eq 0 ]; then
        log_info "DRY-RUN: Would have run ${hook_type}-hook for target '$target' in collection $collection_name"

    elif [ -f "$collection_path/$target/$HOOKS_DIR/${hook_type}.sh" ]; then
        log_debug "$_func Running ${hook_type}-hook for target '$target' in collection $collection_path"
        # Run within a subshell, this has the benefit of any sourced script functions and variables
        # do not pollute subsequent targets on the same run
        export CAIFS_TARGET="$target"
        (

            TMP_DIR=$(mktemp -d)
            cd "${TMP_DIR}" || exit

            # pre create an install directory that caifs_install can use to automatically install files
            mkdir -p ${CAIFS_INSTALL_DIR}/bin \
                  ${CAIFS_INSTALL_DIR}/lib \
                  ${CAIFS_INSTALL_DIR}/share/zsh/completions \
                  ${CAIFS_INSTALL_DIR}/share/bash-completion/completions

            # shellcheck disable=SC1090
            # import the hook script functions
            . "$collection_path/$target/$HOOKS_DIR/${hook_type}.sh"

            # TARGET VERSION is injected into this sub-process to allow targets to
            # make use of version information provided on the command line
            # shellcheck disable=SC2034
            TARGET_VERSION="$version_info"

            log_info "Running ${hook_type}-hook for target '$target' in '$collection_name' collection on ${OS_TYPE}/${OS_ID}($OS_ARCH)"
            run_hook_functions

            cd "${TMP_DIR}" || exit

            #cd - || exit
            rm -rf "${TMP_DIR}"
        )
        unset CAIFS_TARGET

    else
        log_debug "$_func No ${hook_type}-hook found for target '$target'. Ignoring"
    fi

}

# A wrapper to specifically run a remove hook
# $1: collection path
# $2: The target name to run the hook for
run_remove_hook() {
    run_hook "$@" "rm"
}

# A wrapper to specifically run a pre hook
# $1: collection path
# $2: The target name to run the hook for
run_pre_hook() {
    run_hook "$@" "pre"
}

# A wrapper to specifically run a post hook
# $1: collection path
# $2: The target name to run the hook for
run_post_hook() {
    run_hook "$@" "post"
}
