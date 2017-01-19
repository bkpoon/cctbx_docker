FROM centos:6.8
MAINTAINER "Billy Poon" bkpoon@lbl.gov
ENV container docker

# arguments
ARG NCPU=4

# software versions
ENV PSDM_VER 0.15.5
ENV CCTBX_SRC xfel_20151230.tar.xz

# upgrade OS and install base packages for psdm
# https://confluence.slac.stanford.edu/display/PSDM/System+packages+for+rhel6
# fix libmysqlclient.so symbolic link
RUN yum update -y && \
    yum -y install alsa-lib atk compat-libf2c-34 fontconfig freetype gsl \
    libgfortran libgomp libjpeg libpng libpng-devel pango postgresql-libs \
    unixODBC libICE libSM libX11 libXext libXft libXinerama libXpm \
    libXrender libXtst libXxf86vm mesa-libGL mesa-libGLU gtk2 \
    xorg-x11-fonts-Type1 xorg-x11-fonts-base xorg-x11-fonts-100dpi \
    xorg-x11-fonts-truetype xorg-x11-fonts-75dpi xorg-x11-fonts-misc \
    tar xz which gcc gcc-c++ mysql libibverbs openssh-server openssh \
    gcc-gfortran

# install psdm
# https://confluence.slac.stanford.edu/display/PSDM/Software+Distribution
ADD http://pswww.slac.stanford.edu/psdm-repo/dist_scripts/site-setup.sh \
    /reg/g/psdm/
RUN sh /reg/g/psdm/site-setup.sh /reg/g/psdm
ENV SIT_ROOT=/reg/g/psdm
ENV PATH=/reg/g/psdm/sw/dist/apt-rpm/rhel6-x86_64/bin:$PATH
ENV APT_CONFIG=/reg/g/psdm/sw/dist/apt-rpm/rhel6-x86_64/etc/apt/apt.conf
RUN apt-get -y update && \
    apt-get -y install psdm-release-ana-${PSDM_VER}-x86_64-rhel6-gcc44-opt && \
    ln -s /reg/g/psdm/sw/releases/ana-${PSDM_VER} \
          /reg/g/psdm/sw/releases/ana-current

# use old HDF5 (1.8.6) for compatibility with cctbx.xfel
ADD https://www.hdfgroup.org/ftp/HDF5/releases/hdf5-1.8.6/bin/linux-x86_64/hdf5-1.8.6-linux-x86_64-shared.tar.gz .
#COPY ./hdf5-1.8.6-linux-x86_64-shared.tar.gz .
RUN tar -xf hdf5-1.8.6-linux-x86_64-shared.tar.gz &&\
    mkdir -p /reg/g/psdm/sw/external/hdf5/1.8.6 &&\
    mv hdf5-1.8.6-linux-x86_64-shared \
       /reg/g/psdm/sw/external/hdf5/1.8.6/x86_64-rhel6-gcc44-opt

# =============================================================================
# Install mpich for NERSC
# https://github.com/NERSC/shifter/blob/master/doc/mpi/mpich_abi.rst
WORKDIR /usr/local/src
ADD http://www.mpich.org/static/downloads/3.2/mpich-3.2.tar.gz /usr/local/src/
RUN tar xf mpich-3.2.tar.gz && \
    cd mpich-3.2 && \
    ./configure && \
    make -j ${NCPU} && make install && \
    cd /usr/local/src && \
    rm -rf mpich-3.2

