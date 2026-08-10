#!/bin/sh

# Log debug to standard error, so we can use debug logging in functions, without impacting
# the stdout returns
log_debug() {
    if [ "$VERBOSE" -eq 0 ]; then
        printf "[DEBUG] %s\n" "$@" >&2
    fi
}

# For general information that is useful for the user to see
log_info() {
    printf "[INFO]  %s\n" "$@" >&2
}

# Information that is unexpected, but acknowledged and catered for
# eg file conflicts
log_warn() {
    printf "[WARN]  %s\n" "$@" >&2
}

# $1: The error message
# $2: The exit code [Default 1]
log_error() {
    rc=${2:-1}
    printf  "[ERROR] %s\n" "$1" >&2
    exit "$rc"
}

##
## Some globals. These can generally be overridden via environment variables with the CAIFS_ prefix
# By default, run both links and hooks
# shellcheck disable=SC2034
CAIFS_VERSION=1.0.1

# Consumed by hooks.sh; shellcheck cannot see cross-module use
# shellcheck disable=SC2034
HOOKS_DIR=hooks

LOCAL_COLLECTION_DIR=${CAIFS_LOCAL_COLLECTIONS:-"$HOME/.local/share/caifs-collections"}

# A temporary install directory that is used by caifs_install.
# hooks should use this install structure for providing installables
export CAIFS_INSTALL_DIR="install"

# Force the override of existing link targets
RUN_FORCE=${CAIFS_RUN_FORCE:-1}

# Whether to run links and/or hooks. Defaults to true (0) for both
RUN_LINKS=${CAIFS_RUN_LINKS:-0}
RUN_HOOKS=${CAIFS_RUN_HOOKS:-0}
RUN_TARGETS=""

# Multiple targets could be specified. We will run them in order
export VERBOSE="${CAIFS_VERBOSE:=1}"
export DRY_RUN="${CAIFS_DRY_RUN:-1}"

# A list of directories to interogate for caifs collections
CAIFS_COLLECTIONS=${CAIFS_COLLECTIONS:-""}

# This could be exposed as an ENV var in the future, but it might be confusing with the above
COLLECTION_CONSTRAINT=""

# The root directory of where config should link to. By default it should be home, but for root scenarios
# this can be overridden
export LINK_ROOT="${CAIFS_LINK_ROOT:-$HOME}"

# The user that links should be owned by, which is useful in root situations like docker where installs are typically
# performed by the root user, but can be owned by the
export RUN_USER="${CAIFS_USER:=$USER}"

# Local directory for linking certificates into
export LOCAL_CERT_DIR=".local/share/certificates"

# Source the OS type and export the most useful for being available in executed scripts
export OS_TYPE=
OS_TYPE="$(uname -s)"

export OS_ID=""
export OS_VERSION_ID=""

export OS_ARCH=
OS_ARCH="$(uname -m)"

