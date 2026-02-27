Step 1: Initialize yarvt (Yet Another RISC-V Tool)
==================================================
This how-to is meant for debian-based distros, but the only distro-specific part has to do with installing dependencies, it can easily be adapted to other distros if needed.

Let's start by installing yarvt requirements, and clone the yarvt repo. Note that yarvt is a bash script that uses standard tools such as grep, sed, awk, tar etc that should be part of your distro, on top of that the following need to be installed:
* Git for cloning repositories
* Curl and wget for querying/downloading pre-built images
* patch for patching sources when needed
* xz for compressing initramfs when building linux
* A working toolchain on the host for building Linux's kbuild and other tools
* flex/bison for Linux's kbuild
* OpenSSL (+ headers) for Linux's module signing tool
* bc for Linux's build scripts and for yarvt to calculate hex addresses

Note: All apt-get commands need to run as root either through `sudo` or `su`, the rest should be executed as your normal user, no root required.

```
apt-get install git curl wget gawk patchutils xz-utils build-essential flex bison libssl-dev bc
git clone --depth=1 https://github.com/CARV-ICS-FORTH/yarvt.git
```

We have two options for initializing (bootstraping) yarvt:
* Download toolchain sources and build them locally, that takes a lot of time (bootstrap)
* Download the pre-build toolchain binaries from the toolchain repo's ci (bootstrap_fast)

In both cases we'll need to also build QEMU locally, so that it includes any custom machines (added through files/patches). For that we need to install a few extra dependencies:

* python3-pip (QEMU's build system requires a python3 venv)
* ninja-build (Build system used for QEMU)
* libglib2.0-dev (Glib library + headers)
* libslirp-dev (SLIRP library + headers for QEMU's user networking backend)

```
apt-get install python3-pip ninja-build libglib2.0-dev libslirp-dev
```

In order to share the user's home folder with the guest when running under QEMU, using cifs (via QEMU's user backend), we also need to install samba

```
apt-get install samba
```

Option 1: Build the required toolchains (and go for a walk)
-----------------------------------------------------------
If you want to build the toolchains locally instead of using the pre-built images (that should work in most distros), a few more dependencies are needed:

```
apt-get install autoconf automake texinfo gperf libtool autotools-dev zlib1g-dev libexpat-dev libmpc-dev libmpfr-dev libgmp-dev 
./yarvt bootstrap
```

Option 2: Download the pre-built toolchains (recomended)
--------------------------------------------------------

No further requirements in this case, just run:

```
./yarvt bootstrap_fast
```


Step 2: Verify correct operation
================================

Now that our development environment is ready, let's build a simple payload with networking support, and test it under QEMU.

```
./yarvt qemu-virt bootstrap
./yarvt qemu-virt run_linux64
```

If everything worked as expected you should end up with a login prompt, where you can use root/riscv to login.

Using `ip addr show` you should see the eth0 interface up, with an ip address of 10.0.2.15 (the default address provided by QEMU's user network backend).
You should also be able to mount your home directory from within QEMU:

```
mkdir /home
mount -tcifs //10.0.2.4/qemu /home
```

You may exit using just ` halt `.

Note that 10.0.2.4 is a virtual endpoint emulated by QEMU's user network backend, to reach the host through this backend you may use 10.0.2.2, which is also used as the default gateway, and to perform DNS queries through the host's resolver you may use 10.0.2.3.