# old way
# WORKDIR /
# COPY ./optcray_alva.tar /
# RUN tar -xf optcray_alva.tar && \
#     printf "/opt/cray/mpt/default/gni/mpich2-gnu/48/lib\n" >> /etc/ld.so.conf && \
#     printf "/opt/cray/pmi/default/lib64\n" >> /etc/ld.so.conf && \
#     printf "/opt/cray/ugni/default/lib64\n" >> /etc/ld.so.conf && \
#     printf "/opt/cray/udreg/default/lib64\n" >> /etc/ld.so.conf && \
#     printf "/opt/cray/xpmem/default/lib64\n" >> /etc/ld.so.conf && \
#     printf "/opt/cray/alps/default/lib64\n" >> /etc/ld.so.conf && \
#     printf "/opt/cray/wlm_detect/default/lib64\n" >> /etc/ld.so.conf && \
#     printf "/opt/cray/wlm_detect/default/lib64/libwlm_detect.so.0" >> /etc/ld.so.preload && \
#     ldconfig

# ### replace psdm mpi4py with cray-tuned one
# ### TODO it would be nice if this could use the existing scons build system
# WORKDIR /usr/src
# ADD https://bitbucket.org/mpi4py/mpi4py/downloads/mpi4py-1.3.1.tar.gz /usr/src/
# ADD mpi.cfg /usr/src/
# RUN source /reg/g/psdm/etc/ana_env.sh && \
#     mkdir -p mpi4py && \
#     tar xf mpi4py-1.3.1.tar.gz -C mpi4py --strip-components=1 && \
#     mv mpi.cfg mpi4py && \
#     cd mpi4py && \
#     mv /reg/g/psdm/sw/external/mpi4py/1.3.1d /reg/g/psdm/sw/external/mpi4py/1.3.1d.orig && \
#     mkdir -p /reg/g/psdm/sw/external/mpi4py/1.3.1d/x86_64-rhel6-gcc44-opt && \
#     python setup.py build && \
#     python setup.py install --prefix=/reg/g/psdm/sw/external/mpi4py/1.3.1d/x86_64-rhel6-gcc44-opt && \
#     cd / && rm -rf /usr/src/mpi4py

# =============================================================================

# build myrelease
WORKDIR /reg/g
RUN source /reg/g/psdm/etc/ana_env.sh &&\
    newrel ana-${PSDM_VER} myrelease &&\
    cd myrelease &&\
    source sit_setup.sh &&\
    newpkg my_ana_pkg

# copy cctbx.xfel from local tarball
RUN mkdir -p /reg/g/cctbx
WORKDIR /reg/g/cctbx
COPY ./${CCTBX_SRC} /reg/g/cctbx/${CCTBX_SRC}
RUN tar -Jxf ./${CCTBX_SRC}

# build cctbx.xfel
# make needs to be run multiple times to ensure complete build (bug)
ENV CPATH=/reg/g/psdm/sw/releases/ana-${PSDM_VER}/arch/x86_64-rhel6-gcc44-opt/geninc
#:/reg/g/psdm/sw/releases/ana-${PSDM_VER}/arch/x86_64-rhel6-gcc44-opt/geninc/hdf5
ENV LD_LIBRARY_PATH=/reg/g/psdm/sw/releases/ana-${PSDM_VER}/arch/x86_64-rhel6-gcc44-opt/lib
RUN source /reg/g/psdm/etc/ana_env.sh &&\
    cd /reg/g/myrelease &&\
    sit_setup.sh &&\
    cd /reg/g/cctbx &&\
    python ./modules/cctbx_project/libtbx/auto_build/bootstrap.py build \
    --builder=xfel --with-python=`which python` --nproc=${NCPU} &&\
    cd build &&\
    make -j ${NCPU} &&\
    make -j ${NCPU}

# finish building myrelease
RUN source /reg/g/psdm/etc/ana_env.sh &&\
    cd /reg/g/myrelease &&\
    source /reg/g/psdm/bin/sit_setup.sh &&\
    source /reg/g/cctbx/build/setpaths.sh &&\
    cd my_ana_pkg &&\
    ln -s /reg/g/cctbx/modules/cctbx_project/xfel/cxi/cspad_ana src &&\
    cd .. &&\
    scons

# recreate /reg/d directories for data
RUN mkdir -p /reg/d/psdm/cxi &&\
    mkdir -p /reg/d/psdm/CXI
