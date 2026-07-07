

generic() {
    # escape the TMPDIR/HOOKS//Target dir/project dir
    # I don't think I like this that much
    cp -r ../../../../src/* "${CAIFS_INSTALL_DIR}"/
    chmod +x "${CAIFS_INSTALL_DIR}"/bin/caifs
    caifs_install
}
