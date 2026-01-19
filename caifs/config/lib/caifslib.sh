#!/bin/sh

log_debug() {
    if [ "$VERBOSE" -eq 0 ]; then
        echo "DEBUG: $*"
    fi
}

log_info() {
    echo "INFO: $*"
}

log_warn() {
    echo "WARN: $*"
}

# $1: The error message
# $2: The exit code [Default 1]
log_error() {
    rc=${2:-1}
    echo "ERROR: $1"
    exit "$rc"
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
    pathchk -p "$1"
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
            log_warn "Value for $s is empty"
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
            log_debug "$path is designated for root"
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
    [ -f /.dockerenv ] && return 0
    [ -f /run/.containerenv ] && return 0
    [ -n "$CAIFS_IN_CONTAINER" ] && return 0
    grep -qE 'docker|containerd|lxc|podman' /proc/1/cgroup 2>/dev/null && return 0
    return 1
}

# Detects if running inside a WSL environment
# Returns 0 if in WSL, 1 otherwise
is_wsl() {
    [ -n "$WSLENV" ] && return 0
    [ -n "$CAIFS_IN_WSL" ] && return 0
    return 1
}

# returns a string of valid config directories for this run
# Default will always be "config"
# $1 a path prefix to add to the final result of each config directory
config_directories() {
    if [ "${1%?}" = '/' ]; then
        path_prefix="${1%?}"
    else
        path_prefix="$1"
    fi
    config_directories="${path_prefix}/config"
    [ "$(is_wsl)" ] && config_directories="${path_prefix}/config_wsl $config_directories"
    [ "$(is_container)" ] && config_directories="${path_prefix}/config_container $config_directories"
    echo "$config_directories"
}

# Creates symbolic links for all files under the target config directory
# It creates the directory structure, if it doesn't exist already
# $1: collection path
# $2: target
# $3: root directory to link the files in
create_target_links() {
    collection_path="$1"
    target=$2
    #target_directory="${collection_path}/${target}/${CONFIG_DIR}"
    link_root=$3
    require_escalation=1
    log_debug "Creating link for $*"

    # if in a container or wsl environment, enable extra search directories. These specific
    # environments take priority to the standard 'config' one, which comes last in the find
    target_directory="$(config_directories "${collection_path}/${target}")"

    log_debug "using target_directory=$target_directory"

    # TODO - is there a solution to this that is more POSIX compliant?
    # shellcheck disable=SC2044
    for config_file in $(find "${target_directory}" \( -type f -o -type l \) -printf "%P\n" 2>/dev/null); do

        log_debug "Processing $target_directory/$config_file"

        #dest_file=$(replace_vars_in_string "$config_file")
        # replace any variable place holders in the relative path, to form a destination path
        # TODO: This should call replace_vars_in_string but the exiting doesn't work well
        dest_file=$config_file
        for s in $(echo "$dest_file" | sed -E 's|[^%]*%([^%]*)%[^%]*|\1 |g'); do
            match_value=$(eval "echo \$${s}")
            if [ -z "$match_value" ]; then
                log_error "Value for $s is empty, exiting"
            fi
            dest_file=$(echo "$dest_file" | sed "s|%$s%|$match_value|g")
        done

        # Check if the leading config entry has a ^ then we need to escalate to root
        if [ "$(is_root_config "$config_file")" ]; then
            link_root="/"
            # remove the caret from the start of the string
            dest_file=$(strip_leading_char "$config_file")
            require_escalation=0
        fi

        #validate_path "$dest_file"
        create_link "$target_directory/$config_file" "$link_root/$dest_file" "$require_escalation" "$RUN_FORCE"
    done
}

# Removes all symbolic links for all files under the target config directory
# $1: collection path
# $2: target
# $3: the link_root to remove from
remove_target_links() {
    collection_path="$1"
    target=$2
    link_root=$3
    log_debug "Removing links for target=$target in collection=$collection_path"

    # if in a container or wsl environment, enable extra search directories. These specific
    # environments take priority to the standard 'config' one, which comes last in the find
    target_directory="$(config_directories "${collection_path}/${target}")"

    # TODO - is there a solution to this that is more POSIX compliant?
    # shellcheck disable=SC2044
    for config_file in $(find "${target_directory}" \( -type f -o -type l \) -printf "%P\n" ); do
        log_debug "Found ${config_file}. Checking if link exists at $link_root/$config_file"
        if [ -L "$link_root/$config_file" ]; then

            unlink_cmd="unlink $link_root/$config_file"
            if [ "$(is_root_config "$config_file")" ]; then
                link_root="/"
                unlink_cmd="rootdo $unlink_cmd"
            fi
            dry_or_exec "$unlink_cmd"
        fi
    done
}

