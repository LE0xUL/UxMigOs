#!/bin/bash

/usr/sbin/pppd defaultroute replacedefaultroute usepeerdns debug connect "/usr/sbin/chat -V -f /root/migstate/carrierFile.bkp" noauth /dev/ttyAMA0 nodetach 115200
EXITVAL=$? 
exit $EXITVAL
