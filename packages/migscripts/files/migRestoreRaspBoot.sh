#!/bin/bash

# wget -O - 'http://10.0.0.229/balenaos/scripts/migRestoreRaspBoot.sh' | bash
# wget -O - 'http://10.0.0.229/balenaos/scripts/migRestoreRaspBoot.sh' | sudo bash
# wget http://10.0.0.229/balenaos/scripts/migRestoreRaspBoot.sh

MIGSSTATEDIR_BOOT="/boot/migstate"
MIGSSTATEDIR_ROOT="/root/migstate"
MIGSSTATEDIR_TEMP="/tmp/migstate"
MIGSSTATE_DIR="${MIGSSTATEDIR_ROOT}"
MIGCOMMAND_LOG="${MIGSSTATE_DIR}/cmdrestorerastboot.log"
MIGSCRIPT_LOG="${MIGSSTATE_DIR}/migrestorerastboot.log"
MIGBKP_RASPBIANBOOT="migboot-backup-raspbian.tgz"

MIGBOOT_DEVICE='/dev/mmcblk0p1'
MIGBOOT_MOUNTDIR='/mnt/boot'
MIGROOTFS_DEVICE='/dev/mmcblk0p2'
MIGROOTFS_MOUNTDIR='/mnt/rootfs'

# En caso de error, envia log del comando a la web
function logCommand {
    echo "MIGOS | ${BASH_SOURCE[1]##*/} | ${FUNCNAME[1]} | ${BASH_LINENO[0]} | $(cat /proc/uptime | awk '{print $1}') | INI | CMDLOG " |& tee -a ${MIGSCRIPT_LOG} /dev/kmsg

    if [[ -f ${MIGSSTATE_DIR}/MIGOS_NETWORK_OK ]]; then
        echo '{"device":"'"${MIGDID}"'", '\
        '"script":"migRestoreRaspBoot.sh", '\
        '"function":"'"${FUNCNAME[1]}"'", '\
        '"line":"'"${BASH_LINENO[0]}"'", '\
        '"uptime":"'"$(cat /proc/uptime | awk '{print $1}')"'", '\
        '"state":"'"CMDLOG"'", '\
        '"msg":"' | \
        cat - ${MIGCOMMAND_LOG} > temp.log && \
        mv temp.log ${MIGCOMMAND_LOG} && \
        echo '"}' >>${MIGCOMMAND_LOG} && \
        cat ${MIGCOMMAND_LOG} &>>${MIGSCRIPT_LOG} && \
        curl -X POST \
        -d "@${MIGCOMMAND_LOG}" \
        "${MIGWEBLOG_URL}/${MIGWEBLOG_KEYCOMMAND}" &>>${MIGSCRIPT_LOG} || \
        echo "MIGOS | ${BASH_SOURCE[1]##*/} | ${FUNCNAME[1]} | ${BASH_LINENO[0]} | $(cat /proc/uptime | awk '{print $1}') | FAIL | Can not send CMDLOG, curl fail" |& tee -a ${MIGSCRIPT_LOG} /dev/kmsg
    else
        echo "MIGOS | ${BASH_SOURCE[1]##*/} | ${FUNCNAME[1]} | ${BASH_LINENO[0]} | $(cat /proc/uptime | awk '{print $1}') | FAIL | Can not send CMDLOG, No network" |& tee -a ${MIGSCRIPT_LOG} /dev/kmsg
    fi

    echo "MIGOS | ${BASH_SOURCE[1]##*/} | ${FUNCNAME[1]} | ${BASH_LINENO[0]} | $(cat /proc/uptime | awk '{print $1}') | END | CMDLOG " |& tee -a ${MIGSCRIPT_LOG} /dev/kmsg

    return 0
}

