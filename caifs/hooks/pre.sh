

generic() {
    cp -r ../../src/* "${CAIFS_INSTALL_DIR}"/
    chmod +x "${CAIFS_INSTALL_DIR}"/bin/caifs
    caifs_install
}
