#!/bin/bash
set -e

# Build variables
export ARCH=arm64
export CPUS=${CPUS:-$(($(getconf _NPROCESSORS_ONLN) - 1))}
export CWD="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"
export KERNEL_DIR="${CWD}/kernel"
export KBUILD_BUILD_USER=theofficialgman
export KBUILD_BUILD_HOST=buildbot

export NX_VER="linux-dev"
export NV_VER="linux-dev"
export NG_VER="linux-3.4.0-r32.5"
export DT_VER="l4t/l4t-r32.5"

export KCFLAGS="-march=armv8-a+simd+crypto+crc -mtune=cortex-a57 --param=l1-cache-line-size=64 --param=l1-cache-size=32 --param=l2-cache-size=2048"

# Create compressed modules and update archive with correct permissions and ownership
create_update_modules() {
	find "$1" -type d -exec chmod 755 {} \;
	find "$1" -type f -exec chmod 644 {} \;
	find "$1" -name "*.sh" -type f -exec chmod 755 {} \;
	find "$1" -name "*.py" -type f -exec chmod 755 {} \;
	sudo chown -R root:root "$1"
	tar -C "$1" -czvpf "$2" .
}

Prepare() {
	echo "Preparing Source"
	if [[ -z `ls -A ${KERNEL_DIR}/kernel-4.9` ]]; then
		git clone -b "${NX_VER}" --single-branch https://github.com/theofficialgman/switch-l4t-kernel-4.9.git "${KERNEL_DIR}/kernel-4.9"
	fi

	if [[ -z $(ls -A ${KERNEL_DIR}/nvidia) ]]; then
		git clone -b ${NV_VER} --single-branch https://github.com/theofficialgman/switch-l4t-kernel-nvidia.git "${KERNEL_DIR}/nvidia"
		git clone -b ${NX_VER} --single-branch https://github.com/theofficialgman/switch-l4t-platform-t210-nx.git "${KERNEL_DIR}/hardware/nvidia/platform/t210/nx"
		git clone -b ${NG_VER} --single-branch https://gitlab.com/switchroot/kernel/l4t-kernel-nvgpu "${KERNEL_DIR}/nvgpu"
		git clone -b ${DT_VER} --single-branch https://gitlab.com/switchroot/kernel/l4t-soc-t210 "${KERNEL_DIR}/hardware/nvidia/soc/t210"
		git clone -b ${DT_VER} --single-branch https://gitlab.com/switchroot/kernel/l4t-soc-tegra "${KERNEL_DIR}/hardware/nvidia/soc/tegra/"
		git clone -b ${DT_VER} --single-branch https://gitlab.com/switchroot/kernel/l4t-platform-tegra-common "${KERNEL_DIR}/hardware/nvidia/platform/tegra/common/"
		git clone -b ${DT_VER} --single-branch https://gitlab.com/switchroot/kernel/l4t-platform-t210-common "${KERNEL_DIR}/hardware/nvidia/platform/t210/common/"
	fi

	if [[ "$1" == "update" ]]; then
		git -C "${KERNEL_DIR}/kernel-4.9" pull
		git -C "${KERNEL_DIR}/nvidia" pull
		git -C "${KERNEL_DIR}/nvgpu" pull
		git -C "${KERNEL_DIR}/hardware/nvidia/platform/t210/nx" pull
		git -C "${KERNEL_DIR}/hardware/nvidia/soc/t210" pull
		git -C "${KERNEL_DIR}/hardware/nvidia/soc/tegra/" pull
		git -C "${KERNEL_DIR}/hardware/nvidia/platform/tegra/common/" pull
		git -C "${KERNEL_DIR}/hardware/nvidia/platform/t210/common/" pull
	fi

	if [[ "$1" == "reset" ]]; then
		git -C "${KERNEL_DIR}/kernel-4.9" reset --hard origin/${NX_VER}
		git -C "${KERNEL_DIR}/nvidia" reset --hard origin/${NV_VER}
		git -C "${KERNEL_DIR}/nvgpu" reset --hard origin/${NG_VER}
		git -C "${KERNEL_DIR}/hardware/nvidia/platform/t210/nx" reset --hard origin/${NX_VER}
		git -C "${KERNEL_DIR}/hardware/nvidia/soc/t210" reset --hard origin/${DT_VER}
		git -C "${KERNEL_DIR}/hardware/nvidia/soc/tegra/" reset --hard origin/${DT_VER}
		git -C "${KERNEL_DIR}/hardware/nvidia/platform/tegra/common/" reset --hard origin/${DT_VER}
		git -C "${KERNEL_DIR}/hardware/nvidia/platform/t210/common/" reset --hard origin/${DT_VER}
	fi

	# Setup linaro aarch64 GCC7 for cross compilation if needed
	if [[ `uname -m` != aarch64 ]]; then
		if [[ ! -d "${KERNEL_DIR}/gcc-linaro-7.5.0-2019.12-x86_64_aarch64-linux-gnu" ]]; then
			echo -e "\nSetting up aarch64 cross compiler"
			wget -q -nc --show-progress https://releases.linaro.org/components/toolchain/binaries/latest-7/aarch64-linux-gnu/gcc-linaro-7.5.0-2019.12-x86_64_aarch64-linux-gnu.tar.xz
			tar xf gcc-linaro-7.5.0-2019.12-x86_64_aarch64-linux-gnu.tar.xz -C "${KERNEL_DIR}"
			rm gcc-linaro-7.5.0-2019.12-x86_64_aarch64-linux-gnu.tar.xz
		fi

		# Set cross compiler in PATH and CROSS_COMPILE string
		export PATH="$(realpath ${KERNEL_DIR}/gcc-linaro-7.5.0-2019.12-x86_64_aarch64-linux-gnu)/bin/:$PATH"
		export CROSS_COMPILE=${CROSS_COMPILE:-"aarch64-linux-gnu-"}
		export STRIP_BIN=${KERNEL_DIR}/gcc-linaro-7.5.0-2019.12-x86_64_aarch64-linux-gnu/bin/aarch64-linux-gnu-strip
	else
		export STRIP_BIN=strip
	fi

	# Retrieve mkdtimg
	if [[ ! -e "${KERNEL_DIR}/mkdtimg" ]]; then
		wget https://android.googlesource.com/platform/system/libufdt/+archive/refs/heads/master/utils.tar.gz
		tar xvf utils.tar.gz --exclude tests --exclude README.md
		cp src/mkdtboimg.py "${KERNEL_DIR}/mkdtimg"
		chmod a+x "${KERNEL_DIR}/mkdtimg"
		rm -rf utils.tar.gz src
	fi
	export PATH="$(realpath ${KERNEL_DIR}):$PATH"
}

