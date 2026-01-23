#!/bin/sh

# Log debug to standard error, so we can use debug logging in functions, without impacting
# the stdout returns
log_debug() {
    if [ "$VERBOSE" -eq 0 ]; then
        echo "DEBUG: $*" >&2
    fi
}

# For general information that is useful for the user to see
log_info() {
    echo "INFO: $*"
}

# Information that is unexpected, but acknowledged and catered for
# eg file conflicts
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

##
## Some globals. These can generally be overridden via environment variables with the CAIFS_ prefix
# By default, run both links and hooks
# shellcheck disable=SC2034
VERSION=0.5.0

HOOKS_DIR=hooks

# Local directory for linking certificates into
LOCAL_CERT_DIR=~/.local/share/certificates
LOCAL_COLLECTION_DIR=${CAIFS_LOCAL_COLLECTIONS:-"$HOME/.local/share/caifs-collections"}

# Force the override of existing link targets
RUN_FORCE=${CAIFS_RUN_FORCE:-1}

# Whether to run links and/or hooks. Defaults to true (0) for both
RUN_LINKS=${CAIFS_RUN_LINKS:-0}
RUN_HOOKS=${CAIFS_RUN_HOOKS:-0}
RUN_TARGETS=""

# Multiple targets could be specified. We will run them in order
VERBOSE=${CAIFS_VERBOSE:=1}
DRY_RUN=${CAIFS_DRY_RUN:-1}

# A list of directories to interogate for caifs collections
CAIFS_COLLECTIONS=${CAIFS_COLLECTIONS:-""}

# The root directory of where config should link to. By default it should be home, but for root scenarios
# this can be overridden
LINK_ROOT=${CAIFS_LINK_ROOT:-$HOME}

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
    RUN_HOOKS=${1}
}

