MEM_START=0x800000400000

function target_usage () {
	pr_inf "\nTARGET: ${1}"
	pr_inf "\n${1} commands:"
	pr_inf "\thelp/usage: Print this message"
	pr_inf "\tbootstrap: (Re)Build unified image (osbi + Linux + rootfs)"
	pr_inf "\trun_on_qemu: Test unified image on QEMU"
	pr_wrn "\t<arg> Rootfs path on host's NFS server"
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
	if [[ "${2}" != "bootstrap" && "${2}" != "run_on_qemu" ]]; then
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
	LINUX_KERNEL_GITBRANCH="linux-6.7.y"
	OSBI_GITBRANCH="v1.4"
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
		pr_err "Exported NFS path for rootfs on host is required"
		exit ${E_INVAL};
	fi

	if [[ ! -e ${1} ]]; then
		pr_err "Provided path on host doesn't exist"
		exit ${E_INVAL};
	fi

# Use virt machine for now until I debug this further
#
#	${QEMU} -nographic -machine eupilot-vec -smp 4 -m 2G -nic user,id=hnet0,smb=/home/$(whoami)  \
#		-kernel ${LINUX_INSTALL_DIR}/Image \
#		-append "nfsrootdebug root=/dev/nfs nfsroot=${1},vers=4,tcp ip=::::eupilot-vec:eth0:dhcp:: ro"

	${QEMU} -nographic -machine virt -cpu rv64,v=true,vext_spec=v1.0,vlen=128 -smp 4 -m 2G -nic user,id=hnet0,smb=/home/$(whoami)  \
		-device virtio-net-device,netdev=eth0 -netdev user,id=eth0 \
		-kernel ${LINUX_INSTALL_DIR}/Image \
		-append "nfsrootdebug root=/dev/nfs nfsroot=${1},vers=4,tcp ip=::::eupilot-vec:eth0:dhcp:: ro"


	cd ${SAVED_PWD}
}