Build() {
	echo "Creating Defconfig and preparing kernel build"

	cd "${KERNEL_DIR}/kernel-4.9"

	# # clean build
	# make mrproper

	# make .config
	make tegra_linux_defconfig

	# prepare for build
	make prepare
	make modules_prepare

	# Build kernel
	echo "Building kernel"
	make -j${CPUS} tegra-dtstree="../hardware/nvidia"

	# Copy modules and firmware
	echo "Copying modules and firmware"
	sudo rm -rf "${KERNEL_DIR}/modules"
	make modules_install INSTALL_MOD_PATH="${KERNEL_DIR}/modules"
	make firmware_install INSTALL_MOD_PATH="${KERNEL_DIR}/modules" INSTALL_FW_PATH="${KERNEL_DIR}/modules/lib/firmware"
 	rm "${KERNEL_DIR}/modules/lib/modules/4.9.140-l4t/build" "${KERNEL_DIR}/modules/lib/modules/4.9.140-l4t/source"

	cd ../..
}

PostConfig() {
	echo "Stripping debug symbols from modules"
	sudo find ${KERNEL_DIR}/modules -name "*.ko" -type f -exec $STRIP_BIN --strip-debug {} \;

  	echo "Create modules.tar.gz"
	create_update_modules "${KERNEL_DIR}/modules/lib/" "${KERNEL_DIR}/modules.tar.gz"

	mkimage -A arm64 -O linux -T kernel -C gzip -a 0x80200000 -e 0x80200000 -n theofficialgman-L4T -d ${KERNEL_DIR}/kernel-4.9/arch/arm64/boot/zImage "${KERNEL_DIR}/uImage"

	mkdtimg create "${KERNEL_DIR}/nx-plat.dtimg" --page_size=1000 \
        ${KERNEL_DIR}/kernel-4.9/arch/arm64/boot/dts/tegra210-odin.dtb	 --id=0x4F44494E \
		${KERNEL_DIR}/kernel-4.9/arch/arm64/boot/dts/tegra210b01-odin.dtb --id=0x4F44494E --rev=0xb01 \
		${KERNEL_DIR}/kernel-4.9/arch/arm64/boot/dts/tegra210b01-vali.dtb --id=0x56414C49 \
		${KERNEL_DIR}/kernel-4.9/arch/arm64/boot/dts/tegra210b01-fric.dtb --id=0x46524947

	# Build linux-headers-4.9.140-l4t for external module support
	cd "${KERNEL_DIR}/kernel-4.9"
	make clean
	sudo rm -rf "${KERNEL_DIR}/linux-headers-4.9.140-l4t"
	cp -R "${KERNEL_DIR}/kernel-4.9" "${KERNEL_DIR}/linux-headers-4.9.140-l4t"
	sudo chown -R root:root "${KERNEL_DIR}/linux-headers-4.9.140-l4t"
	cd  "${KERNEL_DIR}/linux-headers-4.9.140-l4t"
	sudo rm -rf .git .config.old .gitattributes .gitignore
	sudo find . -depth -type f ! \( -path './include/*' -o -path './scripts/*' -o  -name 'Makefile*' -o -name 'Kconfig*' -o -name 'Kbuild*' -o -name '*.sh' -o -name '*.pl' -o -name '*.lds' -o -name '*.h' -o -name '.config' -o -name 'Module.symvers' \) -delete
	sudo find . -depth -type f ! \( -path './include/*' -o -path './scripts/*' -o -path './arch/*' \) -a -name '*.h' -delete
	cd ../..

	echo "Done"
}

Prepare $1
Build
PostConfig
