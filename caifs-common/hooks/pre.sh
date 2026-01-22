
generic() {

    LATEST_VERSION=$(github_latest_tag "caifs-org/caifs-common")
    VERSION=${CAIFS_COMMON_VERSION:-$LATEST_VERSION}

    curl -sL https://github.com/caifs-org/caifs-common/releases/download/v"${VERSION}"/release.tar.gz | tar -xzf -
    mkdir -p share/caifs-collections
    mv caifs-common share/caifs-collections/
    
    caifs_install "share" 
}
