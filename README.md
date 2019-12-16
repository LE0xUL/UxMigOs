# MIGOS - Balena

MIGOS is a raspbian-based ramdisk environment for migrate raspbian to BalenaOS

MIGOS is loaded fully into RAM at boot time, after which the SD card is available
for migration. 

# Build MIGOS

## Clone / Submodules

This repository uses git submodules. Clone with `--recursive` or after cloning
the repository run:

    git submodule update --init --recursive

Note that shallow cloning usually won't be possible because most of the upstream
repositories do not allow shallow cloning arbitrary commits, only the tips of
branches and tags.

### System packages

MIGOS uses multistrap to collect packages. multistrap requires apt and
as such is only supported on Debian based systems. It may be possible to use
it on other distributions, but this has not been tested.

In addition you need the following packages to build MIGOS:

For Ubuntu 18.04:

    sudo apt install libc6:i386 libstdc++6:i386 libgcc1:i386 \
                     libncurses5:i386 libtinfo5:i386 zlib1g:i386 \
                     build-essential git bc python zip wget gettext \
                     autoconf automake libtool pkg-config autopoint \
                     bison flex libglib2.0-dev gobject-introspection \
                     multistrap fakeroot fakechroot proot cpio \
                     qemu-user binfmt-support makedev \
                     gtk-doc-tools valac python3.7-minimal

This dependency list may be incomplete. If so, please report a bug.

Some build dependencies need to be fairly new:

Git >= 2.12 is needed for "rev-parse --absolute-git-dir". It is available in
Ubuntu 17.10 and newer, or from this PPA if you are on an older release:

  https://launchpad.net/~git-core/+archive/ubuntu/ppa

Qemu >= 3.1 is needed for the getrandom() syscall. It is available in Ubuntu
19.04 and newer. You can get it from the Ubuntu Cloud Archive, Stein repository
for Ubuntu 18.04:

  https://wiki.ubuntu.com/OpenStack/CloudArchive

Proot >= 5.1.0-1.3 is needed for the renameat2() syscall. It is available in
Ubuntu 19.04 and newer. It is available in this PPA for Ubuntu 18.04:

  https://launchpad.net/~a-j-buxton/+archive/ubuntu/backports/

## Keys

Multistrap/apt needs public keys to verify the repositories. You must import
the required keys into your local gpg keyring with the following commands:

    gpg --recv-key 9165938D90FDDD2E # raspbian-archive-keyring
    gpg --recv-key 82B129927FA3303E # raspberrypi-archive-keyring

You should take necessary steps to ensure that you have authentic versions of
these keys. Once received, MIGOS will export them as and when required.

On Ubuntu 16.04 you will also need to import these keys into the host apt
trusted keys with the following commands:

    sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 9165938D90FDDD2E
    sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 82B129927FA3303E

You may also need to do this on Ubuntu 16.10, 17.04, 17.10 but it is not necessary
on 18.04 and later.

### Pydo

MIGOS uses a build tool called [pydo](https://github.com/ali1234/pydo) which has been developed specifically
to handle complex builds which don't produce executables and libraries. You must
first install it:

    cd migos-balena/pydo && pip3 install .


## Compiling

First initialize the project:

    cd migos-balena/
    pydo --init

To build the whole project run:

    pydo :build

To clean the whole project run:

    pydo :clean

You can view another options running:

    pydo -l

## Booting

The build produces a boot/ directory containing everything needed to boot.

Run `./gen_migos-boot.sh` to generate a fit `tgz` file and extract it onto blank
boot fat partition on the SD card, normally `/dev/mmcblk0p1`.


