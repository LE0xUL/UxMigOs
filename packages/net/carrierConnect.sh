#!/bin/bash

/usr/sbin/pppd defaultroute replacedefaultroute usepeerdns debug connect "/usr/sbin/chat -V -f /mnt/fsroot/usr/local/share/admobilize-adbeacon-software/public/files/carrierFile" noauth /dev/ttyAMA0 nodetach 115200
EXITVAL=$? 
exit $EXITVAL