set_run_links() {
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
    RUN_FORCE=${1}
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

# returns a loopable string of files found within the supplied directory
# $1: The directory to search
files_in_dir() {
    find "${1}" \( -type f -o -type l \) -printf "%P\n" 2>/dev/null
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
            CAIFS_COLLECTIONS="$CAIFS_COLLECTIONS:$collection_dir"
        fi

    done

    # Finally add the caifs-common lib to the end
    if [ -d "$LOCAL_COLLECTION_DIR/caifs-common" ]; then
        CAIFS_COLLECTIONS="$CAIFS_COLLECTIONS:$LOCAL_COLLECTION_DIR/caifs-common"
    fi
    log_debug "populate_caifs_collections: END"
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
    echo "$config_directories"
}

# Run a specific type of hook for a given target.
# The script is sourced to give access to all the caifs runtime variables.
# $1: collection path
# $2: target
# $3: hook type [pre|post|rm]
run_hook() {
    collection_path="$1"
    target=$2
    hook_type=$3

    if [ "$RUN_HOOKS" -ne 0 ]; then
        log_debug "Not running ${hook_type}-hook for target '$target' in collection $collection_path"
        return 0
    fi

    log_debug "Running ${hook_type}-hook for target '$target' in collection $collection_path"

    if [ -f "$collection_path/$target/$HOOKS_DIR/${hook_type}.sh" ]; then
        TMP_DIR=$(mktemp -d)
        cd "${TMP_DIR}" || exit

        # shellcheck disable=SC1090
        # import the hook script functions
        . "$collection_path/$target/$HOOKS_DIR/${hook_type}.sh"

        run_hook_functions

        cd - || exit
        rm -rf "${TMP_DIR}"
    else
        log_debug "No ${hook_type}-hook found for target '$target'. Ignoring"
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


# Check if a target has any linked files
# $1: collection path
# $2: target name
# $3: link root
# Returns 0 if linked, 1 if not
is_target_linked() {
    collection_path="$1"
    target="$2"
    link_root="$3"

    target_directory="$(config_directories "${collection_path}/${target}")"
    log_debug "using target_directory=$target_directory"

    for config_dir in $target_directory; do
        for config_file in $(files_in_dir "$config_dir"); do
            dest_link="$link_root/$config_file"
            src_config_file="$config_dir/$config_file"
            log_debug "Checking if dest_link=$dest_link is linked to $src_config_file"

            if [ -L "$dest_link" ]; then
                # Verify the symlink points to our target
                link_target=$(readlink "$dest_link")
                if [ "$link_target" = "$src_config_file" ]; then
                    log_debug "$src_config_file is -> $link_target"
                    return 0
                fi
            fi
        done
    done
    return 1
}

# Creates symbolic links for all files under the target config directory
# It creates the directory structure, if it doesn't exist already
# $1: collection path
# $2: target
# $3: root directory to link the files in
create_target_links() {
    collection_path="$1"
    target=$2
    link_root=$3

    log_debug "create_target_links: BEGIN collection_path=$collection_path target=$target link_root=$link_root"

    if [ "$RUN_LINKS" -ne 0 ]; then
        log_debug "Not running links as it is disabled RUN_LINKS=$RUN_LINKS"
        return 0
    fi

    # if in a container or wsl environment, enable extra search directories. These specific
    # environments take priority to the standard 'config' one, which comes last in the find
    target_directory="$(config_directories "${collection_path}/${target}")"

    log_debug "using target_directory=$target_directory"

    for config_dir in $target_directory; do
        for config_file in $(files_in_dir "$config_dir"); do

            log_debug "Processing $config_dir/$config_file"

            # Form the source path of the link, which is a path to the current config file
            src_path="$config_dir/$config_file"
            dest_file=$config_file
            require_escalation=1

            log_debug "Initially src_path=$src_path dest_file=$config_file"
            # replace any variable place holders in the relative path, to form a destination path
            dest_file=$(replace_vars_in_string "$config_file")
            rc=$?
            log_debug "Return code from replace_vars_in_string rc=$rc"
            if [ "$rc" -ne 0 ]; then
                log_warn "$config_file has missing variables or incorrect syntax and will be skipped"
                continue
            fi

            # in case the variable was at the beginning of the path and containers a $HOME reference,
            # strip the $link_root from the dest_path to avoid double-ups.
            # TODO: This feels like a work-around and should be cleaner
            dest_path="${dest_file#"$link_root"}"
            log_debug "Stripped $link_root from $dest_file to form $dest_path"
            dest_path="$link_root/$dest_path"

            # Check if the leading config entry has a ^ then we need to escalate to root
            is_root_config "$config_file"
            rc=$?
            if [ "$rc" -eq 0 ]; then
                # remove the caret from the start of the string
                dest_file=$(strip_leading_char "$dest_file")
                dest_path="/$dest_file"
                require_escalation=0
            fi

            #validate_path "$dest_file"
            create_link "$src_path" "$dest_path" "$require_escalation" "$RUN_FORCE"
        done
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

    if [ "$RUN_LINKS" -ne 0 ]; then
        log_debug "Not running remove_target_links as it is disabled RUN_LINKS=$RUN_LINKS"
        return 0
    fi

    # if in a container or wsl environment, enable extra search directories. These specific
    # environments take priority to the standard 'config' one, which comes last in the find
    target_directory="$(config_directories "${collection_path}/${target}")"

    for config_dir in $target_directory; do
        for config_file in $(files_in_dir "$config_dir"); do
            log_debug "Found ${config_dir}/${config_file}. Checking if link exists at $link_root/$config_file"
            if [ -L "$link_root/$config_file" ]; then

                unlink_cmd="unlink $link_root/${config_file}"
                if [ "$(is_root_config "$config_file")" ]; then
                    unlink_cmd="rootdo unlink /${config_file}"
                fi
                dry_or_exec "$unlink_cmd"
            fi
        done
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
        mkdir_cmd="mkdir -p $basedir"
        if [ "$require_escalation" -eq 0 ]; then
            mkdir_cmd="rootdo $mkdir_cmd"
        fi
        dry_or_exec "$mkdir_cmd"
    fi

    link_cmd="ln -s $source_file $dest_link"
    # if the destination link, starts with a / then we need to escalate to root
    if [ "$require_escalation" -eq 0 ]; then
        link_cmd="rootdo $link_cmd"
    fi

    log_info "Creating Link $source_file -> $dest_link"
    dry_or_exec "$link_cmd"
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

# Install packages via yay (AUR helper) without confirmation
# Arch being a rolling distro the concept of package versions are not really a thing
# $@ packages to install
yay_install() {
    has_or_exit yay
    yay -S --needed --noconfirm "$@"
}

# Uninstall packages via yay without confirmation
# $@ packages to uninstall
yay_uninstall() {
    has_or_exit yay
    yay -Rns --noconfirm "$@"
}

# This helper function can be used for installing tools via uv
# If a corresponding env var of the form $<PACKAGE NAME>_VERSION exists, then this is assumed to be
# a version number required for the package. It will be appended to the uv install command via the == syntax
# $1 name of the tool to install via uv
uv_install() {
    has_or_exit uv
    PACKAGE=$1
    shift 1

    log_debug "Attempting to install $PACKAGE"

    PACKAGE_VERSION=$(version_from_env "$PACKAGE")
    if [ -n "$PACKAGE_VERSION" ]; then
        log_debug "Found ${PACKAGE}_VERSION=$PACKAGE_VERSION"
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

# Installs previously linked certificiates from $LOCAL_CERT_DIR into the specific trust chain of the current OS
install_certs() {
    for cert in "${LOCAL_CERT_DIR}"/*; do
        log_info "Importing CA for ${OS_TYPE}/${OS_ID}"
        case "$OS_TYPE" in
            Linux)
                check_and_exec_function "${OS_ID}_cert_installer" "$cert" "$LOCAL_CERT_DIR"
                ;;
            Darwin)
                check_and_exec_function "macos_cert_installer" "$cert" "$LOCAL_CERT_DIR"
                ;;
            *)
                log_error "Not a support OS - ${OS_TYPE}"
                # This is invoked directly, we can safely ignore it, as it does actually work
                # shellcheck disable=SC2317
                exit 1
                ;;
        esac
    done
}

# $1: cert name
# $2: location directory of cert $1
arch_cert_hander() {
    rootdo cp "$2/$1" "/etc/ca-certificates/trust-source/anchors/${1}.pem"
    rootdo update-ca-trust
}

# $1: cert name
# $2: location directory of cert $1
rhel_cert_handler() {
    rootdo cp "$2/$1" "/etc/pki/ca-trust/source/anchors/${1}.pem"
    rootdo update-ca-trust
}

# $1: cert name
# $2: location directory of cert $1
debian_cert_handler() {
    rootdo cp "$2/$1" "/usr/local/share/ca-certificates/${1}.crt"
    rootdo update-ca-certificates
}

steamos_cert_hander() {
    arch_cert_handler "$@"
}

ubuntu_cert_handler() {
    debian_cert_handler "$@"
}

fedora_cert_handler() {
    rhel_cert_handler "$@"
}

# A utility that allows installing software from a hook script, with respect to the LINK_ROOT
# It performs root escalation, if the current LINK_ROOT is anchored at /
# Files will be copied recurisvely to the LINK_ROOT destination, so $1 path should be in required order
# $1: Path to install
# $2: Optional extra directory, useful for the LINK_ROOT=$HOME use case. Defaults to .local
caifs_install() {
    link_root_home=${2:-".local"}

    # If the intended LINK_ROOT starts with / then we escalate privileges
    if is_root_config "$LINK_ROOT"; then
        log_debug "Link root appears to reference / - escalating privileges for copy"
        dry_or_exec rootdo cp -r "$1" "$LINK_ROOT/"
    elif [ "$LINK_ROOT" = "$HOME" ]; then
        log_debug "Link root is the default \$HOME - copying to $LINK_ROOT/$link_root_home/"
        dry_or_exec cp -r "$1" "$LINK_ROOT/$link_root_home/"
    else
        # respect LINK_ROOT,but it appears to not need privileges
        dry_or_exec cp -r "$1" "$LINK_ROOT/"
    fi
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
