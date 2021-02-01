FROM centos:7
LABEL maintainer="Andrew Whitehead"

ENV AUDITWHEEL_ARCH=x86_64 \
    AUDITWHEEL_PLAT=manylinux2014_$AUDITWHEEL_ARCH \
    LC_ALL=en_US.UTF-8 \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US.UTF-8 \
    DEVTOOLSET_ROOTPATH=/opt/rh/devtoolset-9/root \
    PKG_CONFIG_PATH=/usr/local/lib/pkgconfig
ENV PATH=$DEVTOOLSET_ROOTPATH/usr/bin:/root/.cargo/bin:$PATH
ENV LD_LIBRARY_PATH=$DEVTOOLSET_ROOTPATH/usr/lib64:$DEVTOOLSET_ROOTPATH/usr/lib:$DEVTOOLSET_ROOTPATH/usr/lib64/dyninst:$DEVTOOLSET_ROOTPATH/usr/lib/dyninst:/usr/local/lib64:/usr/local/lib

COPY build_scripts /build_scripts
RUN bash build_scripts/build.sh && rm -r build_scripts

COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
