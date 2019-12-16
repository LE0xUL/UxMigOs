#!/bin/bash

MIGOS_VERSION='V1.10'
MIGOS_BALENA_FILENAME="migboot-migos-balena.tgz"

# pydo :build && \
cd boot/ && \
rm start4.elf start4cd.elf start4db.elf start4x.elf && \
rm MIGOS_* && \
touch "MIGOS_${MIGOS_VERSION}" && \
tar -czf ../${MIGOS_BALENA_FILENAME} --owner=root --group=root ./*
# scp migboot-migos-balena.tgz trecetp@10.0.0.211:/srv/http/balenaos/
