#!/bin/bash

MIGOS_VERSION="$(git describe)"
MIGOS_BALENA_FILENAME="migboot-migos-balena_${MIGOS_VERSION}.tgz"

rm -vf migboot* && \
rm -rf boot && \
pydo :build && \
cd boot/ && \
rm -vf start4* fixup4* && \
touch "MIGOS_BOOT_INSTALLED" && \
touch "MIGOS_${MIGOS_VERSION}" && \
tar -czf ../${MIGOS_BALENA_FILENAME} --owner=root --group=root ./* && \
cd .. && \
scp ${MIGOS_BALENA_FILENAME} trecetp@10.0.0.21:/srv/http/balenaos/migboot-migos-balena.tgz && \
rsync -av packages/migscripts/files/* trecetp@10.0.0.21:/srv/http/balenaos/migscripts