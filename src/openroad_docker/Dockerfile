###############################################################################
# OpenROAD runtime for ICCAD 2025 Problem C
# Base: Ubuntu 22.04 + local OpenROAD .deb (same approach as the course README)
###############################################################################
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        wget \
        git \
        vim \
        python3 \
        python3-pip \
        libgomp1 \
        libtcl8.6 \
        tcl \
        tk \
        libqt5widgets5 \
        libqt5gui5 \
        libqt5core5a \
        libx11-6 \
        libxext6 \
        libxrender1 \
        libglu1-mesa \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/openroad_pkg

# Place the .deb next to this Dockerfile before build, e.g.:
#   openroad_2.0-17598-ga008522d8_amd64-ubuntu-22.04.deb
ARG OPENROAD_DEB=openroad_2.0-17598-ga008522d8_amd64-ubuntu-22.04.deb
COPY ${OPENROAD_DEB} /tmp/openroad.deb

RUN apt-get update \
    && apt-get install -y --no-install-recommends /tmp/openroad.deb \
    || (dpkg -i /tmp/openroad.deb || true; apt-get install -f -y) \
    && rm -f /tmp/openroad.deb \
    && rm -rf /var/lib/apt/lists/* \
    && command -v openroad

WORKDIR /workspace
CMD ["bash"]
