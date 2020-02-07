#!/bin/bash

# wget -O - 'http://10.0.0.21/balenaos/migscripts/migBackup.sh' | bash
# curl -s 'http://10.0.0.21/balenaos/migscripts/migBackup.sh' | bash
# wget -O - 'https://storage.googleapis.com/balenamigration/migscripts/migBackup.sh?ignoreCache=1' | bash
# curl 'https://storage.googleapis.com/balenamigration/migscripts/migBackup.sh?ignoreCache=1' --output migBackup.sh

MIGTIME_INI="$(cat /proc/uptime | grep -o '^[0-9]\+')"

MIGSSTATEDIR_BOOT="/boot/migstate"
MIGSSTATEDIR_ROOT="/root/migstate"
MIGSSTATE_DIR="${MIGSSTATEDIR_ROOT}"

MIGNET_EN_FILE="${MIGSSTATE_DIR}/en.network"
MIGNET_WLAN0_FILE="${MIGSSTATE_DIR}/wlan0.network"

MIGCOMMAND_LOG="${MIGSSTATE_DIR}/cmd.log"
MIGSCRIPT_LOG="${MIGSSTATE_DIR}/backup.log"
MIGSCRIPT_STATE='STATE'
MIGCONFIG_FILE="${MIGSSTATE_DIR}/mig.config"
## Device ID
MIGDID="$(hostname)"
MIGMMC="/dev/mmcblk0"
MIGBOOT_DEV='/dev/mmcblk0p1'
MIGBKP_RASPBIANBOOT="/root/migboot-backup-raspbian.tgz"

# TODO: MIGOS_VERSION="$(git describe)"
# TODO: MIGOS_BALENA_FILENAME="migboot-migos-balena_${MIGOS_VERSION}.tgz"
MIGOS_BALENA_FILENAME="migboot-migos-balena.tgz"
MIGOS_BALENA_FILEPATH="/root/${MIGOS_BALENA_FILENAME}"

MIGWEBLOG_URL='https://eu.webhook.logs.insight.rapid7.com/v1/noformat'
MIGWEBLOG_KEYEVENT='f79248d1-bbe0-427b-934b-02a2dee5f24f'
MIGWEBLOG_KEYCOMMAND='642de669-cf83-4e19-a6bf-9548eb7f5210'

MIGBUCKET_URL='http://10.0.0.21/balenaos'
# MIGBUCKET_URL='https://storage.googleapis.com/balenamigration'
MIGBUCKET_FILETEST='test.file'

function bkpExitError {
    touch ${MIGSSTATE_DIR}/MIG_BACKUP_FAIL

    [[ -f ${MIGCOMMAND_LOG} ]] && cat ${MIGCOMMAND_LOG}

    migRestoreBoot
    
    echo -e "\n\n" | tee -a ${MIGSCRIPT_LOG}
    echo -e "###############" | tee -a ${MIGSCRIPT_LOG}
    echo -e "# BACKUP FAIL #" | tee -a ${MIGSCRIPT_LOG}
    echo -e "###############" | tee -a ${MIGSCRIPT_LOG}
    echo -e "\n" | tee -a ${MIGSCRIPT_LOG}
    date | tee -a ${MIGSCRIPT_LOG}
    echo -e "\n\n" | tee -a ${MIGSCRIPT_LOG}
    echo "${BASH_SOURCE[1]##*/}:${FUNCNAME[1]}[${BASH_LINENO[0]}]" | tee -a ${MIGSCRIPT_LOG}
    exit
}

function logCommand {
    echo '{"device":"'"${MIGDID}"'", '\
    '"script":"migBackup.sh", '\
    '"function":"'"${FUNCNAME[1]}"'", '\
    '"line":"'"${BASH_LINENO[0]}"'", '\
    '"uptime":"'"$(cat /proc/uptime | awk '{print $1}')"'", '\
    '"state":"'"CMDLOG"'", '\
    '"msg":"' | \
    cat - ${MIGCOMMAND_LOG} > temp.log && \
    mv temp.log ${MIGCOMMAND_LOG} && \
    echo '"}' >> ${MIGCOMMAND_LOG} && \
    cat ${MIGCOMMAND_LOG} &>> ${MIGSCRIPT_LOG} && \
    curl -X POST \
    -d "@${MIGCOMMAND_LOG}" \
    "${MIGWEBLOG_URL}/${MIGWEBLOG_KEYCOMMAND}" || \
    echo "${BASH_SOURCE[1]##*/} | ${FUNCNAME[1]} | ${BASH_LINENO[0]} | $(cat /proc/uptime | awk '{print $1}') | FAIL | Can not send CMDLOG, curl fail" |& tee -a ${MIGSCRIPT_LOG}
}