if [ "${OS_TYPE}" = "Linux" ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID=${ID}
    OS_VERSION_ID=${VERSION_ID}

elif [ "${OS_TYPE}" = "Darwin" ]; then
    OS_ID=$(sw_vers -productName)
    OS_VERSION_ID=$(sw_vers -productVersion)
else
    log_error "Unsupported Operating System - $OS_TYPE"
fi

set_collection_paths() {
    CAIFS_COLLECTIONS=$1
}
get_collection_paths() {
    echo "$CAIFS_COLLECTIONS"
}

set_run_hooks() {
    # Consumed by hooks.sh; shellcheck cannot see cross-module use
    # shellcheck disable=SC2034
    RUN_HOOKS=${1}
}

set_run_links() {
    # Consumed by links.sh; shellcheck cannot see cross-module use
    # shellcheck disable=SC2034
    RUN_LINKS=${1}
}

set_dry_run() {
    DRY_RUN=${1}
}

set_link_root() {
    LINK_ROOT=${1}
}

get_link_root() {
    echo "$LINK_ROOT"
}

set_force() {
    # Consumed by links.sh; shellcheck cannot see cross-module use
    # shellcheck disable=SC2034
    RUN_FORCE=${1}
}

set_run_user() {
    RUN_USER=${1}
}

get_run_user() {
    echo "$RUN_USER"
}

# Enables (0) or disables (1) the debugging logs
# $1 - status 0|1 default 1
set_verbose() {
    VERBOSE=${1}
}

set_run_targets() {
    if [ -z "$1" ]; then
        log_error "At least one target is required!"
    fi
    RUN_TARGETS=$1
}

get_run_targets() {
    echo "$RUN_TARGETS"
}

set_collection_constraint() {
    COLLECTION_CONSTRAINT=$1
}

get_collection_constraint() {
    echo "$COLLECTION_CONSTRAINT"
}

# returns a loopable string of files found within the supplied directory
# $1: The directory to search
files_in_dir() {
    dir=$1
    [ -d "$dir" ] || return 0
    (
        cd "$dir" || exit 0
        find . \( -type f -o -type l \) -print 2>/dev/null | sed 's|^\./||'
    )
}

# Splits a string at a desired character and returns the portion before the character
# returns the original string if no match found
# $1: string to search
# $2: optional charactor default @
str_before_char() {
    sep=${2:-'@'}
    echo "${1%"$sep"*}"
}

# Splits a string at a desired character and returns the portion after the character
# Returns the original string if no match found
# $1: string to search
# $2: optional charactor default @
str_after_char() {
    sep=${2:-'@'}
    echo "${1#*"$sep"}"
}

# Returns the first char of a string
# $1: the string to search
first_char() {
    echo "${1%"${1#?}"}"
}

# Gets an optional collection name from a target specifier, of the form target@<collection name>==<version info>
# Returns empty if nothing found
# $1: the target specifier string
get_collection() {
    collection=$(str_after_char "$1" "@")

    if [ "$collection" = "$1" ]; then
        # original string returned, meaning no collection specified. Return an empty string
        collection=""
    else
        # a collection was returned, but we need to check if version information is appended
        # and remove it for the collection name
        collection=$(str_before_char "$collection" "==")
    fi
    echo "$collection"
}

# Gets the target name from a target specifier, of the form target@<collection name>
# $1: the target specifier string
get_target() {
    target=$(str_before_char "$1" "==")
    target=$(str_before_char "$target" "@")
    echo "$target"
}

# Gets the version information, which follows the convention <target>@<collection>==<version>
# $1: The target specificer string
get_version_info() {
    version_info=$(str_after_char "$1" "==")

    if [ "$version_info" = "$1" ]; then
        # original string is returned, this means the == delimter wasn't found
        # return an empty string in this case
        version_info=""
    fi
    echo "$version_info"
}

# Validates that specified target is good to run against supplied collection
# If no collection is supplied, then function will return true
# $1: The collection specified as part of the target argument
# $2: collection_path
valid_for_collection_path() {
    collection_name=$(basename "$2")

    log_debug "valid_for_collection_path: 1=$1, 2=$2, collection_name=$collection_name"
    if [ "$1" = "$collection_name" ] || [ -z "$1" ]; then
        return 0
    else
        return 1
    fi
}

# iterate over the standard collection path and discovers installed collections
# each collection is added to the variable in order, apart from caifs-common which is always last
# If CAIFS_COLLECTION is non-empty, do nothing. Otherwise populate with auto found
populate_caifs_collections() {

    LOCAL_COLLECTION_DIR=$(strip_trailing "$LOCAL_COLLECTION_DIR")
    log_debug "populate_caifs_collections: BEGIN"
    for collection_dir in "${LOCAL_COLLECTION_DIR}"/*; do
        collection_name=$(basename "$collection_dir")

        if [ -d "$collection_dir" ] && [ "$collection_name" != "caifs-common" ]; then
            log_debug "Adding $collection_name in ${LOCAL_COLLECTION_DIR}"
            if [ -n "$CAIFS_COLLECTIONS" ]; then
                CAIFS_COLLECTIONS="$CAIFS_COLLECTIONS:$collection_dir"
            else
                CAIFS_COLLECTIONS="$collection_dir"
            fi
        fi

    done

    # Finally add the caifs-common lib to the end
    if [ -d "$LOCAL_COLLECTION_DIR/caifs-common" ]; then
        CAIFS_COLLECTIONS="$CAIFS_COLLECTIONS:$LOCAL_COLLECTION_DIR/caifs-common"
    fi
    log_debug "populate_caifs_collections: $CAIFS_COLLECTIONS - END"
}

# Runs a command, if the DRY_RUN setting is not in effect
dry_or_exec() {
    if [ "$DRY_RUN" -ne 0 ]; then
        log_debug "COMMAND is $*"
        # shellcheck disable=SC2068
        $@
    else
        log_info "DRY-RUN: Would have run $*"
    fi
}

# validate that a supplied path actually resembles a path
# $1: The path to check
validate_path() {
    pathchk -Pp "$1"
    rc=$?
    if [ "$rc" -ne 0 ]; then
        log_warn "$1 does not appear to be a valid path"
        return 1
    fi
    return 0
}

# Replaces delimited variables in a given string, with the values of the string if they exist
# $1: The string with delimited variables
# $2: delimiter [default: %]
replace_vars_in_string() {
    path="$1"

    if [ -z "$path" ]; then
        return 1
    fi
    for s in $(echo "$path" | sed -E 's|[^%]*%([^%]*)%[^%]*|\1 |g'); do
        match_value=$(eval "echo \$${s}")
        if [ -z "$match_value" ]; then
            log_debug "Value for $s is empty"
            return 1
        fi
        path=$(echo "$path" | sed "s|%$s%|$match_value|g")
    done
    echo "$path"
}

# Gets the value of a variable by name, if it exists. Otherwise returns an empty string
# $1: Name of the variable
var_value() {
    eval "echo \$${1}"
}

# Checks if a supplied path has a leading ^ which indicates it is destined for root config
# $1 the file path
is_root_config() {
    path=$1

    case "$path" in
        ^*)
            log_debug "$path is designated for root via leading ^"
            return 0
            ;;
        $HOME*)
            log_debug "$path is prefixed with \$HOME, not considering this a root config"
            return 1
            ;;
        /*)
            log_debug "$path is designated for root via leading /"
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Detects if running inside a container (Docker, Podman, LXC, etc.)
# Returns 0 if in container, 1 otherwise
is_container() {
    if [ -n "$CAIFS_IN_CONTAINER" ]; then
        if [ "$CAIFS_IN_CONTAINER" = "0" ]; then
            return 0
        else
            return 1
        fi
    fi
    [ -f /.dockerenv ] && return 0
    [ -f /run/.containerenv ] && return 0
    grep -qE 'docker|containerd|lxc|podman' /proc/1/cgroup 2>/dev/null && return 0
    return 1
}

# Detects if running inside a WSL environment
# Returns 0 if in WSL, 1 otherwise
is_wsl() {
    if [ -n "$CAIFS_IN_WSL" ]; then
        if [ "$CAIFS_IN_WSL" = "0" ]; then
            return 0
        else
            return 1
        fi
    fi
    [ -f /etc/wsl.conf ] && return 0
    [ -n "$WSLENV" ] && return 0
    return 1
}

# Detects if running on a portable device (laptop, notebook, convertible, etc.)
# Returns 0 if portable, 1 otherwise
is_portable() {
    if [ -n "$CAIFS_IS_PORTABLE" ]; then
        if [ "$CAIFS_IS_PORTABLE" = "0" ]; then
            return 0
        else
            return 1
        fi
    fi

    # Linux: check for battery via power supply type (more reliable than BAT* naming)
    for ps in /sys/class/power_supply/*; do
        [ -f "$ps/type" ] && [ "$(cat "$ps/type" 2>/dev/null)" = "Battery" ] && return 0
    done

    # Linux: fallback to DMI chassis type
    # 8=Portable, 9=Laptop, 10=Notebook, 14=Sub-Notebook, 31=Convertible, 32=Detachable
    if [ -f /sys/class/dmi/id/chassis_type ]; then
        case "$(cat /sys/class/dmi/id/chassis_type)" in
            8|9|10|14|31|32) return 0 ;;
        esac
    fi

    # untested...
    # macOS: check if it's a portable Mac
    if [ "$OS_ID" = "macOS" ]; then
        ioreg -l 2>/dev/null | grep -q '"BatteryInstalled" = Yes' && return 0
        # Fallback: check model identifier for portable Macs
        system_profiler SPHardwareDataType 2>/dev/null | grep -qiE 'MacBook|Portable' && return 0
        return 1
    fi

    return 1
}

# strips a trail character from the supplied string, returning the string, sans character
# $1: the string to strip
# $2: optional character, default '/'
strip_trailing() {
    char=${2:-"/"}
    echo "${1%"$char"}"
}

# strips the leading character for a string and returns the original string, sans first character
# $1: The string
# $2: The optional charactor to strip if present default ^
strip_leading_char() {
    char=${2:-'^'}
    echo "${1#"$char"}"
}

# Returns true 0 or false 1 depending if 1 or more hook scripts are present
# $1: target_dir to check for hooks/ directory
has_hooks() {
    target_dir=$1
    if [ -d "$target_dir/hooks" ]; then
        if [ -f "$target_dir/hooks/pre.sh" ] \
           || [ -f "$target_dir/hooks/post.sh" ] \
           || [ -f "$target_dir/hooks/rm.sh" ]
        then
            return 0
        fi
    fi
    return 1
}

# Returns true 0 or false 1 depending if 1 or more config files are present
# $1: target_dir to check for config*/ directory
has_config() {
    target_dir=$1
    find "$target_dir/"config* -type f 2>/dev/null | grep -q .
    return $?
}

# Returns true 0 or false 1 depending on whether the supplied target_dir is valid for caifs
# $1: target_dir to check
is_valid_caifs_structure() {
    if has_hooks "$1" || has_config "$1"; then
        return 0
    else
        return 1
    fi
}

# returns a string of valid config directories for this run
# Default will always be "config"
# $1 a path prefix to add to the final result of each config directory
config_directories() {
    path_prefix=$(strip_trailing "$1")
    config_directories="${path_prefix}/config"

    is_wsl && config_directories="${path_prefix}/config_wsl $config_directories"
    is_container && config_directories="${path_prefix}/config_container $config_directories"
    is_portable && config_directories="${path_prefix}/config_portable $config_directories"
    echo "$config_directories"
}


# $1 - line to conditionally add
# $2 - file path to add
add_line_to_file() {
    mkdir -p "$(dirname "$2")"
    touch "$2"
    if ! grep -q "${1}" "${2}"; then
        echo "${1}" >> "${2}"
        log_debug "Added ${1} to ${2}"
    else
        log_info "$1 already exists in ${2}....skipping"
    fi
}

# Check if an exectuable exists
# $1 name or path to executable
has() {
    if ! command -v "$1" > /dev/null 2>&1; then
        log_warn "$1 does not exist or is not executable"
        log_warn "you might need to run 'caifs run $1' to install it"
        return 1
    fi
    return 0
}

# A wrapper to the `has` function to exit if the command is not found
# $1 name or path to executable
has_or_exit() {
    if ! has "$@"; then
        exit 1
    fi
}

# Checks if a function exists and returns true 0 or false 1
# $1: Name of the function to check for
has_function() {
    func_name=$1

    if type "$func_name" > /dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Checks if a given function $1 exists and executes
# with remaining parameters
check_and_exec_function() {
    func_name=$1
    if has_function "$func_name"; then
        log_debug "function name=$func_name exists and will be run"
        shift 1
        eval "$func_name $*"
        rc="$?"
        if [ "$rc" -ne 0 ]; then
            log_info "$func_name exited with non-zero exit code, rc=$rc"
            exit "$rc"
        fi
    else
        log_debug "skipping function name=$func_name as it does not exist"
    fi

}

# Looks for a version environment variable for a given name
# If a corresponding env var of the form $<PACKAGE NAME>_VERSION exists, then this is assumed to be
# a version number required for the package.
# env_version=$(version_from_env uv)
# $1: package name
version_from_env() {
    PACKAGE=$1
    PACKAGE_UPPERCASE=$(echo "$PACKAGE" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
    PACKAGE_VERSION_VARNAME="${PACKAGE_UPPERCASE}_VERSION"
    PACKAGE_VERSION=$(eval echo "\$$PACKAGE_VERSION_VARNAME")
    log_debug "Matching package version for $PACKAGE will be in env-var $PACKAGE_VERSION_VARNAME"
    echo "$PACKAGE_VERSION"
}

# A wrapper function for elevating to sudo if required. Or failing that su -c
# This function helps during container builds, as usually the container runs as root and sudo isn't installed.
# This negates the need to add sudo, but must be run as root now
rootdo() {
    # If this is not run as an elevated user, then attempt to run the entire script again as sudo, or failing that
    # execute the command as root, on behalf of the user. Which may require an interactive password prompt
    if [ "$(id -u)" -ne 0 ]; then
        if has sudo ; then
            sudo "$@"
        else
            su -c "$@"
        fi
    else
        # shellcheck disable=SC2068
        $@
    fi
}



# Gets the latest github tag from a given repo. By default this api appears to be pretty-printed, so use tr
# to minify to one line for sed to parse
# Note: this function removes any optional v prefix of the tag, which seems to be a github convention
# $1 repo path
github_latest_tag() {
    curl -sL https://api.github.com/repos/"${1}"/releases/latest?per_page=1 | tr -d '[:space:]' | sed -E 's/.*"tag_name":"v?([^"]+)".*/\1/'
}

# Gets the latest tag for a given gitlab repository
# Note: this function removes any optional v prefix of the tag, which seems to be a github convention
# $1 project name or id
gitlab_latest_tag() {
    curl -sL https://gitlab.com/api/v4/projects/"${1}"/releases?per_page=1 | tr -d '[:space:]' | sed -E 's/.*"tag_name":"v?([^"]+)".*/\1/'
}



# Changes the permissions of a file or link according to the $RUN_USER variable, if set
# $1: The file or directory
# $2: root permissions required flag, default 1 false
ensure_permissions() {
    needs_root=${2:-1}

    if [ -n "${RUN_USER}" ]; then
        if [ "$needs_root" -eq 0 ]; then
            dry_or_exec rootdo chown -R "${RUN_USER}" "$1"
        else
            dry_or_exec chown -R "${RUN_USER}" "$1"
        fi
    fi
}

# A utility that allows installing software from a hook script, with respect to the LINK_ROOT
# It performs root escalation, if the current LINK_ROOT is anchored at /
# Files will be copied recurisvely from the CAIFS_INSTALL_DIR to the LINK_ROOT destination
# Note: Function respects the CAIFS_USER variable, so ownership will be applied to all files if set
# $1: Optional extra directory, useful for the LINK_ROOT=$HOME use case. Defaults to .local
caifs_install() {
    link_root_home=${2:-".local"}

    # If the intended LINK_ROOT starts with / then we escalate privileges
    if is_root_config "$LINK_ROOT"; then
        log_debug "Link root appears to reference / - escalating privileges for copy"
        ensure_permissions "${CAIFS_INSTALL_DIR}/*" 1
        dry_or_exec rootdo cp -vpr "${CAIFS_INSTALL_DIR}/*" "$LINK_ROOT/"
    elif [ "$LINK_ROOT" = "$HOME" ]; then
        log_debug "Link root is the default \$HOME - copying to $LINK_ROOT/$link_root_home/"
        ensure_permissions "${CAIFS_INSTALL_DIR}/*"
        dry_or_exec cp -vpr "${CAIFS_INSTALL_DIR}/*" "$LINK_ROOT/$link_root_home/"
    else
        # respect LINK_ROOT, but it appears to not need privileges
        ensure_permissions "${CAIFS_INSTALL_DIR}/*"
        dry_or_exec cp -vpr "${CAIFS_INSTALL_DIR}/*" "$LINK_ROOT/"
    fi
}

# shellcheck disable=SC2120
# A utility that allows removing of software that has previously been installed via caifs_install
# Much like caifs_install, it respects the LINK_ROOT destitation and acts accordingly
# $@: List of files to remove
caifs_remove() {

    link_root_home=".local"
    # prefix each argument with the $LINK_ROOT and remove
    for item in "$@"; do
        if is_root_config "$LINK_ROOT"; then
            log_debug "Link root appears to reference / - escalating privileges for copy"
            dry_or_exec rootdo rm -vr "$LINK_ROOT/$item"
        elif [ "$LINK_ROOT" = "$HOME" ]; then
            log_debug "Link root is the default \$HOME - copying to $LINK_ROOT/$link_root_home/"
            dry_or_exec rm -vr "$LINK_ROOT/$link_root_home/$item"
        else
            dry_or_exec rm -vr "$LINK_ROOT/$item"
        fi
    done
}

# Expand '*' to all targets in the collections
# Uses get_collection_paths() and sets run_targets via set_run_targets()
# $1: An optional explicit collection that was applied to '*@explicit-collection'
expand_wildcard_targets() {
    expanded_targets=""
    collection_paths="$(get_collection_paths)"

    while [ -n "$collection_paths" ]; do
        caifs_collection="${collection_paths%%:*}"

        if [ -d "$caifs_collection" ]; then
            for target_dir in "$caifs_collection"/*/; do
                [ -d "$target_dir" ] || continue
                target=$(basename "$target_dir")

                # Only include if it has a valid caifs structure
                is_valid_caifs_structure "$target_dir" || continue

                # If we have a explict collection, add it on to the target explicitly
                if [ -n "$1"  ]; then
                    target="${target}@${1}"
                fi

                # Add to list if not already present
                case " $expanded_targets " in
                    *" $target "*) ;;  # Already in list
                    *) expanded_targets="$expanded_targets $target" ;;
                esac
            done
        fi

        # Loop control
        if [ "$caifs_collection" = "$collection_paths" ]; then
            collection_paths=""
        else
            collection_paths="${collection_paths#*"${caifs_collection}":}"
        fi
    done

    set_run_targets "${expanded_targets# }"  # Trim leading space
}
