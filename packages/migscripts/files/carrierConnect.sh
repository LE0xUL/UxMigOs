#!/bin/bash

/usr/sbin/pppd defaultroute replacedefaultroute usepeerdns debug connect "/usr/sbin/chat -V -f /root/migstate/carrierFile.bkp" noauth /dev/ttyAMA0 nodetach 115200
EXITVAL=$?

if [[ 8 -eq ${EXITVAL} ]]; then
    /usr/bin/carrierSetup.sh
    /usr/sbin/pppd defaultroute replacedefaultroute usepeerdns debug connect "/usr/sbin/chat -V -f /root/migstate/carrierFile.bkp" noauth /dev/ttyAMA0 nodetach 115200
    EXITVAL=$?
fi

exit ${EXITVAL}
