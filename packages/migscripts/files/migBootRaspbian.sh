#!/bin/bash

# wget -O - 'http://10.0.0.211/balenaos/scripts/migBootRaspbian.sh' | bash
# wget -O - 'http://10.0.0.211/balenaos/scripts/migBootRaspbian.sh' | sudo bash
# wget http://10.0.0.211/balenaos/scripts/migBootRaspbian.sh

MIGSSTATEDIR_BOOT="/boot/migstate"
MIGSSTATEDIR_ROOT="/root/migstate"
MIGSSTATE_DIR="${MIGSSTATEDIR_ROOT}"
MIGCOMMAND_LOG="${MIGSSTATE_DIR}/cmdbootraspbian.log"
MIGSCRIPT_LOG="${MIGSSTATE_DIR}/migbootraspbian.log"
MIGBKP_RASPBIANBOOT="migboot-backup-raspbian.tgz"

MIGBOOT_MOUNTDIR='/boot'
MIGBOOT_DEVICE='/dev/mmcblk0p1'
MIGROOTFS_DEVICE='/dev/mmcblk0p2'
MIGROOTFS_MOUNTDIR='/mnt/rootfs'

# En caso de error, envia log del comando a la web
function logCommand {
    echo -e "MIGOS | ${BASH_SOURCE[1]##*/} | ${FUNCNAME[1]} | ${BASH_LINENO[0]} | $(cat /proc/uptime | awk '{print $1}') | INI | CMDLOG " |& tee -a ${MIGSCRIPT_LOG} /dev/kmsg

    if [[ -f ${MIGSSTATE_DIR}/MIGOS_NETWORK_OK ]]; then
        echo '{"device":"'"${MIGDID}"'", '\
        '"script":"migBootRaspbian.sh", '\
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
        echo -e "MIGOS | ${BASH_SOURCE[1]##*/} | ${FUNCNAME[1]} | ${BASH_LINENO[0]} | $(cat /proc/uptime | awk '{print $1}') | FAIL | Can not send CMDLOG, curl fail" |& tee -a ${MIGSCRIPT_LOG} /dev/kmsg
    else
        echo -e "MIGOS | ${BASH_SOURCE[1]##*/} | ${FUNCNAME[1]} | ${BASH_LINENO[0]} | $(cat /proc/uptime | awk '{print $1}') | FAIL | Can not send CMDLOG, No network" |& tee -a ${MIGSCRIPT_LOG} /dev/kmsg
    fi

    echo -e "MIGOS | ${BASH_SOURCE[1]##*/} | ${FUNCNAME[1]} | ${BASH_LINENO[0]} | $(cat /proc/uptime | awk '{print $1}') | END | CMDLOG " |& tee -a ${MIGSCRIPT_LOG} /dev/kmsg

    return 0
}

# Guarda log de evento en el archivo de log, lo muestra por kmsg y lo envia a la web
function logEvent {
    #TODO: touch Alive file for Watchdog
    if [[ -f ${MIGSSTATE_DIR}/MIGOS_NETWORK_OK ]]; then
        >${MIGCOMMAND_LOG}
        echo '{"device":"'"${MIGDID}"'", '\
        '"script":"migBootRaspbian.sh", '\
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
        echo -e "MIGOS | ${BASH_SOURCE[1]##*/} | ${FUNCNAME[1]} | ${BASH_LINENO[0]} | $(cat /proc/uptime | awk '{print $1}') | ${MIGSCRIPT_STATE} | $1" |& tee -a ${MIGSCRIPT_LOG} /dev/kmsg
    fi

    return 0
}


function restoreRaspianBoot {
	logEvent "INI"

    umount -v ${MIGBOOT_DEVICE} &>>${MIGSCRIPT_LOG}

    logEvent "mount" && \
    mount -v ${MIGBOOT_DEVICE} ${MIGBOOT_MOUNTDIR} &>>${MIGSCRIPT_LOG} && \
    logEvent "res" && \

    logEvent "rm all" && \
    rm -rf ${MIGBOOT_MOUNTDIR}/* &>>${MIGSCRIPT_LOG} && \
    logEvent "tar -x" && \
    tar -xzf /root/${MIGBKP_RASPBIANBOOT} -C /mnt &>>${MIGSCRIPT_LOG} && \
    logEvent "cp migstate" && \
    cp -r ${MIGSSTATE_DIR} ${MIGBOOT_MOUNTDIR}/ &>>${MIGSCRIPT_LOG} && \
    logEvent "reboot" && \
    {
        reboot;
        sleep 10;
    } || \
    {
        logEvent "FAIL"
        
        logCommand
        return 1
    }
	
}


logEvent "INI"

if [[ -f /root/${MIGBKP_RASPBIANBOOT} ]] ; then
    
else
    restoreRaspianBoot
fi

logEvent "END"

return 0