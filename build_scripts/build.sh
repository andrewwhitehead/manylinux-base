#!/bin/bash
# Top-level build script called from Dockerfile

# Stop at any error, show all commands
set -ex

# Set build environment variables
MY_DIR=$(dirname "${BASH_SOURCE[0]}")
. $MY_DIR/build_env.sh

# Libraries that are allowed as part of the manylinux2014 profile
# Extract from PEP: https://www.python.org/dev/peps/pep-0599/#the-manylinux2014-policy
# On RPM-based systems, they are provided by these packages:
# Package:    Libraries
# glib2:      libglib-2.0.so.0, libgthread-2.0.so.0, libgobject-2.0.so.0
# glibc:      libresolv.so.2, libutil.so.1, libnsl.so.1, librt.so.1, libpthread.so.0, libdl.so.2, libm.so.6, libc.so.6
# libICE:     libICE.so.6
# libX11:     libX11.so.6
# libXext:    libXext.so.6
# libXrender: libXrender.so.1
# libgcc:     libgcc_s.so.1
# libstdc++:  libstdc++.so.6
# mesa:       libGL.so.1
#
# PEP is missing the package for libSM.so.6 for RPM based system
# Install development packages (except for libgcc which is provided by gcc install)
MANYLINUX_DEPS="glibc-devel libstdc++-devel glib2-devel libX11-devel libXext-devel libXrender-devel mesa-libGL-devel libICE-devel libSM-devel"

CMAKE_DEPS="openssl-devel zlib-devel libcurl-devel"

# Get build utilities
source $MY_DIR/build_utils.sh

# See https://unix.stackexchange.com/questions/41784/can-yum-express-a-preference-for-x86-64-over-i386-packages
echo "multilib_policy=best" >> /etc/yum.conf
# Error out if requested packages do not exist
echo "skip_missing_names_on_install=False" >> /etc/yum.conf
# Make sure that locale will not be removed
sed -i '/^override_install_langs=/d' /etc/yum.conf

# https://hub.docker.com/_/centos/
# "Additionally, images with minor version tags that correspond to install
# media are also offered. These images DO NOT recieve updates as they are
# intended to match installation iso contents. If you choose to use these
# images it is highly recommended that you include RUN yum -y update && yum
# clean all in your Dockerfile, or otherwise address any potential security
# concerns."
# Decided not to clean at this point: https://github.com/pypa/manylinux/pull/129
yum -y update
yum -y install yum-utils curl
yum-config-manager --enable extras

if ! which localedef &> /dev/null; then
    # somebody messed up glibc-common package to squeeze image size, reinstall the package
    yum -y reinstall glibc-common
fi

# upgrading glibc-common can end with removal on en_US.UTF-8 locale
localedef -i en_US -f UTF-8 en_US.UTF-8

TOOLCHAIN_DEPS="devtoolset-9-binutils devtoolset-9-gcc devtoolset-9-gcc-c++ devtoolset-9-gcc-gfortran"
if [ "${AUDITWHEEL_ARCH}" == "x86_64" ]; then
    # Software collection (for devtoolset-9)
    yum -y install centos-release-scl-rh
    # EPEL support (for yasm)
    yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
    YASM=yasm
elif [ "${AUDITWHEEL_ARCH}" == "aarch64" ] || [ "${AUDITWHEEL_ARCH}" == "ppc64le" ] || [ "${AUDITWHEEL_ARCH}" == "s390x" ]; then
    # Software collection (for devtoolset-9)
    yum -y install centos-release-scl-rh
elif [ "${AUDITWHEEL_ARCH}" == "i686" ]; then
    # No yasm on i686
    # Install mayeut/devtoolset-9 repo to get devtoolset-9
    curl -fsSLo /etc/yum.repos.d/mayeut-devtoolset-9.repo https://copr.fedorainfracloud.org/coprs/mayeut/devtoolset-9/repo/custom-1/mayeut-devtoolset-9-custom-1.repo
fi

# Development tools and libraries
yum -y install \
    autoconf \
    automake \
    bison \
    bzip2 \
    ${TOOLCHAIN_DEPS} \
    diffutils \
    expat-devel \
    gettext \
    file \
    kernel-devel \
    libffi-devel \
    make \
    patch \
    unzip \
    which \
    ${YASM} \
    ${CMAKE_DEPS}

# Install git
build_git $GIT_ROOT $GIT_HASH
git version

# Install newest automake
build_automake $AUTOMAKE_ROOT $AUTOMAKE_HASH
automake --version

# Install newest libtool
build_libtool $LIBTOOL_ROOT $LIBTOOL_HASH
libtool --version

# Install a recent version of cmake3
curl -L -O $CMAKE_DOWNLOAD_URL/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}.tar.gz
check_sha256sum cmake-${CMAKE_VERSION}.tar.gz $CMAKE_HASH
tar -xzf cmake-${CMAKE_VERSION}.tar.gz
cd cmake-${CMAKE_VERSION}
./bootstrap --system-curl --parallel=$(nproc)
make -j$(nproc)
make install
cd ..
rm -rf cmake-${CMAKE_VERSION}

# Install a more recent SQLite3
curl -fsSLO $SQLITE_AUTOCONF_DOWNLOAD_URL/$SQLITE_AUTOCONF_VERSION.tar.gz
check_sha256sum $SQLITE_AUTOCONF_VERSION.tar.gz $SQLITE_AUTOCONF_HASH
tar xfz $SQLITE_AUTOCONF_VERSION.tar.gz
cd $SQLITE_AUTOCONF_VERSION
do_standard_install
cd ..
rm -rf $SQLITE_AUTOCONF_VERSION*
rm /usr/local/lib/libsqlite3.a

# Install libcrypt.so.1 and libcrypt.so.2
build_libxcrypt "$LIBXCRYPT_DOWNLOAD_URL" "$LIBXCRYPT_VERSION" "$LIBXCRYPT_HASH"

# Install patchelf (latest with unreleased bug fixes) and apply our patches
build_patchelf $PATCHELF_VERSION $PATCHELF_HASH

# Clean up development headers and other unnecessary stuff for
# final image
yum -y erase gettext expat-devel perl-devel
yum -y install ${MANYLINUX_DEPS}
yum -y clean all > /dev/null 2>&1
yum list installed

# Fix libc headers to remain compatible with C99 compilers.
find /usr/include/ -type f -exec sed -i 's/\bextern _*inline_*\b/extern __inline __attribute__ ((__gnu_inline__))/g' {} +

if [ "${DEVTOOLSET_ROOTPATH:-}" != "" ]; then
    # remove useless things that have been installed by devtoolset
    rm -rf $DEVTOOLSET_ROOTPATH/usr/share/man
    find $DEVTOOLSET_ROOTPATH/usr/share/locale -mindepth 1 -maxdepth 1 -not \( -name 'en*' -or -name 'locale.alias' \) | xargs rm -rf
fi

# rm -rf /usr/share/backgrounds

# if we updated glibc, we need to strip locales again...
localedef --list-archive | grep -v -i ^en_US.utf8 | xargs localedef --delete-from-archive
mv -f /usr/lib/locale/locale-archive /usr/lib/locale/locale-archive.tmpl
build-locale-archive
find /usr/share/locale -mindepth 1 -maxdepth 1 -not \( -name 'en*' -or -name 'locale.alias' \) | xargs rm -rf
find /usr/local/share/locale -mindepth 1 -maxdepth 1 -not \( -name 'en*' -or -name 'locale.alias' \) | xargs rm -rf
rm -rf /usr/local/share/man
