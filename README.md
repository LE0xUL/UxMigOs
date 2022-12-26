# UXMIGOS

UXMIGOS is a raspbian-based ramdisk environment that was designed to migrate a raspbianOS to BalenaOS

UXMIGOS is loaded fully into RAM at boot time, after which, the SD card is available for migration

UXMIGOS can be modified to migrate remotely any Linux OS to another OS (principally Linux Based)

# INSTALL UXMIGOS

## Clone / Submodules

This repository uses git submodules. Clone with `--recursive` or after cloning the repository run:

    git submodule update --init --recursive

Note that shallow cloning usually won't be possible because most of the upstream repositories do not allow shallow cloning arbitrary commits, only the tips of branches and tags.

## Install System packages

UXMIGOS uses multistrap to collect packages. multistrap requires apt and as such is only supported on Debian based systems. It may be possible to use it on other distributions, but this has not been tested.

In addition you need the following packages to build UXMIGOS:

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

Git >= 2.12 is needed for "rev-parse --absolute-git-dir". It is available in Ubuntu 17.10 and newer, or from this PPA if you are on an older release:

  https://launchpad.net/~git-core/+archive/ubuntu/ppa

Qemu >= 3.1 is needed for the getrandom() syscall. It is available in Ubuntu 19.04 and newer. You can get it from the Ubuntu Cloud Archive, Stein repository for Ubuntu 18.04:

  https://wiki.ubuntu.com/OpenStack/CloudArchive

Proot >= 5.1.0-1.3 is needed for the renameat2() syscall. It is available in Ubuntu 19.04 and newer. It is available in this PPA for Ubuntu 18.04:

  https://launchpad.net/~a-j-buxton/+archive/ubuntu/backports/

## Keys

Multistrap/apt needs public keys to verify the repositories. You must import the required keys into your local gpg keyring with the following commands:

    gpg --recv-key 9165938D90FDDD2E # raspbian-archive-keyring
    gpg --recv-key 82B129927FA3303E # raspberrypi-archive-keyring

You should take the necessary steps to ensure that you have authentic versions of these keys. Once received, UXMIGOS will export them as and when required.

On Ubuntu 16.04 you will also need to import these keys into the host apt trusted keys with the following commands:

    sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 9165938D90FDDD2E
    sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 82B129927FA3303E

You may also need to do this on Ubuntu 16.10, 17.04, 17.10 but it is not necessary on 18.04 and later.

## Pydo

