#!/bin/bash

#rm -vf *md5

fileList=( \
	'migInstallUXMIGOS.sh' \
	'migDiagnostic.sh' \
	'migRestoreRaspbBoot.sh' \
	)

for fileName in ${fileList[@]}
do
	md5sum ${fileName} > ${fileName}.md5
done
