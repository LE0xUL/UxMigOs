import os
import posixpath
import pathlib

from pydo import *

env = os.environ.copy()

this_dir = pathlib.Path(__file__).parent

try:
    env['http_proxy'] = os.environ['APT_HTTP_PROXY']
except KeyError:
    print("Don't forget to set up apt-cacher-ng")


def relative_links(root):
    for path in pathlib.Path(root).rglob('*'):
        if path.is_symlink():
            link_target = os.readlink(str(path))
            if link_target[0] != '/':
                continue
            if link_target.startswith(str(root)):
                continue
            path.unlink()
            new_target = posixpath.relpath(root / link_target[1:], start=path.parent)
            # print(path, ':', link_target, '->', new_target)
            os.symlink(new_target, str(path))

toolchain_tarball = download(this_dir, 'https://github.com/ali1234/rpi-toolchain/releases/download/buster-0/toolchain-raspbian-buster-0-x86_64-arm-linux-gnueabihf.tar.xz')
toolchain = this_dir / 'toolchain'
sysroot = this_dir / 'sysroot'
cross_compile = toolchain / 'bin/arm-linux-gnueabihf-'
arch_cflags = ' '.join([
    '-pipe',
    '-march=armv6zk',
    '-marm',
    '-mthumb-interwork',
    '-mfpu=vfp',
    #'-mtune=cortex-a7',
    '-mabi=aapcs-linux',
    '-mfloat-abi=hard',
])

env['PATH'] += ':' + str(toolchain / 'bin')
env['SYSROOT'] = str(sysroot)

#### pkg-config workarounds ####

# pkg-config cannot handle sysroots properly, so we need to use a
# wrapper to adjust any paths it outputs.
env['PKG_CONFIG'] = str(this_dir / 'pkg-config')
env['PKG_CONFIG_DIR'] = ''
env['PKG_CONFIG_SYSROOT_DIR'] = str(sysroot)
env['PKG_CONFIG_LIBDIR'] = ':'.join(str(sysroot / p) for p in [
    'usr/lib/pkgconfig',
    'usr/lib/arm-linux-gnueabihf/pkgconfig',
    'usr/share/pkgconfig',
    'opt/vc/lib/pkgconfig',
])

# symlink the brcm* pcs so that Qt etc can find them
# brcmegl.pc needs content patches so that is handled in the overlay
pkgconfig_links = ['glesv2.pc', 'vg.pc', 'egl.pc']

# inform pkg-config wrapper the location of the packages basedir
env['PACKAGES'] = str(this_dir.parent / 'packages')


#### gobject-introspection workarounds ####

# G-I binding generation is done by building a native executable and
# then running it to see what it exports. We need Qemu for this.
env['QEMU_LD_PREFIX'] = str(sysroot)
env['LD_LIBRARY_PATH'] = str(sysroot / 'opt/vc/lib')

# search dirs for G-I
env['XDG_DATA_DIRS'] = ':'.join(str(sysroot / p) for p in [
    'usr/share',
])


@command(produces=[toolchain], consumes=[toolchain_tarball])
def unpack_toolchain():
    call([
        f'mkdir -p {toolchain}',
        f'tar -C {toolchain} --strip-components=1 -xf {toolchain_tarball}',
    ])


# delay importing packages until the sysroot variables are defined
from .. import packages

multistrap_conf = this_dir / 'multistrap.conf'
multistrap_conf_in = this_dir / 'multistrap.conf.in'
overlay = this_dir / 'overlay'


@command(produces=[multistrap_conf], consumes=[multistrap_conf_in], always=True)
def build_multistrap_conf():
    all_sysroot_debs = sorted(set.union(*(set(p.package['sysroot_debs']) for p in packages.packages.values()), set()))
    multistrap_packages = textwrap(all_sysroot_debs, prefix='packages=')
    subst(multistrap_conf_in, multistrap_conf, {'@PACKAGES@': multistrap_packages})


@command(produces=[sysroot], consumes=[multistrap_conf, *dir_scan(overlay)])
def build():
    call([
        f'rm -rf --one-file-system {sysroot}',

        f'mkdir -p {sysroot}/etc/apt/trusted.gpg.d/',
        f'gpg --export 82B129927FA3303E > {sysroot}/etc/apt/trusted.gpg.d/raspberrypi-archive-keyring.gpg',
        f'gpg --export 9165938D90FDDD2E > {sysroot}/etc/apt/trusted.gpg.d/raspbian-archive-keyring.gpg',
        f'/usr/sbin/multistrap -d {sysroot} -f {multistrap_conf}',

        # work around for the following bugs:
        #  https://github.com/raspberrypi/firmware/issues/1013
        #  https://bugreports.qt.io/browse/QTBUG-62216
        #  https://bugreports.qt.io/browse/QTBUG-69176
        # The workaround is simply to copy manually fixed pkgconfig files
        # somewhere where the build will find them.
        f'cp -r {overlay}/* {sysroot}',

        # symbolic links for pkgconfig
        *[f'ln -sf brcm{l} {sysroot}/opt/vc/lib/pkgconfig/{l}' for l in pkgconfig_links],

        # work around for libtool badness. is this still needed?
        # mkdir -p sysroot/opt
        # cd sysroot/opt && for dir in $(PACKAGES); do ln -s ../../$$dir/root/opt/$$dir $$dir; done

        # touch dir so we don't rebuild
        f'touch {sysroot}',
    ], shell=True, env=env)
    relative_links(sysroot)


@command()
def clean():
    call([
        f'rm -rf --one-file-system {sysroot} {toolchain} {multistrap_conf}'
    ])
