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
git clone --depth=1 -b eupilot https://github.com/CARV-ICS-FORTH/yarvt.git
```

We have two options for initializing (bootstraping) yarvt:
* Download toolchain sources and build them locally, that takes a lot of time (bootstrap)
* Download the pre-build toolchain binaries from the toolchain repo's ci (bootstrap_fast)

In both cases we'll need to also build QEMU locally, so that it includes our own custom eupilot-vec machine. For that we need to install a few extra dependencies:

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
./yarvt 6.12-busybox-net bootstrap
./yarvt 6.12-busybox-net run_on_qemu
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
The current machine model has two ethernet interfaces, eth0 is an emaclite interface and eth1 is a dma-based ethernet NIC that matches FORTH's implementation in hw.


Step 3: Prepare and export a folder on the host for the rootfs
==============================================================

Since our platform doesn't include storage, the only way to boot a full-blown linux distro is to mount its rootfs over NFS. I tried to make this work without root privileges, using cifs instead of NFS but the rootfs over cifs support in the linux kernel doesn't work well with QEMU's user backend approach, so all commands in this step need to be executed with root privileges unfortunately (but only once). Let's start by installing nfs tools for running the server:

```
apt-get install nfs-kernel-server
```

And then create a folder for the rootfs, and export it via NFS:

```
mkdir /mnt/riscv64-rootfs
echo "/mnt/riscv64-rootfs 127.0.0.1(async,rw,no_root_squash,subtree_check,insecure) 192.168.1.0/24(async,rw,no_root_squash,subtree_check,insecure)" >> /etc/exports
systemctl start nfs-server
systemctl enable nfs-server
```

Note: the 192.168.1.0/24 rule is needed for Step 5+

You should be able to mount the exported folder locally for testing (as root), e.g.

```
mkdir /mnt/test
mount -tnfs4 127.0.0.1:/mnt/riscv64-rootfs /mnt/test
umount /mnt/test
```

Step 4: Install Ubuntu / Alpine Linux on the exported rootfs folder
===================================================================

The first step is to bootstrap the ubuntu-net profile, since we need the kernel to be build before the rootfs, so that we can install the kernel modules in the rootfs.

```
./yarvt 6.12-ubuntu-net bootstrap
```

When the process is done, choose which distro to install in the exported NFS folder using the run_installer command of that profile:

```
./yarvt 6.12-ubuntu-net run_installer ubuntu /mnt/riscv64-rootfs/
or
./yarvt 6.12-ubuntu-net run_installer alpine /mnt/riscv64-rootfs/
```

This will build a small initramfs (as in step 2), that includes the installation scripts, boot QEMU, and run the installation scripts inside QEMU, with the NFS export mounted.
When the process is done you'll have a full RISC-V ubuntu/alpine distro installed in your exported folder.


Step 5: Booting a single instance of the platform, running ubuntu/alpine
===============================================================

Time to boot the ubuntu-net target, with the rootfs we created above:

```
./yarvt 6.12-ubuntu-net run_on_qemu /mnt/riscv64-rootfs/
```

Note that this would mount the rootfs read-write, allowing you to perform maintenance tasks etc.
The root password set by the installation script is 'riscv' for convenience.
Don't forget to clean things up after you are done, so that the rootfs can also be mounted as read-only for the next step.

Networking in this case is also provided by QEMU's user backend, so check Step 2 for details, the only difference here is that eth1 is used instead of eth0, since eth1 is the dma-based ethernet and is much better/faster for mounting rootfs over NFS.
The emaclite nic is connected to a dummy network with a subnet that goes nowhere due to a limitation in QEMU (we need to initialize eth0 in order to initialize eth1).


Step 6: Setting up the environment for multiple instances that communicate with each other
==========================================================================================

I tried to make this simple for non-root users but it's still messy, so the simplest approach is to create a bridge on the host and have QEMU guests communicate through the bridge with each other and the host/outside.
The idea is to use the 192.168.1.0/24 subnet on top of the bridge, where the host would be reachable at 192.168.1.1 and all other nodes at 192.168.1.<node_id + 1>, so for example node 2 will have an ip address of 192.168.1.3.
For providing internet access to the guests, we need iptables for NAT (so make sure the package and required modules are installed in the host, if not just run `apt-get install iptables`), in the following example `lan` is the name of the host's network interface that connects the host to the outside world.
All commands in this step require root privileges in the host unfortunately, and the first part needs to be executed again in case of a host reboot.

```
ip link add name virbr0 type bridge
ip link set virbr0 up
ip addr add dev virbr0 192.168.1.1/24
echo 1 > /proc/sys/net/ipv4/ip_forward
iptables -t nat -A POSTROUTING -o lan -j MASQUERADE
```

The user backend is still used to provide access to the user's home folder through cifs (as in Step 2), only in this case the traffic for reaching the home folder goes through eth0 (emaclite) since we use eth1 (dma-based ethernet) with the bridge backend that doesn't do any network emulation (just forwards packets to the kernel's bridge).

In order for QEMU to use the virbr0 we need to allow it, and we also need to set suid bit on the bridge helper since it needs to run with root privileges (this is only needed once):

```
mkdir -p ./build/riscv-qemu/etc/qemu
echo "allow virbr0" > ./build/riscv-qemu/etc/qemu/bridge.conf
chmod 0640 ./build/riscv-qemu/etc/qemu/bridge.conf
chmod u+s ./build/riscv-qemu/libexec/qemu-bridge-helper
```

Note: in order for the helper to work it needs the host's kernel to support TUN/TAP, most distro kernels already support this, there is a chance however that the module is not loaded so just in case run `modprobe tun` and you should see `/dev/net/tun`.


Step 7: Booting up X instances
==============================

With everything set, we can now (as normal user) boot as many instances of the dev environment we want. Note that the rootfs will be mounted read-only, but the home folder will still be available for read-write operations. In case you need to make changes to the rootfs use Step 4.

```
./yarvt 6.12-ubuntu-net boot_node /mnt/riscv64-rootfs/ <node id>
```

Make sure your host has enough memory and cores for this to work, each instance is configured to have 4 cores and 2G of RAM.
