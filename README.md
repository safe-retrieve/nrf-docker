# Introduction

This is a fork of the [Nordicplayground/nrf-docker](https://github.com/NordicPlayground/nrf-docker) repo.

It is used to create the Docker image used for the CI build of the [SkyShepherd GEN3 hardware](https://github.com/safe-retrieve/sky-shepherd-firmware-v2).

The repo was forked so that we could continue to update to the latest nRF Connect SDK version.

The image create is reduced in size by removing some packages and modules that are not currently used for a CI build.  The size of the reduced image is about 4.68GB while a full image is 7.27GB.

It can also be used to build images locally.  The reduced image does not include the JLink tools to flash images to a board.

## Setup

Install `docker` on your operating system. On Windows you might want to use the [WSL subsystem](https://docs.docker.com/docker-for-windows/wsl-tech-preview/).

You can either build the image from this repository or use a pre-built one from Dockerhub.

### Build image locally

Clone the repo:

```bash
git clone https://github.com/safe-retrieve/nrf-docker
```

Build the full image with the defaults (this is only needed once):

```bash
cd nrf-docker
docker build -t ncs-full:v3.1.1 .
```

Build the slim image with the defaults (this is only needed once):

```bash
cd nrf-docker
docker build -t ncs-slim:v3.1.1 --build-arg SLIM=1 .
```

The following arguments are supported by the Dockerfile:
|Argument|Description|
|:-------|:----------|
| SLIM                              | Set to 1 to produce a slimmer version of the image.  <br>Defaults to `0`.|
| SDK_NRF_BRANCH                    | Set to the branch or tag to use for the nRF Connect SDK version.<br>Defaults to `v3.1.1`.|
| TOOLCHAIN_VERSION                 | Set to the toolchain version to install.  This is a value from the output of `nrfutil toolchain-manager search`.<br>Defaults to `v3.1.1`.<br>Note: Changing this value also requires a change to **TOOLCHAIN_ID**.|
| TOOLCHAIN_ID                      | Set to the bundle ID of the toolchain.  This value can be found by inspecting `toolchains.json` in an installed system.<br>Defaults to `b2ecd2435d`.<br>Note: Changing this value also requires a change to **TOOLCHAIN_VERSION**. |
| NORDIC_COMMAND_LINE_TOOLS_VERSION | Set to the partial name of the tarball for the [Nordic Command Line tools](https://www.nordicsemi.com/Products/Development-tools/nRF-Command-Line-Tools/Download?lang=en#infotabs).<br>Defaults to `10-24-2/nrf-command-line-tools-10.24.2`.|
| ARCH                              | Set to the host architecture that will be running the image.<br>Defaults to `amd64`.<br>Note: If building to run on a Mac with the M1 architecture, you need to set this value to `arm64`.|

### Use pre-built image from Dockerhub

Pre-built images are available as [`saferetrieve/ncs`](https://hub.docker.com/r/saferetrieve/ncs).

```bash
docker run --rm -v ${PWD}:/workdir/project saferetrieve/ncs:v3.1.1 ...
```

The rest of the documentation will use the local name `ncs-full`, but any of them can use `saferetrieve/ncs-full:v3.1.1` instead.

### Build the firmware

To demonstrate, we'll build the connectivity_bridge application from the nRF Connect SDK:

```bash
docker run --rm \
    -v ${PWD}:/workdir/project \
    -w /workdir/nrf/applications/connectivity_bridge \
    ncs-full \
    west build -b thingy91/nrf52840 --build-dir /workdir/project/build -- -DEXTRA_CFLAGS="-Werror -Wno-dev"

```

The firmware file will be located here: `nrf/applications/connectivity_bridge/build/b0/zephyr/merged.hex`. Because it's inside the folder that is bind mounted when running the image, it is also available outside of the Docker image.

> [!NOTE]
> The `-p always` build argument is to do a pristine build. It is similar to cleaning the build folder and is used because it is less error-prone to a previous build with different configuration. To speed up subsequent build with the same configuration you can remove this argument to avoid re-building code that haven't been modified since the previous build.

To build a stand-alone project, replace `-w /workdir/nrf/applications/connectivity_bridge` with the name of the applications folder inside the docker container:

```bash
# run from the build-with-nrf-connect-sdk
docker run --rm -v ${PWD}:/workdir/project \
    ncs-full \
    west build -p always -b nrf9160dk_nrf9160_ns\
```

## Full example

```bash
# build docker image
git clone https://github.com/safetrtrieve/nrf-docker
cd nrf-docker
docker build -t ncs-full --build-arg saferetrieve/ncs:v3.1.1 .
cd ..
```

### Build a Zephyr sample using the hosted image

This builds the `hci_uart` sample and stores the `hci_uart.hex` file in the current directory:

```bash
docker run --rm saferetrieve/ncs-full:v3.1.1 \
    -v ${PWD}:/workdir/project \
    west build zephyr/samples/bluetooth/hci_uart -p always -b nrf9160dk_nrf52840 --build-dir /workdir/project/build
ls -la build/b0/zephyr && cp build/b0/zephyr/zephyr.hex ./hci_uart.hex
```

#### nRF5280 DK example

```bash
# Init and build in Docker
docker run --rm saferetrieve/ncs-full:v3.1.1 \
  -v ${PWD}:/workdir/project \
  west build zephyr/samples/bluetooth/peripheral_ht -p always -b nrf52840dk_nrf52840 --build-dir /workdir/project/build

# Access build files
cp build/b0/zephyr/zephyr.hex peripheral_ht.hex
ls -la ./peripheral_ht.hex
```

## ClangFormat

The image comes with [ClangFormat](https://clang.llvm.org/docs/ClangFormat.html) and the [nRF Connect SDK formatting rules](https://github.com/nrfconnect/sdk-nrf/blob/main/.clang-format) so you can run for example

```bash
docker run --name ncs-full -d saferetrieve/ncs-full:v3.1.1 tail -f /dev/null
find ./src -type f -iname \*.h -o -iname \*.c \
    | xargs -I@ /bin/bash -c "\
        tmpfile=\$(mktemp /tmp/clang-formatted.XXXXXX) && \
        docker exec -i ncs-full clang-format < @ > \$tmpfile && \
        cmp --silent @ \$tmpfile || (mv \$tmpfile @ && echo @ formatted.)"
docker kill ncs
docker rm ncs
```

to format your sources.

> [!NOTE]
> Instead of having `clang-format` overwrite the source code file itself, the above command passes the source code file on stdin to clang-format and then overwrites it outside of the container. Otherwise the overwritten file will be owner by the root user (because the Docker daemon is run as root).

## Interactive usage

```bash
docker run -it -v ${PWD}:/workdir/project ncs-full /bin/bash
```

Then, inside the container:

```bash
cd /workdir/nrf/applications/connectivity_bridge
west build -p always -b thingy91/nrf52840
...
```

Meanwhile, outside of the container, you may modify the code and repeat the build cycle.

Later after closing the container you may re-open it by name to continue where you left off:

```bash
docker start -i ncs-full
```
