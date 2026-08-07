BINDIR=$(dirname "$0")
. "${BINDIR}"/../lib/caifs/utils.sh


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
# $1: target name
# $2: collection path
# $3: root directory to link the files in
create_target_links() {
    _func="create_target_links:"
    target="$1"
    collection_path="$2"
    link_root=$3

    log_debug "$_func create_target_links: BEGIN collection_path=$collection_path target=$target link_root=$link_root"

    if [ "$RUN_LINKS" -ne 0 ]; then
        log_debug "$_func Not running links as it is disabled RUN_LINKS=$RUN_LINKS"
        return 0
    fi

    # if in a container or wsl environment, enable extra search directories. These specific
    # environments take priority to the standard 'config' one, which comes last in the find
    target_directory="$(config_directories "${collection_path}/${target}")"

    log_debug "$_func using target_directory=$target_directory"

    for config_dir in $target_directory; do
        for config_file in $(files_in_dir "$config_dir"); do

            log_debug "$_func Processing $config_dir/$config_file"

            # Form the source path of the link, which is a path to the current config file
            src_path="$config_dir/$config_file"
            dest_file=$config_file
            require_escalation=1

            log_debug "$_func Initially src_path=$src_path dest_file=$config_file"
            # replace any variable place holders in the relative path, to form a destination path
            dest_file=$(replace_vars_in_string "$config_file")
            rc=$?
            log_debug "$_func Return code from replace_vars_in_string rc=$rc"
            if [ "$rc" -ne 0 ]; then
                log_warn "$config_file has missing variables or incorrect syntax and will be skipped"
                continue
            fi

            # in case the variable was at the beginning of the path and containers a $HOME reference,
            # strip the $link_root from the dest_path to avoid double-ups.
            # TODO: This feels like a work-around and should be cleaner
            dest_path="${dest_file#"$link_root"}"
            log_debug "$_func Stripped $link_root from $dest_file to form $dest_path"
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
        ensure_permissions "$basedir" "$require_escalation"
    fi

    link_cmd="ln -s $source_file $dest_link"
    # if the destination link, starts with a / then we need to escalate to root
    if [ "$require_escalation" -eq 0 ]; then
        link_cmd="rootdo $link_cmd"
    fi

    log_info "Creating Link $source_file -> $dest_link"
    dry_or_exec "$link_cmd"

    ensure_permissions "$dest_link" "$require_escalation"
}
