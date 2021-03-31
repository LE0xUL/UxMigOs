import os, pathlib

from pydo import *

this_dir = pathlib.Path(__file__).parent

try:
    from . import config
except ImportError:
    log.error('Error: Project is not configured.')
    exit(-1)

try:
    jobs = int(os.environ['PYDOJOBS'], 10)
except Exception:
    import multiprocessing
    jobs = multiprocessing.cpu_count()
    log.warning(f'Setting jobs to {jobs}.')

from . import firmware, raspbian, sysroot, packages


# kernel_boot_tarballs = [k.boot for k in kernel.kernels]
boot = this_dir / 'boot'
dnsmasq_conf_in = this_dir / 'dnsmasq.conf.in'
dnsmasq_conf = this_dir / 'dnsmasq.conf'


@command(produces=[dnsmasq_conf], consumes=[dnsmasq_conf_in])
def build_dnsmasq_conf():
    subst(dnsmasq_conf_in, dnsmasq_conf, {'@TFTP_ROOT@': str(boot)})


@command(produces=[boot], consumes=[firmware.fwboot, raspbian.initrd, dnsmasq_conf])
def build():
    call([
        f'mkdir -p {boot}',
        f'rm -rf --one-file-system {boot}/*',
        f'cp {raspbian.initrd} {boot}',
        f'tar -xf {firmware.fwboot} -C {boot}',
        # *list(f'tar -xf {kb} -C {boot}' for kb in kernel_boot_tarballs),
        # f'cd {boot} && zip -qr {boot} *',
        f'touch {boot}',
    ], shell=True)


@command()
def clean():
    sysroot.clean()
    firmware.clean()
    # kernel.clean()
    raspbian.clean()
    packages.clean()
