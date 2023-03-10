import pathlib

from pydo import *

this_dir = pathlib.Path(__file__).parent

package = {
    'requires': [],
    'sysroot_debs': [],
    'root_debs': ['wget', 'curl', 'jq'],
    'target': this_dir / 'migscripts.tar.gz',
    'install': [],
}

stage = this_dir / 'stage'
scriptsdirfiles = this_dir / 'files'

@command(produces=[package['target']])
def build():
    call([
        f'rm -rf --one-file-system {stage}',

        f'mkdir -p {stage}/usr/bin',
        
        f'chmod +x {scriptsdirfiles}/nettool.sh',
	    f'chmod +x {scriptsdirfiles}/migFlashSD.sh',
	    f'chmod +x {scriptsdirfiles}/migFunctions.sh',
	    f'chmod +x {scriptsdirfiles}/migSupervisor.sh',
	    f'chmod +x {scriptsdirfiles}/carrierConnect.sh',
	    f'chmod +x {scriptsdirfiles}/carrierSetup.sh',

        f'cp {scriptsdirfiles}/nettool.sh {stage}/usr/bin/',
        f'cp {scriptsdirfiles}/migFlashSD.sh {stage}/usr/bin/',
        f'cp {scriptsdirfiles}/migFunctions.sh {stage}/usr/bin/',
        f'cp {scriptsdirfiles}/migSupervisor.sh {stage}/usr/bin/',
        f'cp {scriptsdirfiles}/carrierConnect.sh {stage}/usr/bin/',
        f'cp {scriptsdirfiles}/carrierSetup.sh {stage}/usr/bin/',

        # f'cp {scriptsdirfiles}/migBackup.sh {stage}/usr/bin/',
        # f'cp {scriptsdirfiles}/migDiagnostic.sh {stage}/usr/bin/',

        f'tar -C {stage} -czf {package["target"]} .',
    ])


@command()
def clean():
    call([
        f'rm -rf --one-file-system {stage} {package["target"]}',
    ])
