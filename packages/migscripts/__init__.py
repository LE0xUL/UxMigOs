import pathlib

from pydo import *

this_dir = pathlib.Path(__file__).parent

package = {
    'requires': [],
    'sysroot_debs': [],
    'root_debs': ['wget', 'curl'],
    'target': this_dir / 'migscripts.tar.gz',
    'install': [],
}

stage = this_dir / 'stage'
scriptsdirfiles = this_dir / 'files/'

@command(produces=[package['target']])
def build():
    call([
        f'rm -rf --one-file-system {stage}',

        f'mkdir -p {stage}/usr/bin',

        f'cp {scriptsdirfiles}/nettool.sh {stage}/usr/bin/',
        f'cp {scriptsdirfiles}/migBackup.sh {stage}/usr/bin/',
        f'cp {scriptsdirfiles}/migDiagnostic.sh {stage}/usr/bin/',
        f'cp {scriptsdirfiles}/migWatchDog.sh {stage}/usr/bin/',

        f'tar -C {stage} -czf {package["target"]} .',
    ])


@command()
def clean():
    call([
        f'rm -rf --one-file-system {stage} {package["target"]}',
    ])
