MEM_START=0x800000400000

function target_usage () {
	pr_inf "\nTARGET: ${1}"
	pr_inf "\n${1} commands:"
	pr_inf "\thelp/usage: Print this message"
	pr_inf "\tbootstrap: (Re)Build unified image (osbi + Linux)"
	pr_inf "\trun_on_qemu: Test unified image on QEMU"
	pr_wrn "\t<arg> Rootfs: path to NFS-exported directory  OR  path to raw disk image file"
	pr_inf "\tboot_node: Run unified image on QEMU, in a multi-instance scenario"
	pr_wrn "\t<arg> Rootfs path on host's NFS server"
	pr_wrn "\t<arg> Node ID (1 - 253)"
	pr_inf "\trun_installer: Build and run the installer script on the rootfs"
	pr_wrn "\t<arg> Distro to install: ubuntu / alpine"
	pr_wrn "\t<arg> Rootfs: path to NFS-exported directory  OR  path to raw disk image file (created if absent)"
}

function target_env_check() {
	if [[ $# < 2 ]]; then
		usage
		exit -1;
	fi

	if [[ ${2} == "usage" || ${2} == "help" ]]; then
		target_usage ${1}
		echo -e "\n"
		KEEP_LOGS=0
		exit 0;
	fi

	# Command filter
	if [[ "${2}" != "bootstrap" && "${2}" != "run_on_qemu" && \
	      "${2}" != "boot_node" && "${2}" != "run_installer" ]]; then
		pr_err "Invalid command for ${1}"
		target_usage ${1}
		echo -e "\n"
		KEEP_LOGS=0
		exit -1;
	fi
}

function target_env_prepare () {
	TARGET=${1}
	OSBI_PLATFORM="generic"
	BASE_ISA=RV64I
	NO_NETWORK=0
	LINUX_KERNEL_GITPATH=pub/scm/linux/kernel/git/stable/linux.git/
	LINUX_KERNEL_GITURL=https://git.kernel.org/${LINUX_KERNEL_GITPATH}
	LINUX_KERNEL_GITBRANCH="linux-6.12.y"
	OSBI_GITBRANCH="v1.6"
}

function target_bootstrap () {
	KERNEL_EMBED_INITRAMFS=0
	build_linux
	OSBI_WITH_PAYLOAD=1
	build_osbi
}

function run_on_qemu () {
	local SAVED_PWD=${PWD}
	local QEMU_INSTALL_DIR=${BINDIR}/riscv-qemu
	local OSBI_INSTALL_DIR=${WORKDIR}/${BASE_ISA}/riscv-opensbi
	local LINUX_INSTALL_DIR=${WORKDIR}/${BASE_ISA}/riscv-linux
	local BASE_ISA_XLEN=$(echo ${BASE_ISA} | tr -d [:alpha:])
	local QEMU=${QEMU_INSTALL_DIR}/bin/qemu-system-riscv${BASE_ISA_XLEN}
	local BIOS=${OSBI_INSTALL_DIR}/fw_jump.elf

	if [[ $# -lt 1 ]]; then
		pr_err "Rootfs argument required: NFS-exported directory or raw disk image file"
		exit ${E_INVAL};
	fi

	if [[ ! -e ${1} ]]; then
		pr_err "Provided path doesn't exist"
		exit ${E_INVAL};
	fi

	if [[ -f ${1} ]]; then
		# Disk image mode: boot from raw image via virtio-blk
		${QEMU} -nographic -machine eupilot-vec -smp 4 -m 4G \
			-nic user,model=xlnx.xps-ethernetlite,id=hnet0,net=10.0.3.0/24 \
			-nic user,id=hnet1,smb=${HOME} \
			-drive file=${1},format=raw,id=rootdisk \
			-device virtio-blk-device,drive=rootdisk \
			-kernel ${LINUX_INSTALL_DIR}/Image \
			-append "root=/dev/vda1 rw rootwait"
	else
		# NFS mode: root over NFS via the fast DMA ethernet (eth1)
		# Note: emaclite (eth0) is too slow/lossy for NFS; eth1 (DMA eth) is used instead.
		# QEMU requires all NICs in order, so eth0 must still be declared even if unused.
		${QEMU} -nographic -machine eupilot-vec -smp 4 -m 4G \
			-nic user,model=xlnx.xps-ethernetlite,id=hnet0,net=10.0.3.0/24 \
			-nic user,id=hnet1,smb=${HOME} \
			-kernel ${LINUX_INSTALL_DIR}/Image \
			-append "nfsrootdebug root=/dev/nfs nfsroot=${1},vers=4,tcp ip=::::eupilot:eth1:dhcp:: rw"
	fi

	cd ${SAVED_PWD}
}

function boot_node () {
	local SAVED_PWD=${PWD}
	local QEMU_INSTALL_DIR=${BINDIR}/riscv-qemu
	local OSBI_INSTALL_DIR=${WORKDIR}/${BASE_ISA}/riscv-opensbi
	local LINUX_INSTALL_DIR=${WORKDIR}/${BASE_ISA}/riscv-linux
	local BASE_ISA_XLEN=$(echo ${BASE_ISA} | tr -d [:alpha:])
	local QEMU=${QEMU_INSTALL_DIR}/bin/qemu-system-riscv${BASE_ISA_XLEN}
	local BIOS=${OSBI_INSTALL_DIR}/fw_jump.elf

	if [[ $# -lt 1 ]]; then
		pr_err "Exported NFS path for rootfs on host is required"
		exit ${E_INVAL};
	fi

	if [[ ! -e ${1} ]]; then
		pr_err "Provided path on host doesn't exist"
		exit ${E_INVAL};
	fi

	if [[ $# -lt 2 ]]; then
		pr_err "Node ID not provided"
		exit ${E_INVAL};
	fi

	local NODE_ID=${2}

	if ! [[ ${NODE_ID} =~ ^[0-9]+$ ]]; then
		pr_err "Invalid Node ID"
		exit ${E_INVAL};
	fi

	if (( ${NODE_ID} <= 0 || ${NODE_ID} >= 254 )); then
		pr_err "Node ID out of range"
		exit ${E_INVAL};
	fi

	local IP_OFFSET=$((${NODE_ID} + 1))
	local IP_ADDR="192.168.1.${IP_OFFSET}"
	local HOSTNAME="eupilot-node-${NODE_ID}"

	${QEMU} -nographic -machine eupilot-vec -smp 4 -m 2G -nic user,model=xlnx.xps-ethernetlite,id=hnet0,smb=${HOME}  \
		-nic bridge,br=nodebridge0,id=hnet1 \
		-kernel ${LINUX_INSTALL_DIR}/Image \
		-append "nfsrootdebug root=/dev/nfs nfsroot=${1},vers=4,tcp ip=${IP_ADDR}:192.168.1.1:192.168.1.1:255.255.255.0:${HOSTNAME}:eth1:off: systemd.hostname=${HOSTNAME} ro"

	cd ${SAVED_PWD}
}

function run_installer () {
	local SAVED_PWD=${PWD}
	local QEMU_INSTALL_DIR=${BINDIR}/riscv-qemu
	local BASE_ISA_XLEN=$(echo ${BASE_ISA} | tr -d [:alpha:])
	local LINUX_INSTALL_DIR=${WORKDIR}/${BASE_ISA}/riscv-linux
	local ROOTFS_INSTALL_DIR=${WORKDIR}/${BASE_ISA}/rootfs/
	local QEMU=${QEMU_INSTALL_DIR}/bin/qemu-system-riscv${BASE_ISA_XLEN}

	if ! [[ -d ${LINUX_INSTALL_DIR} ]]; then
		pr_err "Kernel installation dir not present, you need to run bootstrap first"
		exit ${E_INVAL}
	fi

	if [[ $# -lt 2 ]]; then
		pr_err "Invalid number of arguments"
		target_usage
		exit ${E_INVAL};
	fi

	if [[ "${1}" != "alpine" && "${1}" != "ubuntu" ]]; then
		pr_err "Invalid distro argument"
		target_usage
		exit ${E_INVAL};
	fi

	if ! [[ -d ${ROOTFS_INSTALL_DIR} ]] || \
	   [[ "${SCRIPT_PATH}/files/extra/installer-ubuntu" -nt "${ROOTFS_INSTALL_DIR}/initramfs.img" ]]; then
		pr_inf "Building/rebuilding rootfs for installer"
		NO_NETWORK=1
		build_rootfs
	fi

	if [[ -d ${2} ]]; then
		# NFS mode: install into an NFS-exported directory
		${QEMU} -nographic -machine eupilot-vec -smp 4 -m 8G \
			-nic user,model=xlnx.xps-ethernetlite,id=hnet0,net=10.0.3.0/24 \
			-nic user,id=hnet1,smb=${HOME} \
			-kernel ${LINUX_INSTALL_DIR}/Image \
			-initrd ${ROOTFS_INSTALL_DIR}/initramfs.img \
			-append "installer_prefix=${2} installer=${1} ip=::::eupilot:eth1:dhcp::"
	else
		# Disk image mode: install into a raw partitioned image via virtio-blk
		if [[ ! -e ${2} ]]; then
			pr_inf "Creating 16G raw disk image at ${2}..."
			fallocate -l 16G ${2}
			if [[ $? -ne 0 ]]; then
				pr_err "Failed to create disk image"
				exit ${E_INVAL};
			fi
		fi
		pr_inf "Partitioning disk image..."
		sgdisk -n 1:2048:0 -t 1:8300 ${2}
		if [[ $? -ne 0 ]]; then
			pr_err "Failed to partition disk image"
			exit ${E_INVAL};
		fi
		pr_inf "Formatting partition as ext4..."
		local _fsectors=$(( $(stat -c%s ${2}) / 512 ))
		local _fblocks=$(( (_fsectors - 2081) / 8 ))
		mkfs.ext4 -F -E offset=$((2048 * 512)) ${2} ${_fblocks}
		if [[ $? -ne 0 ]]; then
			pr_err "Failed to format partition"
			exit ${E_INVAL};
		fi
		${QEMU} -nographic -machine eupilot-vec -smp 4 -m 8G \
			-nic user,model=xlnx.xps-ethernetlite,id=hnet0,net=10.0.3.0/24 \
			-nic user,id=hnet1,smb=${HOME} \
			-drive file=${2},format=raw,id=rootdisk \
			-device virtio-blk-device,drive=rootdisk \
			-kernel ${LINUX_INSTALL_DIR}/Image \
			-initrd ${ROOTFS_INSTALL_DIR}/initramfs.img \
			-append "installer_dev=/dev/vda1 installer=${1} ip=::::eupilot:eth1:dhcp::"
	fi

	cd ${SAVED_PWD}
}