# $1: link source
# $2: link destination
# $3: require root escalation [default 1: false]
# $4: force mode [default false|1]
create_link() {
    source_file="$1"
    dest_link="$2"
    require_escalation=${3:-1}
    force=${4:-1}

    log_debug "create_link: source_file=$source_file dest_link=$dest_link force=$force"

    # Check for existing file or symlink (including broken symlinks)
    if { [ -e "$dest_link" ] || [ -L "$dest_link" ]; } && [ "$force" -ne 0 ]; then
        log_warn "link or file already exists for $dest_link .... skipping"
        return
    fi
    if { [ -e "$dest_link" ] || [ -L "$dest_link" ]; } && [ "$force" -eq 0 ]; then
        if [ -L "$dest_link" ]; then
            log_warn "FORCE set, unlinking $dest_link"
            dry_or_exec "unlink $dest_link"
        elif [ -f "$dest_link" ]; then
            log_warn "FORCE set, removing regular file $dest_link"
            dry_or_exec "rm $dest_link"
        fi
    fi

    basedir=$(dirname "$dest_link")
    if [ ! -d "$basedir" ]; then
        log_debug "Creating directory structure at $basedir"
        dry_or_exec "mkdir -p $basedir"
    fi

    link_cmd="ln -s $source_file $dest_link"
    # if the destination link, starts with a / then we need to escalate to root
    if [ "$require_escalation" -eq 0 ]; then
        link_cmd="root_do $link_cmd"
    fi

    log_info "Creating Link $source_file -> $dest_link"
    dry_or_exec "$link_cmd"
}

# strips the leading character for a string and returns the original string, sans first character
# $1: The string
strip_leading_char() {
    echo "${1#?}"
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
    rc=$(has "$@")
    if [ "$rc" -ne 0 ]; then
        exit "$rc"
    fi
}

# Checks if a given function $1 exists and executes
# with remaining parameters
check_and_exec_function() {
    func_name=$1
    if type "$func_name" > /dev/null 2>&1; then
        shift 1
        eval "$func_name $*"
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
    echo "$PACKAGE_VERSION"
}

# A wrapper function for elevating to sudo if required. Or failing that su -c
# This function helps during container builds, as usually the container runs as root and sudo isn't installed.
# This negates the need to add sudo, but must be run as root now
rootdo() {
    # If this is not run as an elevated user, then attempt to run the entire script again as sudo
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


# This helper function can be used for installing tools via uv
# If a corresponding env var of the form $<PACKAGE NAME>_VERSION exists, then this is assumed to be
# a version number required for the package. It will be appended to the uv install command via the == syntax
# $1 name of the tool to install via uv
uv_install() {
    has_or_exit uv
    PACKAGE=$1
    shift 1

    PACKAGE_VERSION=$(version_from_env "$PACKAGE")
    if [ -n "$PACKAGE_VERSION" ]; then
        PACKAGE="$PACKAGE==$PACKAGE_VERSION"
    fi
    uv tool install --upgrade "$PACKAGE $*"
}

# Removes a package via a uv tool install
uv_uninstall() {
    uv tool uninstall "$@"
}

# Install a package via npm.
# You should ensure that the nodejs hook has been run previously, otherwise packages will be
# installed to non-shell aware locations
# $1 name of the package
npm_install() {
    has_or_exit npm
    PACKAGE=$1
    shift 1

    PACKAGE_VERSION=$(version_from_env "$PACKAGE")
    if [ -n "$PACKAGE_VERSION" ]; then
        PACKAGE="${PACKAGE}@${PACKAGE_VERSION}"
    fi
    npm install --global "$PACKAGE $*"
}

# Removes a managed package via npm
npm_uninstall() {
    npm uninstall --global "$@"
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


# Generic install script for installing per OS_ID based on the above global
# variables that determine cross platform OS infomation
#
# *_install functions are considered hooks, and should be developed per pre.sh or post.sh script as
# required
run_hook_functions() {
    log_info "Running $SCRIPT_ACTION hook for $SCRIPT_GROUP on ${OS_TYPE}/${OS_ID}($OS_ARCH)"

    case "$OS_TYPE" in
        Linux)
            # Run the specific OS installers before the general purpose linux one
            check_and_exec_function "${OS_ID}"

            check_and_exec_function linux

            unset -f "${OS_ID}" linux
            ;;
        Darwin)
            check_and_exec_function macos

            unset -f macos darwin
            ;;
        *)
            log_error "Not a supported OS"

            # This is invoked directly, we can safely ignore it, as it does actually work
            # shellcheck disable=SC2317
            exit 1
            ;;
    esac

    # perhaps there's a generic install for all operating systems. Eg uv
    check_and_exec_function generic
    unset -f generic

    # Run container-specific hooks for cleanup, etc.
    if is_container; then
        log_debug "Container environment detected"
        check_and_exec_function container
        unset -f container
    fi
}