function logEvent {
    echo '{"device":"'"${MIGDID}"'", '\
    '"script":"migBackup.sh", '\
    '"function":"'"${FUNCNAME[1]}"'", '\
    '"line":"'"${BASH_LINENO[0]}"'", '\
    '"uptime":"'"$(cat /proc/uptime | awk '{print $1}')"'", '\
    '"state":"'"${MIGSCRIPT_STATE}"'", '\
    '"msg":"'"$1"'"}' | \
    tee -a ${MIGSCRIPT_LOG} /dev/tty | \
    curl -i -H "Accept: application/json" \
    -X POST \
    --data @- \
    "${MIGWEBLOG_URL}/${MIGWEBLOG_KEYEVENT}" &>${MIGCOMMAND_LOG} || \
    logCommand
}

function backupFile {
    MIGBKP_FILENAME=$(echo "$1" | awk '{n=split($1,A,"/"); print A[n]}')
    
    if [[ -f $1 ]]; then
        cp $1 "${MIGSSTATE_DIR}/${MIGBKP_FILENAME}.bkp" &> ${MIGCOMMAND_LOG} || \
        { logCommand; bkpExitError; }
        MIGSCRIPT_STATE="OK"
        logEvent "backuped ${MIGBKP_FILENAME}"
    else
        MIGSCRIPT_STATE="FAIL"
        logEvent "Missing $1"
        bkpExitError
    fi
}

function backupSystemFiles {
    MIGSCRIPT_STATE="INI"
    logEvent

    backupFile '/etc/network/interfaces'
    backupFile '/etc/hostname'
    backupFile '/usr/local/share/admobilize-adbeacon-software/config/json/device.json'

    [[ 'UP' == "${MIGCONFIG_WLAN_CONN}" ]] && backupFile '/etc/wpa_supplicant/wpa_supplicant.conf'
    
    if [[ 'NO' == "${MIGCONFIG_ETH_DHCP}" ]] || [[ 'NO' == "${MIGCONFIG_WLAN_DHCP}" ]];then
        backupFile '/etc/dhcpcd.conf'
    fi

    MIGSCRIPT_STATE="END"
    logEvent
}