# Guarda log de evento en el archivo de log, lo muestra por kmsg y lo envia a la web
function logEvent {
    if [[ -f ${MIGSSTATE_DIR}/MIGOS_NETWORK_OK ]]; then
        >${MIGCOMMAND_LOG}
        echo '{"device":"'"${MIGDID}"'", '\
        '"script":"migRestoreRaspBoot.sh", '\
        '"function":"'"${FUNCNAME[1]}"'", '\
        '"line":"'"${BASH_LINENO[0]}"'", '\
        '"uptime":"'"$(cat /proc/uptime | awk '{print $1}')"'", '\
        '"state":"'"${MIGSCRIPT_STATE}"'", '\
        '"msg":"'"$1"'"}' | \
        tee -a ${MIGSCRIPT_LOG} /dev/kmsg /dev/tty | \
        curl -i -H "Accept: application/json" \
        -X POST \
        --data @- \
        "${MIGWEBLOG_URL}/${MIGWEBLOG_KEYEVENT}" &>>${MIGCOMMAND_LOG} || logCommand
    else
        echo "MIGOS | ${BASH_SOURCE[1]##*/} | ${FUNCNAME[1]} | ${BASH_LINENO[0]} | $(cat /proc/uptime | awk '{print $1}') | ${MIGSCRIPT_STATE} | $1" |& tee -a ${MIGSCRIPT_LOG} /dev/kmsg
    fi

    return 0
}

function exitError {
    MIGSCRIPT_STATE="EXIT"
    logEvent "${BASH_SOURCE[1]##*/}:${FUNCNAME[1]}[${BASH_LINENO[0]}]"

    touch ${MIGSSTATE_DIR}/MIG_RESTORE_RASPBIAN_BOOT_FAIL
    #TODO: sent logfile to transfer.sh
    exit 1
}

function restoreRaspianBoot {
	MIGSCRIPT_STATE="INI"
    logEvent

    MIGSCRIPT_STATE="INFO"

    umount -v ${MIGBOOT_DEVICE} &>>${MIGSCRIPT_LOG}
    mkdir -vp ${MIGBOOT_MOUNTDIR} &>>${MIGSCRIPT_LOG} || exitError

    rm -vrf ${MIGSSTATEDIR_TEMP} &>>${MIGSCRIPT_LOG} || exitError

    logEvent "mount"
    mount -v ${MIGBOOT_DEVICE} ${MIGBOOT_MOUNTDIR} &>>${MIGSCRIPT_LOG} || exitError
    logEvent "migstate boot backup"
    cp -rv ${MIGBOOT_MOUNTDIR}/migstate /tmp &>>${MIGSCRIPT_LOG} || exitError 
    logEvent "rm all"
    rm -rf ${MIGBOOT_MOUNTDIR}/* &>>${MIGSCRIPT_LOG} || exitError
    logEvent "tar -x"
    tar -xzvf /root/${MIGBKP_RASPBIANBOOT} -C /mnt &>>${MIGSCRIPT_LOG} || exitError
    logEvent "cp migstate"
    cp -rv ${MIGSSTATEDIR_TEMP} ${MIGBOOT_MOUNTDIR} &>>${MIGSCRIPT_LOG} || exitError
    logEvent "Success Restore RaspbianBoot"

    MIGSCRIPT_STATE="END"
    logEvent
}

function mainRestoreRaspBoot {
    MIGSCRIPT_STATE="INI"
    logEvent

    rm -vf ${MIGSSTATE_DIR}/MIG_RESTORE_RASPBIAN_BOOT_FAIL &>>${MIGSCRIPT_LOG}

    if [[ ! -f /root/${MIGBKP_RASPBIANBOOT} ]] ; then
        MIGSCRIPT_STATE="FAIL"
        logEvent "Missing /root/${MIGBKP_RASPBIANBOOT}"
        exitError
    fi

    if [[ -f ${MIGSSTATE_DIR}/MIG_FSM_SFDISK_OK ]]; then
        MIGSCRIPT_STATE="FAIL"
        logEvent "The Partition table was altered"
        exitError
    fi

    restoreRaspianBoot

    MIGSCRIPT_STATE="END"
    logEvent
}

mainRestoreRaspBoot
exit 0