BINDIR=$(dirname "$0")
. "${BINDIR}"/../lib/caifs/utils.sh
. "${BINDIR}"/../lib/caifs/links.sh
. "${BINDIR}"/../lib/caifs/hooks.sh
#. utils.sh
#. links.sh


# command handler for running the remove action
# $1: collection paths to consider
# $2: targets to action
# $3: link root
cmd_remove() {
    collection_paths=$1
    run_targets=$2
    link_root=$3
    log_debug "cmd_remove: begin $*"

    while [ -n "$collection_paths" ]; do
        caifs_collection="${collection_paths%%:*}"

        log_debug "Working with $caifs_collection"

        # Cater for the --collection argument
        if valid_for_collection_path "$(get_collection_constraint)" "$caifs_collection"; then
            for target in $run_targets; do
                log_debug "$target"

                remove_target_links "${caifs_collection}" "${target}" "${link_root}"
                run_remove_hook "${caifs_collection}" "$target"

            done
        fi

        # Loop control, get the next path to operate on
        if [ "$caifs_collection" = "$collection_paths" ]; then
            # No more paths available. End the loop
            collection_paths=""
        else
            collection_paths="${collection_paths#*"${caifs_collection}":}"
        fi
    done

    log_debug "cmd_remove: end"
}

# Loop over the CAIFS_COLLECTIONS variable, which is colon (:) separated paths to caifs collections
# First target wins, so order in the collection is important.
# $1 collection_paths
# $2 targets - an array of 1 or more targets to add
# $3 link_root
cmd_add() {
    _func="cmd_add:"
    log_debug "cmd_add: begin $*"

    collection_paths="$1"
    run_targets="$2"
    link_root="$3"

    while [ -n "$collection_paths" ]; do

        caifs_collection="${collection_paths%%:*}"
        log_debug "$_func Working with $caifs_collection"

        # Cater for the --collection argument
        if valid_for_collection_path "$(get_collection_constraint)" "$caifs_collection"; then

            for t in $run_targets; do
                target=$(get_target "$t")
                collection=$(get_collection "$t")
                version_info=$(get_version_info "$t")

                log_debug "$_func target specificer $t sanitised to target=$target, version=$version_info and collection=$collection"

                if ! valid_for_collection_path "$collection" "$caifs_collection"; then
                    log_debug "collection '$collection' not valid for current caifs collection path '$caifs_collection' - skipping"
                    continue
                fi

                run_pre_hook "$t" "$caifs_collection"

                create_target_links "$target" "$caifs_collection" "${link_root}"

                run_post_hook "$t" "$caifs_collection"
            done
        fi

        # Loop control, get the next path to operate on
        if [ "$caifs_collection" = "$collection_paths" ]; then
            # No more paths available. End the loop
            collection_paths=""
        else
            collection_paths="${collection_paths#*"${caifs_collection}":}"
        fi
    done

    log_debug "$_func end"
}

# Display status of all targets in collections
# $1 collection_paths
# $2 link_root
cmd_status() {
    log_debug "cmd_status: begin $*"

    collection_paths=$1
    link_root=$2

    # Detect unicode support, fallback to ASCII
    case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
        *UTF-8*|*utf8*)
            CHECK="✓"; CROSS="✗"; DASH="-"
            ;;
        *)
            CHECK="Y"; CROSS="N"; DASH="-"
            ;;
    esac

    # Color codes for linked column (only if stdout is a terminal)
    if [ -t 1 ]; then
        GREEN='\033[0;32m'
        RED='\033[0;31m'
        NC='\033[0m'
    else
        GREEN=''; RED=''; NC=''
    fi

    # Print header
    printf "%-25s %-30s %-8s %s\n" "COLLECTION" "TARGET" "LINKED" "HOOKS"
    printf "%-25s %-30s %-8s %s\n" "$(printf '%0.s-' $(seq 1 25))" "$(printf '%0.s-' $(seq 1 30))" "------" "-----"

    while [ -n "$collection_paths" ]; do
        caifs_collection="${collection_paths%%:*}"
        collection_name=$(basename "$caifs_collection")

        log_debug "Checking collection: $caifs_collection"

        # Cater for the --collection argument
        if valid_for_collection_path "$(get_collection_constraint)" "$caifs_collection"; then

            # Find all targets (directories containing config/ or hooks/ subdirectory)
            if [ -d "$caifs_collection" ]; then
                for target_dir in "$caifs_collection"/*/; do
                    [ -d "$target_dir" ] || continue
                    target=$(basename "$target_dir")

                    log_debug "Checking if target_dir=$target_dir contains a valid structure"
                    is_valid_caifs_structure "$target_dir" || continue

                    # Check linked status (pad for alignment, color for linked column only)
                    if has_config "$target_dir"; then
                        log_debug "target_dir=$target_dir has config files"
                        if is_target_linked "$caifs_collection" "$target" "$link_root"; then
                            linked_status="${GREEN}${CHECK}${NC}       "
                        else
                            linked_status="${RED}${CROSS}${NC}       "
                        fi
                    else
                        linked_status="${DASH}       "
                    fi

                    # Check hooks status (has hooks/*.sh files)
                    if has_hooks "$target_dir"; then
                        log_debug "target_dir=$target_dir has hooks"
                        hooks_status="${CHECK}"
                    else
                        hooks_status="${CROSS}"
                    fi

                    printf "%-25s %-30s %b %s\n" "$collection_name" "$target" "$linked_status" "$hooks_status"
                done
            fi
        fi
        # Loop control
        if [ "$caifs_collection" = "$collection_paths" ]; then
            collection_paths=""
        else
            collection_paths="${collection_paths#*"${caifs_collection}":}"
        fi
    done
    log_debug "cmd_status : end"
}
