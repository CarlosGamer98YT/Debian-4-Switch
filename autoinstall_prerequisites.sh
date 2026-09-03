#!/bin/bash

sudo apt-get update && sudo apt-get install -y \
    debootstrap mmdebstrap qemu-user-static binfmt-support \
    git build-essential gcc-aarch64-linux-gnu g++-aarch64-linux-gnu \
    bison flex libssl-dev bc libncurses-dev kmod \
    dosfstools parted rsync u-boot-tools 7z

sudo chmod +x build.sh
./build.sh
