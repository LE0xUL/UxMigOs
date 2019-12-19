#!/bin/bash

MIGOS_VERSION="$(git describe)"
MIGOS_BALENA_FILENAME="migboot-migos-balena_${MIGOS_VERSION}.tgz"
MIGOS_INITRDDIR='_INITRD'

# rm -rf ${MIGOS_INITRDDIR} && \
# mkdir -p ${MIGOS_INITRDDIR} && \
cd ${MIGOS_INITRDDIR} && \
# xz -dc ../boot/initrd | cpio -idmv && \
sudo bash -c "\
cp ../raspbian/overlay/init ./ && \
cp ../packages/migscripts/files/mig* usr/bin/ && \
find . 2>/dev/null -xdev -not \( -path host-rootfs -prune -path run -prune -path proc -prune -path sys -prune -path boot -prune \) | \
cpio --create -H newc | xz -C crc32 -9 > ../boot/initrd" && \
cd ../boot && \
tar -czf ../${MIGOS_BALENA_FILENAME} --owner=root --group=root ./* && \
cd .. && \
scp ${MIGOS_BALENA_FILENAME} trecetp@10.0.0.211:/srv/http/balenaos/ && \
rsync -av packages/migscripts/files/* trecetp@10.0.0.211:/srv/http/balenaos/scripts
