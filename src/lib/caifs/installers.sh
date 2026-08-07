BINDIR=$(dirname "$0")
. "${BINDIR}"/../lib/caifs/utils.sh

# Installs packages vis homebrew without confirmation
# $@ packages and any further options
brew_install() {
    has_or_exit brew
    brew install --yes "$@"
}

# Uninstalls packages vis homebrew without confirmation
# $@ packages and any further options
brew_uninstall() {
    has_or_exit brew
    brew uninstall --yes "$@"
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

# Install packages via apt-get for debian and ubuntu
# rudimentary checks are in place to determine if and update is required
# $@ packages and options to install
apt_install() {
    has_or_exit apt-get

    if ! ls -l /var/lib/apt/lists/; then
        rootdo apt-get update
    fi

    rootdo apt-get install -y "$@"
}

# uninstall packages via apt-get for debian and ubuntu
# $@packages and options to uninstall
apt_uninstall() {
    has_or_exit apt-get
    rootdo apt-get uninstall -y "$@"
}

# This helper function can be used for installing tools via uv
# If a corresponding env var of the form $<PACKAGE NAME>_VERSION exists, then this is assumed to be
# a version number required for the package. It will be appended to the uv install command via the == syntax
# It also respects the LINK_ROOT option, if the LINK_ROOT is the default of $HOME, then the standard `.local` prefix is
# added, otherwise it is assumed a user knows what they are doing and have specified a custom path
# $1 name of the tool to install via uv
uv_install() {
    _func="uv_install:"
    has_or_exit uv
    PACKAGE=$1
    shift 1

    log_info "Using uv installer for managing $PACKAGE"

    # Need to override the install base dir in the case of when a custom link root is specified. If it is the default,
    # then we need to append the .local path. Otherwise, assume it is correct
    local_link_root=$LINK_ROOT
    if [ "$LINK_ROOT" = "$HOME" ]; then
        local_link_root="$LINK_ROOT/.local"
    fi

    UV_TOOL_DIR="${local_link_root}/share/uv/tools" \
    UV_TOOL_BIN_DIR="${local_link_root}/bin" \
      uv tool install --upgrade "$PACKAGE" "$@"
}

# Removes a package via a uv tool install
uv_uninstall() {
    uv tool uninstall "$@"
}

# Install a package via npm.
# You should ensure that the nodejs hook has been run previously, otherwise packages will be
# installed to non-shell aware locations.
# NOTE: This function relies on an injected version variable, which is specified at the command line
# $1 name of the package
npm_install() {
    _func="npm_install:"
    has_or_exit npm
    PACKAGE=$1
    shift 1

    log_info "Using npm installer for managing $PACKAGE"

    local_link_root=$LINK_ROOT
    if [ "$LINK_ROOT" = "$HOME" ]; then
        local_link_root="$LINK_ROOT/.local"
    fi
    npm config set prefix "$local_link_root"
    # npm has a bug where trailing spaces after the package name get added to the package
    # so we smoosh the trailing args up tight with the package name
    log_debug "$_func installing the following command \"${PACKAGE}$*\""
    npm install --global "${PACKAGE}$*"
}

# Removes a managed package via npm
npm_uninstall() {
    npm uninstall --global "$@"
}



# Installs previously linked certificiates from $LOCAL_CERT_DIR into the specific trust chain of the current OS
install_certs() {
    cert_dir="$(get_link_root)/${LOCAL_CERT_DIR}"
    for cert in "$cert_dir"/*; do
        [ -e "$cert" ] || continue
        cert_name=$(basename "$cert")
        log_info "Importing CA '$cert_name' for ${OS_TYPE}/${OS_ID}"
        case "$OS_TYPE" in
            Linux)
                check_and_exec_function "${OS_ID}_cert_handler" "$cert_name" "$cert_dir"
                ;;
            Darwin)
                check_and_exec_function "macos_cert_handler" "$cert_name" "$cert_dir"
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
arch_cert_handler() {
    dry_or_exec rootdo cp "$2/$1" "/etc/ca-certificates/trust-source/anchors/${1}.pem"
    dry_or_exec rootdo update-ca-trust
}

# $1: cert name
# $2: location directory of cert $1
rhel_cert_handler() {
    dry_or_exec rootdo cp "$2/$1" "/etc/pki/ca-trust/source/anchors/${1}.pem"
    dry_or_exec rootdo update-ca-trust
}

# $1: cert name
# $2: location directory of cert $1
debian_cert_handler() {
    dry_or_exec rootdo cp "$2/$1" "/usr/local/share/ca-certificates/${1}.crt"
    dry_or_exec rootdo update-ca-certificates
}

alpine_cert_handler() {
    debian_cert_handler "$@"
}

steamos_cert_handler() {
    arch_cert_handler "$@"
}

ubuntu_cert_handler() {
    debian_cert_handler "$@"
}

fedora_cert_handler() {
    rhel_cert_handler "$@"
}