UXMIGOS uses a build tool called [pydo](https://github.com/ali1234/pydo) which has been developed specifically to handle complex builds that don't produce executables and libraries. You must first install it:

    cd uxmigos-balena/pydo && sudo pip3 install .

## Docker

If have a docker in your system, you can run `./docker-build` to have a complete ecosystem to build the UXMIGOS

# BULID AND BOOTING UXMIGOS

## Configure UXMIGOS

In the file 'config.py' you can define:

    * The hostname
    * Packages to build (relating to packager folder)
    * The type or types for arch kernel

## Compiling UXMIGOS

First, initialize the project:

    pydo --init

To build the whole project run:

    pydo :build

To clean the whole project run:

    pydo :clean

You can view other options running:

    pydo -l

## RAW Booting of UXMIGOS (NOT for migration)

The build produces a boot/ directory containing everything needed to boot.

Run `./go.sh` to generate a fit `tgz` file and extract it onto blank boot fat partition on the SD card, normally `/dev/mmcblk0p1`.


# MIGRATION SCRIPTS

Onto dir `/packages/migscripts` are the scripts that will be executed automatically by the UXMIGOS system or by hand for the user.

Those scripts are in a bucked called `balenamigration` inside folder [migscripts](https://console.cloud.google.com/storage/browser/balenamigration/migscripts/?project=admobilize-testing)

The idea is that all scripts can be executed remotely, see the documentation below for more explanations.

## Scripts logs

All scripts, generate a remote log that is stored in [insightOps](https://insight.rapid7.com) inside a logset called `BalenaMigration`

The logset `BalenaMigration/eventLog` store the highlights of the migration process while the logset `BalenaMigration/commandLog` store the detail output of certain commands inside scripts.

All remote logs are in `json` format and have the following fields:
  
  * device: ID of the device.
  * script: name of the script.
  * function: name of the function.
  * line: Number of the line that generates the log entry.
  * uptime: Kernel timestamp
  * state: Result of the event. Can be `INI`, `END`, `INFO` `OK`, `ERROR`, `FAIL`, `SUCCESS`, `EXIT` or `CMDLOG`
  * msg: Additional info.

Additionally a full detailed log is stored using the service of [filepush.sh](https://filepush.co/) the URL of this log can be found in the `BalenaMigration/eventLog` under the `logFilePush` function name.

## Order of manual execution scripts

Execute those scripts in the RaspbianOS system that will be migrated to the BalenaOS.

```
______________________
|                    |  * Validate Raspian version and RPI version
|                    |  * Validate Partition geometry of MMC
|  migDiagnostic.sh  |  * Validate Network connection and configuration
|                    |  * Validate AdBeacons configurations
|                    |  * Validate Files at bucket
|____________________|  * Generate mig.config
          ||
__________\/__________
|                    |  * BackUp Raspbian Boot Partition
|                    |  * BackUp system configuration files
|                    |  * Make Net configuration files for UXMIGOS and Balena
| migInstallUXMIGOS.sh |  * Download files from bucket
|                    |  * Delete Boot files of Raspbian
|                    |  * Download and install the last version of UXMIGOS
|____________________|  * Reboot the system to initiate the migration process (UXMIGOS)
```

If each script generates a successful result the next script can be executed.
If any script fails, pay attention to logs, to determinate the source of the error. 

## Order of automatic execution scripts

Those scrips are executed automatically by the systemd services of UXMIGOS

```
               ____________________
               |                  |  * Validate MMC
               |                  |  * Validate migstate dir
               |      /init       |  * Create Ramdisk
               |                  |  * Config network connection
               |                  |  * Update FSM Files
               |                  |  * Update resin Files
               |__________________|  * Update config.json
                                ||
_____________________        ___\/_________________    ___________________________
|                   |        |                    |    |                         |
|   migFlashSD.sh   |   <==  |  migSupervisor.sh  | => |  migRestoreRaspBoot.sh  |
|___________________|        |____________________|    |_________________________|

* FSM to download             * Test Network            * Validate and restore
  and install all             * Test FSM                  original boot files of 
  partitions of               * Restart mig2balena        Raspbian
  BalenaOS                    * reboot system

```


# MIGRATION PROCESS

In theory all migration process is completely automatized, the only manual process is to execute the initiation scripts. 
The `migPusher.sh` script was builds to send the command to execute remotely the manual scripts.
Is necessary previusly know the `ID` of the device target to migrate.

NOTE: The order of executions is very important (see above).

There are two options to run this, the recommend option is using the CLI tool.

## How to execute remotely via API HTTP

The usage structure is: `./migPusher.sh api <Device ID> <Script name>` where:

  * The `<Device ID>` will be in HEX format in lowercase
  * The `<Script name>` can be: `migDiagnostic`, `migBackup`, or migLaunch`

Example:

```
./migPusher.sh api b8_27_eb_a0_a8_71 migDiagnostic
./migPusher.sh api b8_27_eb_a0_a8_71 migInstallUXMIGOS
```

> The output of this script only say if the "pusher command" can be sent, to see the result of each script executed remotely is necessary see the log in the `insightOps` platform (see above)

## How to execute remotely via Pusher CLI

First, is necessary download and install the last version of **Pusher CLI**, the instructions are [here](https://pusher.com/docs/channels/pusher_cli/overview)

If you want to see the response of each pusher event sent, you can run `./migPusher.sh cli <Device ID> subscribe` in a parallel console.

Example:

```
./migPusher.sh cli b8_27_eb_a0_a8_71 subscribe
```

The other commands is like "API HTTP", only change `api` for `cli`

Example:

```
./migPusher.sh api b8_27_eb_a0_a8_71 migDiagnostic
./migPusher.sh api b8_27_eb_a0_a8_71 migInstallUXMIGOS
``

> The output of this script only say if the "pusher command" can be sent or fail, to see the result of each script executed remotely is necessary see the log on the `insightOps` platform (see above)
