#!/bin/bash

# Script to migrate the OS of any Linux Device Using MIGOS
# USAGE: FILE_IMG2FLASH= FILE_MIGOS_BOOT= URL_BUCKET2DOWN= migrateOS.sh
set -x

: ${FILE_IMG2FLASH:=BalenaMigration32-rpi3-2.72.0_rev1-v12.3.5.img.gz}
: ${FILE_MIGOS_BOOT:=migboot-migos-balena.tgz}
: ${URL_BUCKET2DOWN:=https://storage.googleapis.com/balenamigration/m4b/}

DIR_BOOT_MIGSTATE="/mnt/boot/migstate"
DIR_OLD_MIGSTATE="/mnt/data/migstate.old"
DIR_MIGDATA="/mnt/data"
DIR_MIGDOWNLOADS="${DIR_MIGDATA}/migdownloads"

FILE_BACKUP_BOOT="mig-backup-boot.tgz"
FILE_MIG_CONFIG="mig.config"
FILE_WPA_CONFIG="wpa_supplicant.conf.bkp"
FILE_RESIN_WLAN="resin-wlan"

mkdir -vp ${DIR_OLD_MIGSTATE} || exit $LINENO
mkdir -vp ${DIR_MIGDOWNLOADS} || exit $LINENO

# Backup Boot partition
[[ ! -f ${DIR_MIGDATA}/${FILE_BACKUP_BOOT} ]] && \
{   
    cd /mnt/boot/ \
    && [[ ! -f MIGOS_BOOT_INSTALLED ]] \
    && tar -czf ${DIR_MIGDATA}/${FILE_BACKUP_BOOT} . \
    || exit $LINENO
}

# Get and check balena image
cd ${DIR_MIGDOWNLOADS} || exit $LINENO

[[ ! -f ${FILE_IMG2FLASH} ]] && \
{   
    wget ${URL_BUCKET2DOWN}${FILE_IMG2FLASH} \
    || exit $LINENO
}

wget ${URL_BUCKET2DOWN}${FILE_IMG2FLASH}.md5 -O ${FILE_IMG2FLASH}.md5 \
|| exit $LINENO

md5sum --check ${FILE_IMG2FLASH}.md5 || exit $LINENO

#wget MIGOS
[[ ! -f ${FILE_MIGOS_BOOT} ]] && \
{   
    wget ${URL_BUCKET2DOWN}${FILE_MIGOS_BOOT} \
    || exit $LINENO
}

wget ${URL_BUCKET2DOWN}${FILE_MIGOS_BOOT}.md5 -O ${FILE_MIGOS_BOOT}.md5 \
|| exit $LINENO

#Check MIGOS
md5sum --check ${FILE_MIGOS_BOOT}.md5 || exit $LINENO

#Backup config files
cp -v /mnt/boot/system-connections/resin* ${DIR_OLD_MIGSTATE} \
&& rm -vrf ${DIR_OLD_MIGSTATE}\*.ignore \
|| exit $LINENO

[[ -d ${DIR_BOOT_MIGSTATE} ]] && \
{
    mv -v ${DIR_BOOT_MIGSTATE}/* ${DIR_OLD_MIGSTATE} \
    || exit $LINENO
}

#install MIGOS
rm -rf /mnt/boot/* || exit $LINENO
tar -xzf ${FILE_MIGOS_BOOT} -C /mnt/boot/

#Restore Config Files
mkdir -vp ${DIR_BOOT_MIGSTATE} || exit $LINENO

[[ -f ${DIR_OLD_MIGSTATE}/${FILE_WPA_CONFIG} ]] \
&& cp -v ${DIR_OLD_MIGSTATE}/${FILE_WPA_CONFIG} ${DIR_BOOT_MIGSTATE}

# TODO: Make WPA_CONFIG file is WIFI is present

[[ -f ${DIR_OLD_MIGSTATE}/${FILE_RESIN_WLAN} ]] \
&& cp -v ${DIR_OLD_MIGSTATE}/${FILE_RESIN_WLAN} ${DIR_BOOT_MIGSTATE}

[[ -f ${DIR_OLD_MIGSTATE}/${FILE_MIG_CONFIG} ]] \
&& cp -v ${DIR_OLD_MIGSTATE}/${FILE_MIG_CONFIG} ${DIR_BOOT_MIGSTATE} || \
{
    # echo "MIGCONFIG_ETH_CONN='UP'" >>${DIR_BOOT_MIGSTATE}/${FILE_MIG_CONFIG}
    # echo "MIGCONFIG_ETH_DHCP='YES'" >>${DIR_BOOT_MIGSTATE}/${FILE_MIG_CONFIG}
    touch ${DIR_BOOT_MIGSTATE}/${FILE_MIG_CONFIG}
    echo "MIGCONFIG_DID='$(hostname)'" >>${DIR_BOOT_MIGSTATE}/${FILE_MIG_CONFIG}
}

echo "MIGCONFIG_IMG2FLASH='${FILE_IMG2FLASH}'" >>${DIR_BOOT_MIGSTATE}/${FILE_MIG_CONFIG}
echo "MIGCONFIG_BUCKET2DOWN='${URL_BUCKET2DOWN}'" >>${DIR_BOOT_MIGSTATE}/${FILE_MIG_CONFIG}

# MIGCONFIG_DEVDATAFS /dev/mmcblk0p6

set +x