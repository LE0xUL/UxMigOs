import pathlib

from pydo import *

this_dir = pathlib.Path(__file__).parent

package = {
    'requires': ['net'],
    'sysroot_debs': [],
    'root_debs': ['ppp', 'psmisc'],
    'target': this_dir / 'mig3gconn.tar.gz',
    'install': ['{chroot} {stage} /bin/systemctl reenable mig3gconn.service'],
}

stage = this_dir / 'stage'
service = this_dir / 'mig3gconn.service'

@command(produces=[package['target']], consumes=[service])
def build():
    call([
        f'rm -rf --one-file-system {stage}',

        f'mkdir -p {stage}/etc/systemd/system',
        f'cp {service} {stage}/etc/systemd/system/',

        f'tar -C {stage} -czf {package["target"]} .',
    ])


@command()
def clean():
    call([
        f'rm -rf --one-file-system {stage} {package["target"]}',
    ])
