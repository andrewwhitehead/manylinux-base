#!/bin/bash
# Helper utilities for build


function check_var {
    if [ -z "$1" ]; then
        echo "required variable not defined"
        exit 1
    fi
}


function fetch_source {
    # This is called both inside and outside the build context (e.g. in Travis) to prefetch
    # source tarballs, where curl exists (and works)
    local file=$1
    check_var ${file}
    local url=$2
    check_var ${url}
    if [ -f ${file} ]; then
        echo "${file} exists, skipping fetch"
    else
        curl -fsSL -o ${file} ${url}/${file}
    fi
}


function check_sha256sum {
    local fname=$1
    check_var ${fname}
    local sha256=$2
    check_var ${sha256}

    echo "${sha256}  ${fname}" > ${fname}.sha256
    sha256sum -c ${fname}.sha256
    rm -f ${fname}.sha256
}


function build_git {
    local git_fname=$1
    check_var ${git_fname}
    local git_sha256=$2
    check_var ${git_sha256}
    check_var ${GIT_DOWNLOAD_URL}
    fetch_source ${git_fname}.tar.gz ${GIT_DOWNLOAD_URL}
    check_sha256sum ${git_fname}.tar.gz ${git_sha256}
    tar -xzf ${git_fname}.tar.gz
    (cd ${git_fname} && make -j$(nproc) install prefix=/usr/local NO_GETTEXT=1 NO_TCLTK=1 > /dev/null)
    rm -rf ${git_fname} ${git_fname}.tar.gz
}


function do_standard_install {
    ./configure "$@" > /dev/null
    make -j$(nproc) > /dev/null
    make -j$(nproc) install > /dev/null
}


function build_autoconf {
    local autoconf_fname=$1
    check_var ${autoconf_fname}
    local autoconf_sha256=$2
    check_var ${autoconf_sha256}
    check_var ${AUTOCONF_DOWNLOAD_URL}
    fetch_source ${autoconf_fname}.tar.gz ${AUTOCONF_DOWNLOAD_URL}
    check_sha256sum ${autoconf_fname}.tar.gz ${autoconf_sha256}
    tar -zxf ${autoconf_fname}.tar.gz
    (cd ${autoconf_fname} && do_standard_install)
    rm -rf ${autoconf_fname} ${autoconf_fname}.tar.gz
}


function build_automake {
    local automake_fname=$1
    check_var ${automake_fname}
    local automake_sha256=$2
    check_var ${automake_sha256}
    check_var ${AUTOMAKE_DOWNLOAD_URL}
    fetch_source ${automake_fname}.tar.gz ${AUTOMAKE_DOWNLOAD_URL}
    check_sha256sum ${automake_fname}.tar.gz ${automake_sha256}
    tar -zxf ${automake_fname}.tar.gz
    (cd ${automake_fname} && do_standard_install)
    rm -rf ${automake_fname} ${automake_fname}.tar.gz
}


function build_libtool {
    local libtool_fname=$1
    check_var ${libtool_fname}
    local libtool_sha256=$2
    check_var ${libtool_sha256}
    check_var ${LIBTOOL_DOWNLOAD_URL}
    fetch_source ${libtool_fname}.tar.gz ${LIBTOOL_DOWNLOAD_URL}
    check_sha256sum ${libtool_fname}.tar.gz ${libtool_sha256}
    tar -zxf ${libtool_fname}.tar.gz
    (cd ${libtool_fname} && do_standard_install)
    rm -rf ${libtool_fname} ${libtool_fname}.tar.gz
}

function build_libxcrypt {
    curl -fsSLO "$LIBXCRYPT_DOWNLOAD_URL"/v"$LIBXCRYPT_VERSION"
    check_sha256sum "v$LIBXCRYPT_VERSION" "$LIBXCRYPT_HASH"
    tar xfz "v$LIBXCRYPT_VERSION"
    pushd "libxcrypt-$LIBXCRYPT_VERSION"
    ./autogen.sh > /dev/null
    do_standard_install \
        --disable-obsolete-api \
        --enable-hashes=all \
        --disable-werror
    # we also need libcrypt.so.1 with glibc compatibility for system libraries
    # c.f https://github.com/pypa/manylinux/issues/305#issuecomment-625902928
    make clean > /dev/null
    sed -r -i 's/XCRYPT_([0-9.])+/-/g;s/(%chain OW_CRYPT_1.0).*/\1/g' lib/libcrypt.map.in
    DESTDIR=$(pwd)/so.1 do_standard_install \
        --disable-xcrypt-compat-files \
        --enable-obsolete-api=glibc \
        --enable-hashes=all \
        --disable-werror
    cp -P ./so.1/usr/local/lib/libcrypt.so.1* /usr/local/lib/
    popd
    rm -rf "v$LIBXCRYPT_VERSION" "libxcrypt-$LIBXCRYPT_VERSION"

    # Delete GLIBC version headers and libraries
    rm -rf /usr/include/crypt.h
    rm -rf /usr/lib*/libcrypt.a /usr/lib*/libcrypt.so /usr/lib*/libcrypt.so.1
}

function build_patchelf {
    local patchelf_version=$1
    local patchelf_hash=$2
    local src_dir=$(dirname $(readlink -f "${BASH_SOURCE[0]}"))
    curl -fsSL -o patchelf.tar.gz https://github.com/NixOS/patchelf/archive/$patchelf_version.tar.gz
    check_sha256sum patchelf.tar.gz $patchelf_hash
    tar -xzf patchelf.tar.gz
    (cd patchelf-$patchelf_version && ./bootstrap.sh && do_standard_install)
    rm -rf patchelf.tar.gz patchelf-$patchelf_version
}
