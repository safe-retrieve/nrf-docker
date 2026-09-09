FROM ubuntu:22.04 AS base
WORKDIR /workdir

# Set to 1 to create a slim version of the image.  This will remove unnecessary
# files to reduce the size of the image.
ARG SLIM=0

# Select tag from:
#   https://github.com/nrfconnect/sdk-nrf/tags
ARG SDK_NRF_BRANCH=v2.8.0

# Select branch from output of running 'nrfutil toolchain-manager search'.
# When this is changed, you also need to change ${TOOLCHAIN_ID} below.
ARG TOOLCHAIN_VERSION=v2.8.0

# Select by examining the download link for the *.tar.gz file for the Linux x86 64 version:
#   https://www.nordicsemi.com/Products/Development-tools/nRF-Command-Line-Tools/Download?lang=en#infotabs
ARG NORDIC_COMMAND_LINE_TOOLS_VERSION="10-24-2/nrf-command-line-tools-10.24.2"

ARG ARCH=amd64

ENV DEBIAN_FRONTEND=noninteractive

SHELL [ "/bin/bash", "-euxo", "pipefail", "-c" ]

# gcc-multilib make = Host tools for native_sim build
# gcc-12 g++-12 g++-12-multilib = Host compiler for the unit tests.  Ubuntu 22.04 gives GCC 11 by
#                 default, and GCC 12 is the first version that supplies the C++ header <expected>.
#                 The multilib package covers a 32-bit native_sim build.
# python 3.8 is installed by toolchain manager hence older version of libffi is required
RUN <<EOT
    apt-get -y update
    apt-get -y upgrade
    apt-get -y install wget unzip clang-format gcc-multilib make libffi7 \
        gcc-12 g++-12 g++-12-multilib
    # Install command line tool to inspect disk usage
    apt-get -y install ncdu
    apt-get -y clean
    rm -rf /var/lib/apt/lists/*
EOT

# Install toolchain
# Make nrfutil install in a shared location, because when used with GitHub
# Actions, the image will be launched with the home dir mounted from the local
# checkout.
#
# After installation, remove unnecessary files
ENV NRFUTIL_HOME=/usr/local/share/nrfutil
# This needs to be updated if ${TOOLCHAIN_VERSION} is changed.
ARG TOOLCHAIN_ID=b81a7cd864
ENV TOOLCHAIN_PY=/root/ncs/toolchains/${TOOLCHAIN_ID}/usr/local

RUN <<EOT
    wget --timeout=60 https://files.nordicsemi.com/artifactory/swtools/external/nrfutil/executables/x86_64-unknown-linux-gnu/nrfutil
    mv nrfutil /usr/local/bin/nrfutil
    chmod +x /usr/local/bin/nrfutil
    nrfutil install toolchain-manager
    nrfutil toolchain-manager search
    nrfutil toolchain-manager install --ncs-version ${TOOLCHAIN_VERSION}
    nrfutil toolchain-manager list
    # Remove any downloaded files
    rm -f /root/ncs/downloads/*
    if [ "${SLIM}" -ne 0 ]; then
        # Remove toolchains for non-arm archs
        rm -rf /root/ncs/toolchains/*/opt/zephyr-sdk/{riscv64-zephyr-elf,x86_64-zephyr-elf,arc-zephyr-elf,nios2-zephyr-elf,sparc-zephyr-elf,mips-zephyr-elf}
        # Remove files from Nordic setup
        rm -rf /root/ncs/toolchains/*/var
        # Remove unnecessary python packages
        PYTHON_BIN="${TOOLCHAIN_PY}/bin/python3"
        # Need to set the LD_LIBRARY_PATH to get python3 to run
        export LD_LIBRARY_PATH="${TOOLCHAIN_PY}/lib"
        # Packages to uninstall (not needed for CI firmware builds)
        $PYTHON_BIN -m pip uninstall -y pygments pillow lxml mypy capstone pyocd cmsis_pack_manager typecode numpy
        # Remove large files not installed by pip3
        rm -rf grpc grpc_tools licensedcode pdfminer
    fi
EOT

#
# ClangFormat
#
RUN <<EOT
    wget -qO- https://raw.githubusercontent.com/nrfconnect/sdk-nrf/${SDK_NRF_BRANCH}/.clang-format > /workdir/.clang-format
EOT

# Nordic command line tools
# Releases: https://www.nordicsemi.com/Products/Development-tools/nrf-command-line-tools/download
RUN <<EOT
    NCLT_BASE=https://nsscprodmedia.blob.core.windows.net/prod/software-and-other-downloads/desktop-software/nrf-command-line-tools/sw/versions-10-x-x
    echo "Host architecture: $ARCH"
    case $ARCH in
        "amd64")
            NCLT_URL="${NCLT_BASE}/${NORDIC_COMMAND_LINE_TOOLS_VERSION}_linux-amd64.tar.gz"
            ;;
        "arm64")
            NCLT_URL="${NCLT_BASE}/${NORDIC_COMMAND_LINE_TOOLS_VERSION}_linux-arm64.tar.gz"
            ;;
    esac
    echo "NCLT_URL=${NCLT_URL}"
    if [ ! -z "$NCLT_URL" ]; then
        mkdir tmp && cd tmp
        wget -qO - "${NCLT_URL}" | tar --no-same-owner -xz
        if [ "${SLIM}" -eq 0 ]; then
            # Install included JLink
            mkdir /opt/SEGGER
            tar xzf JLink_*.tgz -C /opt/SEGGER
            mv /opt/SEGGER/JLink* /opt/SEGGER/JLink
        fi
        # Install nrf-command-line-tools
        cp -r ./nrf-command-line-tools /opt
        ln -s /opt/nrf-command-line-tools/bin/nrfjprog /usr/local/bin/nrfjprog
        ln -s /opt/nrf-command-line-tools/bin/mergehex /usr/local/bin/mergehex
        cd .. && rm -rf tmp ;
    else
        echo "Skipping nRF Command Line Tools (not available for $ARCH)" ;
    fi
EOT

# Prepare image with a ready to use build environment
SHELL ["nrfutil","toolchain-manager","launch","/bin/bash","--","-c"]
RUN <<EOT
    west init -m https://github.com/nrfconnect/sdk-nrf --mr ${SDK_NRF_BRANCH} .
    west update --narrow -o=--depth=1
    if [ "${SLIM}" -ne 0 ]; then
        # Remove large NCS modules that we're not using
        rm -rf /workdir/modules/lib/gui
        # Remove documentation and examples.  Samples are kept since that's where
        # the bootloader lives.  Tests are kept since they have some .defconfigs
        # that are included in the build and must exist.
        find . -type d \( -iname "example*" -o -iname "doc*" \) -prune -exec rm -rf {} +
    fi
EOT

# Copy the Zephyr patches from the local folder to the container
COPY zephyr_patches /workdir/zephyr_patches

# Apply patches
RUN <<EOT
    cd /workdir/zephyr

    # Setup dummy git config (required by some git commands)
    git config --global user.email "ci@example.com"
    git config --global user.name "CI Builder"

    # Iterate through the patch files and apply them
    for patch in /workdir/zephyr_patches/*.patch; do
        echo "Applying $patch..."
        git apply "$patch"
    done

    # Clean up patches to save space
    rm -rf /workdir/zephyr_patches
EOT

# Launch into build environment with the passed arguments
# Currently this is not supported in GitHub Actions
# See https://github.com/actions/runner/issues/1964
ENTRYPOINT [ "nrfutil", "toolchain-manager", "launch", "/bin/bash", "--", "/root/entry.sh" ]
COPY ./entry.sh /root/entry.sh
