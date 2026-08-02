function target_usage () {
	pr_inf "\nTARGET: QEMU RISC-V Virt machine"
	pr_inf "\nqemu-virt commands:"
	pr_inf "\thelp/usage: Print this message"
	pr_inf "\tbootstrap: (Re)Build osbi + Linux + rootfs"
	pr_inf "\tbuild_osbi: (Re)Build OpenSBI"
	pr_inf "\tbuild_linux: (Re)Build a defconfig RISC-V Linux kernel"
	pr_inf "\tbuild_rootfs: (Re)Build a minimal rootfs on initramfs"
	pr_inf "\trun_linux32 [backend] [distro]: Run a 32bit QEMU instance with osbi+linux+initramfs"
	pr_inf "\trun_linux64 [backend] [distro]: Run a 64bit QEMU instance with osbi+linux+initramfs"
	pr_wrn "\t[backend]: Optional storage backend to install onto / boot from. A raw disk"
	pr_wrn "\t           image path (created if missing) is attached as an NVMe device; an"
	pr_wrn "\t           existing directory is used as an NFS root (the host must export it)."
	pr_wrn "\t[distro]:  alpine or ubuntu - installed onto an empty backend on first boot."
}

function target_env_check() {
	if [[ $# < 2 ]]; then
		usage
		exit -1;
	fi

	if [[ ${2} == "usage" || ${2} == "help" ]]; then
		target_usage
		echo -e "\n"
		KEEP_LOGS=0
		exit 0;
	fi

	# Command filter
	if [[ "${2}" != "build_linux" && \
	      "${2}" != "build_rootfs" && "${2}" != "bootstrap" && \
	      "${2}" != "build_osbi" && \
	      "${2}" != "run_linux32" && "${2}" != "run_linux64" ]];
	      then
		pr_err "Invalid command for ${1}"
		target_usage
		echo -e "\n"
		KEEP_LOGS=0
		exit -1;
	fi
}

function target_env_prepare () {
	TARGET=${1}
	BASE_ISA=RV64I
	MEM_START=0x80000000
	OSBI_PLATFORM="generic"
}

function target_bootstrap () {
	build_linux
	build_rootfs
	build_osbi
	BASE_ISA=RV32I
	build_linux
	build_rootfs
	build_osbi
}

function run_linux () {
	local BACKEND=${1}
	local DISTRO=${2}
	local NVME_SIZE=8G
	local NVME_ARGS=""
	local APPEND=""
	local EXTRA_ARGS=()
	local SAVED_PWD=${PWD}
	local QEMU_INSTALL_DIR=${BINDIR}/riscv-qemu
	local OSBI_INSTALL_DIR=${WORKDIR}/${BASE_ISA}/riscv-opensbi
	local LINUX_INSTALL_DIR=${WORKDIR}/${BASE_ISA}/riscv-linux
	local ROOTFS_INSTALL_DIR=${WORKDIR}/${BASE_ISA}/rootfs
	local BASE_ISA_XLEN=$(echo ${BASE_ISA} | tr -d [:alpha:])
	local QEMU=${QEMU_INSTALL_DIR}/bin/qemu-system-riscv${BASE_ISA_XLEN}
	local BIOS=${OSBI_INSTALL_DIR}/fw_jump.elf

	# A distro is only needed to install onto an empty backend, but validate
	# it up front when one is given.
	if [[ "${DISTRO}" != "" ]] && \
	   [[ "${DISTRO}" != "alpine" ]] && [[ "${DISTRO}" != "ubuntu" ]]; then
		pr_err "Distro must be alpine or ubuntu"
		KEEP_LOGS=0
		exit -1
	fi

	# Pick the storage backend from the argument and tell the guest about it
	# through yarvt.bootmode (init then boots what's installed there or runs
	# the installer):
	#  - an existing directory  -> NFS root (the host must export it to the guest)
	#  - an existing raw image   -> attached as an NVMe device
	#  - a non-existing path      -> a raw NVMe image is created there first
	if [[ "${BACKEND}" != "" ]]; then
		if [[ -d "${BACKEND}" ]]; then
			BACKEND=$(realpath "${BACKEND}")
			pr_inf "Installing/booting over NFS from ${BACKEND} (host must export it)"
			APPEND="yarvt.bootmode=nfs yarvt.nfs_prefix=${BACKEND}"
		elif [[ -f "${BACKEND}" ]]; then
			pr_inf "Using existing disk image ${BACKEND} as an NVMe device"
			NVME_ARGS="-drive file=${BACKEND},if=none,id=nvm0,format=raw"
			NVME_ARGS="${NVME_ARGS} -device nvme,serial=YRVT0000000000000001,drive=nvm0"
			APPEND="yarvt.bootmode=nvme"
		elif [[ ! -e "${BACKEND}" ]]; then
			pr_inf "Creating ${NVME_SIZE} disk image ${BACKEND}..."
			truncate -s ${NVME_SIZE} "${BACKEND}"
			if [[ $? != 0 ]]; then
				pr_err "Couldn't create disk image ${BACKEND}"
				KEEP_LOGS=0
				exit -1
			fi
			NVME_ARGS="-drive file=${BACKEND},if=none,id=nvm0,format=raw"
			NVME_ARGS="${NVME_ARGS} -device nvme,serial=YRVT0000000000000001,drive=nvm0"
			APPEND="yarvt.bootmode=nvme"
		else
			pr_err "'${BACKEND}' is not a valid backend (raw image or NFS directory)"
			KEEP_LOGS=0
			exit -1
		fi
		if [[ "${DISTRO}" != "" ]]; then
			APPEND="${APPEND} yarvt.distro=${DISTRO}"
		fi
		EXTRA_ARGS=(-append "${APPEND}")
	fi

	${QEMU} -nographic -machine virt -smp 2 -m 1G -s \
		-netdev user,id=unet,hostfwd=tcp::2222-:22,hostname=riscv \
		-device virtio-net-device,netdev=unet \
		-net user \
		-object rng-random,filename=/dev/urandom,id=rng0 \
		-device virtio-rng-device,rng=rng0 \
		${NVME_ARGS} \
		-bios ${BIOS} \
		-kernel ${LINUX_INSTALL_DIR}/Image \
		-initrd ${ROOTFS_INSTALL_DIR}/initramfs.img \
		"${EXTRA_ARGS[@]}"

	cd ${SAVED_PWD}
	KEEP_LOGS=0
}

function run_linux32 () {
	BASE_ISA=RV32I
	run_linux "${1}" "${2}"
}

function run_linux64 () {
	BASE_ISA=RV64I
	run_linux "${1}" "${2}"
}