function backupBootPartition {
    MIGSCRIPT_STATE="INI"
    logEvent

    cd /root && tar -czf ${MIGBKP_RASPBIANBOOT} /boot/* &>${MIGCOMMAND_LOG} || { logCommand; bkpExitError; }
    MIGSCRIPT_STATE="OK"
    logEvent "Created boot backup file: ${MIGBKP_RASPBIANBOOT}"
    
    # && sudo wget 10.0.0.210/balenaos/boot-ramdisk-60.tgz && sudo rm -rf /boot/* && sudo tar -xzvf boot-ramdisk-60.tgz -C / && sudo reboot
    
    MIGSCRIPT_STATE="END"
    logEvent
}

function migRestoreBoot {
    MIGSCRIPT_STATE="INI"
    logEvent

    if [[ -f ${MIGBKP_RASPBIANBOOT} ]];then
        rm -rf /boot/* &>${MIGCOMMAND_LOG} || { logCommand; bkpExitError; }
        tar -xzf ${MIGBKP_RASPBIANBOOT} -C / &>${MIGCOMMAND_LOG} || { logCommand; bkpExitError; }

        MIGSCRIPT_STATE="OK"
        logEvent "Restaured Backup in boot partition"
    else
        MIGSCRIPT_STATE="FAIL"
        logEvent "Missing BackUp File: ${MIGBKP_RASPBIANBOOT}"
    fi

    MIGSCRIPT_STATE="END"
    logEvent
}

function installMIGOS {
    MIGSCRIPT_STATE="INI"
    logEvent

    wget -O ${MIGOS_BALENA_FILEPATH} "${MIGBUCKET_URL}/${MIGOS_BALENA_FILENAME}" &>${MIGCOMMAND_LOG} || { logCommand; bkpExitError; }
    rm -rf /boot/* &>${MIGCOMMAND_LOG} || { logCommand; bkpExitError; }
    tar -xzf ${MIGOS_BALENA_FILEPATH} -C /boot &>${MIGCOMMAND_LOG} || { logCommand; bkpExitError; }

    MIGSCRIPT_STATE="OK"
    logEvent "installed MIGOS in boot partition"

    ls /boot &> ${MIGCOMMAND_LOG} && cat ${MIGCOMMAND_LOG} &>> ${MIGSCRIPT_LOG} && \
    logCommand || bkpExitError
    
    MIGSCRIPT_STATE="END"
    logEvent
}

function migState2Boot {
    MIGSCRIPT_STATE="INI"
    logEvent

    # mkdir -p ${MIGSSTATEDIR_BOOT} &>${MIGCOMMAND_LOG} || { logCommand; bkpExitError; }
    cp -rv ${MIGSSTATE_DIR} /boot |& tee -a ${MIGCOMMAND_LOG} ${MIGSCRIPT_LOG} || { logCommand; bkpExitError; }
    # cp -rv ${MIGSSTATE_DIR}/ ${MIGSSTATEDIR_BOOT}/ &>${MIGCOMMAND_LOG} || 

    MIGSCRIPT_STATE="OK"
    logEvent "Copyed migState in boot partition"

    ls -alh /boot &> ${MIGCOMMAND_LOG} && cat ${MIGCOMMAND_LOG} &>> ${MIGSCRIPT_LOG} && \
    logCommand || bkpExitError
    
    MIGSCRIPT_STATE="END"
    logEvent
}

function makeNetFiles {
    MIGSCRIPT_STATE="INI"
    logEvent

    if [[ 'NO' == "${MIGCONFIG_ETH_DHCP}" ]];then
        >${MIGNET_EN_FILE} &>${MIGCOMMAND_LOG} || { logCommand; bkpExitError; }

        echo "[match]" | tee -a ${MIGNET_EN_FILE} &>${MIGCOMMAND_LOG} || { logCommand; bkpExitError; }
        echo "Name=en*" | tee -a ${MIGNET_EN_FILE} &>${MIGCOMMAND_LOG} || { logCommand; bkpExitError; }
        echo "[Network]" | tee -a ${MIGNET_EN_FILE} &>${MIGCOMMAND_LOG} || { logCommand; bkpExitError; }
        
        if [[ -n ${MIGCONFIG_ETH_IPMASK} ]];then
            echo "Address=${MIGCONFIG_ETH_IPMASK}" | tee -a ${MIGNET_EN_FILE} &>${MIGCOMMAND_LOG} || \
            { logCommand; bkpExitError; }
        else
            MIGSCRIPT_STATE="FAIL"
            logEvent "Missing MIGCONFIG_ETH_IPMASK"
            bkpExitError
        fi

        if [[ -n ${MIGCONFIG_ETH_GWIP} ]];then
            echo "Gateway=${MIGCONFIG_ETH_GWIP}" | tee -a ${MIGNET_EN_FILE} &>${MIGCOMMAND_LOG} || \
            { logCommand; bkpExitError; }
        else
            MIGSCRIPT_STATE="FAIL"
            logEvent "Missing MIGCONFIG_ETH_GWIP"
            bkpExitError
        fi

        if [[ -n ${MIGCONFIG_ETH_DNSIP} ]];then
            echo "DNS=${MIGCONFIG_ETH_DNSIP}" | tee -a ${MIGNET_EN_FILE} &>${MIGCOMMAND_LOG} || \
            { logCommand; bkpExitError; }
        else
            MIGSCRIPT_STATE="FAIL"
            logEvent "Missing MIGCONFIG_ETH_DNSIP"
            bkpExitError
        fi

        MIGSCRIPT_STATE="OK"
        logEvent "Created ethernet static IP config file: ${MIGNET_EN_FILE}"

        cat ${MIGNET_EN_FILE} &> ${MIGCOMMAND_LOG} && cat ${MIGCOMMAND_LOG} &>> ${MIGSCRIPT_LOG} && \
        logCommand || bkpExitError
    fi

    if [[ 'NO' == "${MIGCONFIG_WLAN_DHCP}" ]];then
        >${MIGNET_WLAN0_FILE} &>${MIGCOMMAND_LOG} || { logCommand; bkpExitError; }

        echo "[match]" | tee -a ${MIGNET_WLAN0_FILE} &>${MIGCOMMAND_LOG} || { logCommand; bkpExitError; }
        echo "Name=en*" | tee -a ${MIGNET_WLAN0_FILE} &>${MIGCOMMAND_LOG} || { logCommand; bkpExitError; }
        echo "[Network]" | tee -a ${MIGNET_WLAN0_FILE} &>${MIGCOMMAND_LOG} || { logCommand; bkpExitError; }
        
        if [[ -n ${MIGCONFIG_WLAN_IPMASK} ]];then
            echo "Address=${MIGCONFIG_WLAN_IPMASK}" | tee -a ${MIGNET_WLAN0_FILE} &>${MIGCOMMAND_LOG} || \
            { logCommand; bkpExitError; }
        else
            MIGSCRIPT_STATE="FAIL"
            logEvent "Missing MIGCONFIG_WLAN_IPMASK"
            bkpExitError
        fi

        if [[ -n ${MIGCONFIG_WLAN_GWIP} ]];then
            echo "Gateway=${MIGCONFIG_WLAN_GWIP}" | tee -a ${MIGNET_WLAN0_FILE} &>${MIGCOMMAND_LOG} || \
            { logCommand; bkpExitError; }
        else
            MIGSCRIPT_STATE="FAIL"
            logEvent "Missing MIGCONFIG_WLAN_GWIP"
            bkpExitError
        fi

        if [[ -n ${MIGCONFIG_WLAN_DNSIP} ]];then
            echo "DNS=${MIGCONFIG_WLAN_DNSIP}" | tee -a ${MIGNET_WLAN0_FILE} &>${MIGCOMMAND_LOG} || \
            { logCommand; bkpExitError; }
        else
            MIGSCRIPT_STATE="FAIL"
            logEvent "Missing MIGCONFIG_WLAN_DNSIP"
            bkpExitError
        fi

        MIGSCRIPT_STATE="OK"
        logEvent "Created wireless static IP config file: ${MIGNET_WLAN0_FILE}"

        cat ${MIGNET_WLAN0_FILE} &> ${MIGCOMMAND_LOG} && cat ${MIGCOMMAND_LOG} &>> ${MIGSCRIPT_LOG} && \
        logCommand || bkpExitError
    fi

    MIGSCRIPT_STATE="END"
    logEvent
}

function testIsRoot {
    # Run as root, of course.
    if [[ "$UID" -ne "$ROOT_UID" ]]
    then
        echo "[FAIL] Must be root to run this script."
        exit $LINENO
    else
        echo "[OK] Root"
    fi
}

function testBucketConnection {
    wget -q --tries=10 --timeout=10 --spider "${MIGBUCKET_URL}/$MIGBUCKET_FILETEST"

    if [[ $? -ne 0 ]]; then
        echo "[FAIL] No connection to the bucket server detected"
        echo "Is necessary a connection to the bucket server to run this script."
        exit $LINENO
    else
        echo "[OK] Network"
    fi
}

function testMigStateExist {
    [[ -d ${MIGSSTATE_DIR} ]] && \
    cd ${MIGSSTATE_DIR} && \
    [[ -f ${MIGSSTATE_DIR}/MIG_DIAGNOSTIC_SUCCESS ]] && \
    [[ -f ${MIGCONFIG_FILE} ]] && \
    echo "[OK] ${MIGSSTATE_DIR}/MIG_DIAGNOSTIC_SUCCESS" || \
    {
        echo "[FAIL] Is necessary run first the migDiagnostic.sh script with success result."
        exit $LINENO
    }
}

function iniBackupSystem {
    MIGSCRIPT_STATE="INI"

    testIsRoot
    testBucketConnection
    testMigStateExist

    [[ -d ${MIGSSTATEDIR_BOOT} ]] && rm -rf ${MIGSSTATEDIR_BOOT}
    [[ -f ${MIGSSTATE_DIR}/MIG_BACKUP_FAIL ]] && rm ${MIGSSTATE_DIR}/MIG_BACKUP_FAIL
    [[ -f ${MIGSSTATE_DIR}/MIG_BACKUP_SUCCESS ]] && rm ${MIGSSTATE_DIR}/MIG_BACKUP_SUCCESS

    echo -e "\n\n" | tee -a ${MIGSCRIPT_LOG}
    echo -e "**************" | tee -a ${MIGSCRIPT_LOG}
    echo -e "* BACKUP INI *" | tee -a ${MIGSCRIPT_LOG}
    echo -e "**************" | tee -a ${MIGSCRIPT_LOG}
    echo -e "" | tee -a ${MIGSCRIPT_LOG}
    date | tee -a ${MIGSCRIPT_LOG}
    echo -e "" | tee -a ${MIGSCRIPT_LOG}

    logEvent

    source ${MIGCONFIG_FILE} || \
    { logCommand; bkpExitError; }

    backupBootPartition
    backupSystemFiles
    makeNetFiles
    installMIGOS

    touch ${MIGSSTATE_DIR}/MIG_BACKUP_SUCCESS

    migState2Boot

    MIGSCRIPT_STATE="END"
    logEvent "TOTAL TIME: $(( $(cat /proc/uptime | grep -o '^[0-9]\+') - ${MIGTIME_INI} )) seconds"

    # echo -e "\n" | tee -a ${MIGSCRIPT_LOG}
    # cat ${MIGCONFIG_FILE} | tee -a ${MIGSCRIPT_LOG}
    echo -e "" | tee -a ${MIGSCRIPT_LOG}
    date | tee -a ${MIGSCRIPT_LOG}
    echo -e "" | tee -a ${MIGSCRIPT_LOG}
    echo -e "******************" | tee -a ${MIGSCRIPT_LOG}
    echo -e "* BACKUP SUCCESS *" | tee -a ${MIGSCRIPT_LOG}
    echo -e "******************" | tee -a ${MIGSCRIPT_LOG}
    echo -e "\n\n" | tee -a ${MIGSCRIPT_LOG}
    
    cp -rv ${MIGSSTATE_DIR} /boot &>${MIGCOMMAND_LOG} &>>${MIGSCRIPT_LOG} || \
    { logCommand; bkpExitError; }
}

iniBackupSystem

echo $LINENO
exit 0