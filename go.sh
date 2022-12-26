#!/bin/bash

UXMIGOS_VERSION="$(git describe)"
UXMIGOS_BALENA_FILENAME="migboot-uxmigos-balena_${UXMIGOS_VERSION}.tgz"

rm -vf migboot* && \
rm -rf boot && \
pydo :build && \
cd boot/ && \
rm -vf start4* fixup4* start_db.elf && \
touch "UXMIGOS_BOOT_INSTALLED" && \
touch "UXMIGOS_${UXMIGOS_VERSION}" && \
tar -czf ../${UXMIGOS_BALENA_FILENAME} --owner=root --group=root ./* && \
cd .. 
# scp ${UXMIGOS_BALENA_FILENAME} trecetp@10.0.0.21:/srv/http/balenaos/migboot-uxmigos-balena.tgz && \
# rsync -av packages/migscripts/files/* trecetp@10.0.0.21:/srv/http/balenaos/migscripts
