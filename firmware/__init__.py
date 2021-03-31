import os
import pathlib

from pydo import *

env = os.environ.copy()

try:
    env['http_proxy'] = os.environ['APT_HTTP_PROXY']
except KeyError:
    print("Don't forget to set up apt-cacher-ng")

this_dir = pathlib.Path(__file__).parent

firmware_rev = '1.20201201'
firmware_dir = this_dir / 'firmware'
firmware = download(firmware_dir, f'https://github.com/raspberrypi/firmware/archive/{firmware_rev}.zip')

stage = this_dir / 'stage'
fwtmp = this_dir / 'fwtmp'
fwboot = this_dir / 'firmware-boot.tar.gz'
fwroot = this_dir / 'firmware-root.tar.gz'
sources = [this_dir / file for file in ['cmdline.txt', 'config.txt']]
msd = this_dir / 'usbboot' / 'msd' / 'start.elf'

modfiles = [ fwtmp / 'firmware-1.20201201' / 'modules' / '5.4.79-v7+' / file for file in [
    'modules.alias',
    'modules.alias.bin',
    'modules.builtin',
    'modules.builtin.alias.bin',
    'modules.builtin.bin',
    'modules.builtin.modinfo',
    'modules.dep',
    'modules.dep.bin',
    'modules.devname',
    'modules.order',
    'modules.softdep',
    'modules.symbols',
    'modules.symbols.bin',
    'kernel/drivers/spi/spidev.ko',
    'kernel/drivers/net/wireless/broadcom/brcm80211/brcmfmac/brcmfmac.ko',
    'kernel/drivers/net/wireless/broadcom/brcm80211/brcmutil/brcmutil.ko',
    'kernel/net/wireless/cfg80211.ko',
    'kernel/net/rfkill/rfkill.ko',
    'kernel/crypto/sha256_generic.ko',
    'kernel/lib/crypto/libsha256.ko',
    'kernel/drivers/hwmon/raspberrypi-hwmon.ko',
    'kernel/drivers/i2c/busses/i2c-bcm2835.ko',
    'kernel/drivers/usb/dwc2/dwc2.ko',
    'kernel/drivers/usb/gadget/udc/udc-core.ko',
    'kernel/drivers/media/mc/mc.ko',
    'kernel/drivers/staging/vc04_services/vchiq-mmal/bcm2835-mmal-vchiq.ko',
    'kernel/drivers/staging/vc04_services/vc-sm-cma/vc-sm-cma.ko',
    'kernel/drivers/spi/spi-bcm2835.ko',
    'kernel/drivers/regulator/fixed.ko',
    'kernel/drivers/uio/uio_pdrv_genirq.ko',
    'kernel/drivers/uio/uio.ko',
    'kernel/net/ipv4/netfilter/ip_tables.ko',
    'kernel/net/netfilter/x_tables.ko',
    'kernel/net/ipv6/ipv6.ko',
]]

delfiles = [ stage / 'boot' / file for file in [ 
    'kernel8.img',
    'kernel7l.img',
    'kernel.img',
    'start_db.elf',
    'start4db.elf',
    'start4x.elf',
    'start4.elf',
    'start4cd.elf',
    'start_cd.elf',
    'start.elf',
    'bcm2711-rpi-cm4.dtb',
    'fixup4db.dat',
    'fixup4x.dat',
    'bcm2708-rpi-b-plus.dtb',
    'bcm2711-rpi-4-b.dtb',
    'bcm2710-rpi-2-b.dtb',
    'LICENCE.broadcom',
    'bcm2708-rpi-zero.dtb',
    'bcm2708-rpi-b-rev1.dtb',
    'bcm2708-rpi-cm.dtb',
    'bcm2708-rpi-zero-w.dtb',
    'fixup4cd.dat',
    'fixup4.dat',
    'bcm2711-rpi-400.dtb',
    'bcm2708-rpi-b.dtb',
    'overlays/README',
]]

@command(produces = [fwboot, fwroot], consumes = [*sources, msd, firmware])
def build():
    call([
        f'rm -rf --one-file-system {stage}',
        f'rm -rf --one-file-system {fwtmp}',

        f'mkdir -p {fwtmp}/modtmp',
        f'mkdir -p {stage}/root/lib/modules',

        f'unzip -o {firmware} */boot/* -d {fwtmp}/',
        f'unzip -o {firmware} */modules/* -d {fwtmp}/',

        f'cp --parents {" ".join(str(s) for s in modfiles)} {fwtmp}/modtmp/',

        f'cp -R {fwtmp}/firmware-{firmware_rev}/boot {stage}/',
        f'cp -R {fwtmp}/modtmp/{fwtmp}/firmware-{firmware_rev}/modules/5.4.79-v7+ {stage}/root/lib/modules',
        f'cp {" ".join(str(s) for s in sources)} {stage}/boot/',

        f'rm -rf --one-file-system {" ".join(str(s) for s in delfiles)}',

        # f'rm -rf --one-file-system {stage}/root/lib/modules/5.4.79+',
        # f'rm -rf --one-file-system {stage}/root/lib/modules/5.4.79-v8+',
        # f'rm -rf --one-file-system {stage}/root/lib/modules/5.4.79-v7l+',

        # f'rm -rf --one-file-system {stage}/boot/kernel8.img',
        # f'rm -rf --one-file-system {stage}/boot/kernel7l.img',
        # f'rm -rf --one-file-system {stage}/boot/kernel.img',
        # f'rm -rf --one-file-system {stage}/boot/start_db.elf',
        # f'rm -rf --one-file-system {stage}/boot/start4db.elf',
        # f'rm -rf --one-file-system {stage}/boot/start4x.elf',
        # f'rm -rf --one-file-system {stage}/boot/start4.elf',
        # f'rm -rf --one-file-system {stage}/boot/start4cd.elf',
        # f'rm -rf --one-file-system {stage}/boot/start_cd.elf',
        # f'rm -rf --one-file-system {stage}/boot/start.elf',

        # f'cp {msd} {stage}/boot/msd.elf',
        f'touch {stage}/boot/UART',

        f'tar -C {stage}/boot/ -czvf {fwboot} .',
        f'tar -C {stage}/root/ -czvf {fwroot} .',

    ], env=env)


@command()
def clean():
    call([
        f'rm -rf --one-file-system {stage} {fwboot} {fwroot}'
    ])
