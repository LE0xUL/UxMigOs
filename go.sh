#!/bin/bash

pydo :build && \
./gen_migos-boot.sh && \
# rm boot/start4.elf boot/start4cd.elf boot/start4db.elf boot/start4x.elf && \
# tar -czf migboot-migos-balena.tgz --owner=root --group=root boot/* && \
scp migboot-migos-balena.tgz trecetp@10.0.0.211:/srv/http/balenaos/
