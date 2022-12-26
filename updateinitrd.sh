#!/bin/bash
set -x

UXMIGOS_VERSION="$(git describe)"
UXMIGOS_BALENA_FILENAME="migboot-migos-balena_${UXMIGOS_VERSION}.tgz"
UXMIGOS_INITRDDIR='_INITRD'

# rm -rf ${UXMIGOS_INITRDDIR} && \
# mkdir -p ${UXMIGOS_INITRDDIR} && \
cd ${UXMIGOS_INITRDDIR} && \
# xz -dc ../boot/initrd | cpio -idmv && \
sudo bash -c "\
cp ../raspbian/overlay/init ./ && \
cp ../packages/migscripts/files/mig* usr/bin/ && \
find . 2>/dev/null -xdev -not \( -path host-rootfs -prune -path run -prune -path proc -prune -path sys -prune -path boot -prune \) | \
cpio --create -H newc | xz -C crc32 -9 > ../boot/initrd" && \
cd ../boot && \
touch "UXMIGOS_BOOT_INSTALLED" && \
tar -czf ../${UXMIGOS_BALENA_FILENAME} --owner=root --group=root ./* && \
cd .. && \
scp ${UXMIGOS_BALENA_FILENAME} trecetp@10.0.0.21:/srv/http/balenaos/migboot-uxmigos-balena.tgz && \
rsync -av packages/migscripts/files/* trecetp@10.0.0.21:/srv/http/balenaos/migscripts