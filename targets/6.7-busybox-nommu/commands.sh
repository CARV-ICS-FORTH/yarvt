MEM_START=0x800000400000

function target_usage () {
	pr_inf "\nTARGET: ${1}"
	pr_inf "\n${1} commands:"
	pr_inf "\thelp/usage: Print this message"
	pr_inf "\tbootstrap: (Re)Build unified image (osbi + Linux + rootfs)"
	pr_inf "\trun_on_qemu: Test unified image on QEMU"
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
	NO_NETWORK=1
	NOMMU_BUILD=1
	LINUX_KERNEL_GITPATH=pub/scm/linux/kernel/git/stable/linux.git/
	LINUX_KERNEL_GITURL=https://git.kernel.org/${LINUX_KERNEL_GITPATH}
	LINUX_KERNEL_GITBRANCH="linux-6.7.y"
	OSBI_GITBRANCH="v1.4"
}

function target_bootstrap () {
	KERNEL_EMBED_INITRAMFS=1
	build_linux
	OSBI_WITH_PAYLOAD=1
	build_osbi
}

function run_on_qemu () {
	local SAVED_PWD=${PWD}
	local QEMU_INSTALL_DIR=${BINDIR}/riscv-qemu
	local OSBI_INSTALL_DIR=${WORKDIR}/${BASE_ISA}/riscv-opensbi
	local BASE_ISA_XLEN=$(echo ${BASE_ISA} | tr -d [:alpha:])
	local QEMU=${QEMU_INSTALL_DIR}/bin/qemu-system-riscv${BASE_ISA_XLEN}
	local BIOS=${OSBI_INSTALL_DIR}/fw_payload.bin

	${QEMU} -nographic -cpu rv64,mmu=false -machine eupilot-vec -m 1G  \
		-bios ${BIOS}

	cd ${SAVED_PWD}
	KEEP_LOGS=0
}
