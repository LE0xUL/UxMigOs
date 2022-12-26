#!/bin/bash
MIGTIME_INI="$(cat /proc/uptime | grep -o '^[0-9]\+')"

MIGDID="$(hostname)"
[[ 0 -ne $? ]] && { echo "[FAIL] Can't set MIGDID"; exit $LINENO; }

MIGLOG_SCRIPTNAME="migRestoreRaspbBoot.sh"
MIGSSTATE_DIR="/root/migstate"
MIGSCRIPT_LOG="${MIGSSTATE_DIR}/migRestoreRaspbBoot.log"
MIGCOMMAND_LOG="${MIGSSTATE_DIR}/cmd.log"

MIGBKP_RASPBIANBOOT="/root/migboot-backup-raspbian.tgz"
MIGBOOT_DIR='/boot'

MIGWEBLOG_URL='https://eu.webhook.logs.insight.rapid7.com/v1/noformat'
MIGWEBLOG_KEYEVENT='f79248d1-bbe0-427b-934b-02a2dee5f24f'
MIGWEBLOG_KEYCOMMAND='642de669-cf83-4e19-a6bf-9548eb7f5210'

UXMIGOS_RASPBIAN_BOOT_FILE="/boot/UXMIGOS_RASPBIAN_BOOT_${MIGDID}"


# USE: logCommand 
# USE: logCommand MESSAGE 
# USE: logCommand MESSAGE FUNCNAME
# USE: logCommand MESSAGE FUNCNAME BASH_LINENO
# (implicitly the file set by ${MIGCOMMAND_LOG} is sent)
function logCommand {
    MIGLOG_CMDMSG="${1:-NO_MSG}"
    MIGLOG_CMDFUNCNAME="${2:-${FUNCNAME[1]}}"
    MIGLOG_CMDLINENO="${3:-${BASH_LINENO[0]}}"
    MIGLOG_CMDUPTIME="$(cat /proc/uptime | awk '{print $1}')"
    MIGLOG_CMDLOG="\n vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv \n $(cat ${MIGCOMMAND_LOG}) \n ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ \n"

    echo -e '{ "os":"RASPB", '\
    '"device":"'"${MIGDID}"'", '\
    '"script":"'"${MIGLOG_SCRIPTNAME}"'", '\
    '"function":"'"${MIGLOG_CMDFUNCNAME}"'", '\
    '"line":"'"${MIGLOG_CMDLINENO}"'", '\
    '"uptime":"'"${MIGLOG_CMDUPTIME}"'", '\
    '"state":"'"CMDLOG"'", '\
    '"msg":"'"${MIGLOG_CMDMSG}"'", '\
    '"cmdlog":"'"${MIGLOG_CMDLOG}"'"}' |& \
    tee -a ${MIGSCRIPT_LOG} |& \
    curl -ki --data @- "${MIGWEBLOG_URL}/${MIGWEBLOG_KEYCOMMAND}" &>>${MIGSCRIPT_LOG} || \
    echo "FAIL at send logCommand" &>>${MIGSCRIPT_LOG}
}

# USE: logevent STATE 
# USE: logevent STATE MESSAGE
# USE: logevent STATE MESSAGE FUNCNAME 
# USE: logevent STATE MESSAGE FUNCNAME BASH_LINENO
function logEvent {
    MIGLOG_STATE="${1:-INFO}"
    MIGLOG_MSG="${2:-INFO}"
    MIGLOG_FUNCNAME="${3:-${FUNCNAME[1]}}"
    MIGLOG_LINENO="${4:-${BASH_LINENO[0]}}"
    MIGLOG_UPTIME="$(cat /proc/uptime | awk '{print $1}')"

    echo '{ "os":"RASPB", '\
    '"device":"'"${MIGDID}"'", '\
    '"script":"'"${MIGLOG_SCRIPTNAME}"'", '\
    '"function":"'"${MIGLOG_FUNCNAME}"'", '\
    '"line":"'"${MIGLOG_LINENO}"'", '\
    '"uptime":"'"${MIGLOG_UPTIME}"'", '\
    '"state":"'"${MIGLOG_STATE}"'", '\
    '"msg":"'"${MIGLOG_MSG}"'"}' |& \
    tee -a ${MIGSCRIPT_LOG} |& \
    curl -kvi -H "Accept: application/json" \
    -X POST \
    --data @- \
    "${MIGWEBLOG_URL}/${MIGWEBLOG_KEYEVENT}" &>${MIGCOMMAND_LOG} || \
    logCommand "FAIL at send logEvent"
}

function logFilePush {
    MIGLOG_FILEPUSH_URLLOG=$(curl --upload-file "${MIGSCRIPT_LOG}" https://filepush.co/upload/)
    logEvent "INFO" "${MIGLOG_FILEPUSH_URLLOG}"
    echo "${MIGLOG_FILEPUSH_URLLOG}"
}

function exitError {
    touch ${MIGSSTATE_DIR}/MIG_RESTORE_RASPB_BOOT_FAIL
    MIGLOG_MSG="${1:-RESTORE_RASPB_BOOT_FAIL}"

    [[ "logCommand" == "$2" ]] && logCommand "${MIGLOG_MSG}" "${FUNCNAME[1]}" "${BASH_LINENO[0]}"

    logEvent "EXIT" "${MIGLOG_MSG}" "${FUNCNAME[1]}" "${BASH_LINENO[0]}"
    
    echo "" &>>${MIGSCRIPT_LOG}
    date |& tee -a ${MIGSCRIPT_LOG}
    echo "[ ####    RESTORE RASPB BOOT FAIL    #### ]" |& tee -a ${MIGSCRIPT_LOG}
    echo "" &>>${MIGSCRIPT_LOG}
    echo "${MIGLOG_SCRIPTNAME}:${FUNCNAME[1]}[${BASH_LINENO[0]}] ${MIGLOG_MSG}" |& tee -a ${MIGSCRIPT_LOG}

    logFilePush
    rm -vf ${MIGSSTATE_DIR}/MIG_RESTORE_RASPB_BOOT_IS_RUNING
    exit $LINENO
}

# USE: execCmmd "COMMANDS" [logSuccess || logCommand]
function execCmmd {
    echo "" &>>${MIGSCRIPT_LOG}
    echo ">>> $1" &>>${MIGSCRIPT_LOG}
	eval "$1" &>${MIGCOMMAND_LOG} 
    
    if [[ 0 -eq $? ]]; then 
        [[ "$2" == "logSuccess" ]] && cat ${MIGCOMMAND_LOG} &>>${MIGSCRIPT_LOG} 
        [[ "$2" == "logCommand" ]] && logCommand ">>> $1" "${FUNCNAME[1]}" "${BASH_LINENO[0]}"
    else
		logCommand "Fail at exec: $1" "${FUNCNAME[1]}" "${BASH_LINENO[0]}"
		return 1
    fi

	return 0
}

function restoreRaspbianBoot {
    logEvent "INI"

    if [[ -f ${MIGSSTATE_DIR}/MIG_UXMIGOS_IN_BOOT_OK ]] || [[ -f ${UXMIGOS_INSTALLED_BOOT_FILE} ]]; then
        if [[ -f ${MIGBKP_RASPBIANBOOT} ]];then
            execCmmd "rm -vrf ${MIGBOOT_DIR}/*" logSuccess && \
            execCmmd "tar -xzvf ${MIGBKP_RASPBIANBOOT} -C /" logSuccess && \
            execCmmd "rm -vf ${MIGSSTATE_DIR}/MIG_INSTALL_UXMIGOS_SUCCESS" logSuccess && \
            execCmmd "rm -vf ${MIGSSTATE_DIR}/MIG_UXMIGOS_IN_BOOT_OK"  logSuccess && \
            logEvent "OK" "Restaured Raspbian Backup in boot partition" || \
            exitError "Can't restore Raspbian Backup in boot partition"
        else
            exitError "Missing Raspbian BackUp File: ${MIGBKP_RASPBIANBOOT}"
        fi
    fi

    logEvent "END"
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

function testRestoreRaspbBootRunning {
    sleep 0.$[ ( $RANDOM % 10 ) ]s

    if [[ -f ${MIGSSTATE_DIR}/MIG_RESTORE_RASPB_BOOT_IS_RUNING ]]
    then
        echo "[FAIL] Another Restore Raspbian Boot script is running"
        exit $LINENO
    fi
}

function mainRestoreRasbBoot {
    testIsRoot
    testRestoreRaspbBootRunning

    mkdir -vp ${MIGSSTATE_DIR} || \
    {
        echo "FAIL to exec 'mkdir -vp ${MIGSSTATE_DIR}'"
        exit $LINENO
    }

    touch ${MIGSSTATE_DIR}/MIG_RESTORE_RASPB_BOOT_IS_RUNING

    echo "" &>>${MIGSCRIPT_LOG}
    echo "" &>>${MIGSCRIPT_LOG}
    echo "[ ####    RESTORE RASPB BOOT INI    #### ]" |& tee -a ${MIGSCRIPT_LOG}
    date |& tee -a ${MIGSCRIPT_LOG}
    rm -vf  ${MIGSSTATE_DIR}/MIG_RESTORE_RASPB_BOOT_FAIL &>>${MIGSCRIPT_LOG} || exitError
    rm -vf  ${MIGSSTATE_DIR}/MIG_RESTORE_RASPB_BOOT_SUCCESS &>>${MIGSCRIPT_LOG} || exitError
    logEvent "INI"

    restoreRaspbianBoot

    [[ -f ${UXMIGOS_RASPBIAN_BOOT_FILE} ]] && \
    logEvent "OK" "Validated Raspbian Backup in boot partition" || \
    logEvent "FAIL" "Missing validation Raspbian boot file: ${UXMIGOS_RASPBIAN_BOOT_FILE}"

    touch ${MIGSSTATE_DIR}/MIG_RESTORE_RASPB_BOOT_SUCCESS

    logEvent "SUCCESS" "TOTAL TIME: $(( $(cat /proc/uptime | grep -o '^[0-9]\+') - ${MIGTIME_INI} )) seconds"

    echo "" &>>${MIGSCRIPT_LOG}
    date | tee -a ${MIGSCRIPT_LOG}
    echo "[ ####    RESTORE RASPB BOOT SUCCESS    #### ]" |& tee -a ${MIGSCRIPT_LOG}
    
    logFilePush
    rm -vf ${MIGSSTATE_DIR}/MIG_RESTORE_RASPB_BOOT_IS_RUNING
}

mainRestoreRasbBoot

echo $LINENO
exit 0




# # wget -O - 'http://10.0.0.229/balenaos/scripts/migRestoreRaspBoot.sh' | bash
# # wget -O - 'http://10.0.0.229/balenaos/scripts/migRestoreRaspBoot.sh' | sudo bash
# # wget http://10.0.0.229/balenaos/scripts/migRestoreRaspBoot.sh

# MIGSSTATEDIR_BOOT="/boot/migstate"
# MIGSSTATEDIR_ROOT="/root/migstate"
# MIGSSTATEDIR_TEMP="/tmp/migstate"
# MIGSSTATE_DIR="${MIGSSTATEDIR_ROOT}"
# MIGCOMMAND_LOG="${MIGSSTATE_DIR}/cmdrestorerastboot.log"
# MIGSCRIPT_LOG="${MIGSSTATE_DIR}/migrestorerastboot.log"
# MIGBKP_RASPBIANBOOT="migboot-backup-raspbian.tgz"

# MIGBOOT_DEVICE='/dev/mmcblk0p1'
# MIGBOOT_MOUNTDIR='/mnt/boot'
# MIGROOTFS_DEVICE='/dev/mmcblk0p2'
# MIGROOTFS_MOUNTDIR='/mnt/rootfs'

# # En caso de error, envia log del comando a la web
# function logCommand {
#     echo "UXMIGOS | ${BASH_SOURCE[1]##*/} | ${FUNCNAME[1]} | ${BASH_LINENO[0]} | $(cat /proc/uptime | awk '{print $1}') | INI | CMDLOG " |& tee -a ${MIGSCRIPT_LOG} /dev/kmsg

#     if [[ -f ${MIGSSTATE_DIR}/UXMIGOS_NETWORK_OK ]]; then
#         echo '{"device":"'"${MIGDID}"'", '\
#         '"script":"migRestoreRaspBoot.sh", '\
#         '"function":"'"${FUNCNAME[1]}"'", '\
#         '"line":"'"${BASH_LINENO[0]}"'", '\
#         '"uptime":"'"$(cat /proc/uptime | awk '{print $1}')"'", '\
#         '"state":"'"CMDLOG"'", '\
#         '"msg":"' | \
#         cat - ${MIGCOMMAND_LOG} > temp.log && \
#         mv temp.log ${MIGCOMMAND_LOG} && \
#         echo '"}' >>${MIGCOMMAND_LOG} && \
#         cat ${MIGCOMMAND_LOG} &>>${MIGSCRIPT_LOG} && \
#         curl -X POST \
#         -d "@${MIGCOMMAND_LOG}" \
#         "${MIGWEBLOG_URL}/${MIGWEBLOG_KEYCOMMAND}" &>>${MIGSCRIPT_LOG} || \
#         echo "UXMIGOS | ${BASH_SOURCE[1]##*/} | ${FUNCNAME[1]} | ${BASH_LINENO[0]} | $(cat /proc/uptime | awk '{print $1}') | FAIL | Can not send CMDLOG, curl fail" |& tee -a ${MIGSCRIPT_LOG} /dev/kmsg
#     else
#         echo "UXMIGOS | ${BASH_SOURCE[1]##*/} | ${FUNCNAME[1]} | ${BASH_LINENO[0]} | $(cat /proc/uptime | awk '{print $1}') | FAIL | Can not send CMDLOG, No network" |& tee -a ${MIGSCRIPT_LOG} /dev/kmsg
#     fi

#     echo "UXMIGOS | ${BASH_SOURCE[1]##*/} | ${FUNCNAME[1]} | ${BASH_LINENO[0]} | $(cat /proc/uptime | awk '{print $1}') | END | CMDLOG " |& tee -a ${MIGSCRIPT_LOG} /dev/kmsg

#     return 0
# }

# # Guarda log de evento en el archivo de log, lo muestra por kmsg y lo envia a la web
# function logEvent {
#     if [[ -f ${MIGSSTATE_DIR}/UXMIGOS_NETWORK_OK ]]; then
#         >${MIGCOMMAND_LOG}
#         echo '{"device":"'"${MIGDID}"'", '\
#         '"script":"migRestoreRaspBoot.sh", '\
#         '"function":"'"${FUNCNAME[1]}"'", '\
#         '"line":"'"${BASH_LINENO[0]}"'", '\
#         '"uptime":"'"$(cat /proc/uptime | awk '{print $1}')"'", '\
#         '"state":"'"${MIGLOG_STATE}"'", '\
#         '"msg":"'"$1"'"}' | \
#         tee -a ${MIGSCRIPT_LOG} /dev/kmsg /dev/tty | \
#         curl -i -H "Accept: application/json" \
#         -X POST \
#         --data @- \
#         "${MIGWEBLOG_URL}/${MIGWEBLOG_KEYEVENT}" &>>${MIGCOMMAND_LOG} || logCommand
#     else
#         echo "UXMIGOS | ${BASH_SOURCE[1]##*/} | ${FUNCNAME[1]} | ${BASH_LINENO[0]} | $(cat /proc/uptime | awk '{print $1}') | ${MIGLOG_STATE} | $1" |& tee -a ${MIGSCRIPT_LOG} /dev/kmsg
#     fi

#     return 0
# }

# function exitError {
#     MIGLOG_STATE="EXIT"
#     logEvent "${BASH_SOURCE[1]##*/}:${FUNCNAME[1]}[${BASH_LINENO[0]}]"

#     touch ${MIGSSTATE_DIR}/MIG_RESTORE_RASPBIAN_BOOT_FAIL
#     #TODO: sent logfile to transfer.sh
#     exit 1
# }

# function restoreRaspianBoot {
# 	MIGLOG_STATE="INI"
#     logEvent

#     MIGLOG_STATE="INFO"

#     umount -v ${MIGBOOT_DEVICE} &>>${MIGSCRIPT_LOG}
#     mkdir -vp ${MIGBOOT_MOUNTDIR} &>>${MIGSCRIPT_LOG} || exitError

#     rm -vrf ${MIGSSTATEDIR_TEMP} &>>${MIGSCRIPT_LOG} || exitError

#     logEvent "mount"
#     mount -v ${MIGBOOT_DEVICE} ${MIGBOOT_MOUNTDIR} &>>${MIGSCRIPT_LOG} || exitError
#     logEvent "migstate boot backup"
#     cp -rv ${MIGBOOT_MOUNTDIR}/migstate /tmp &>>${MIGSCRIPT_LOG} || exitError 
#     logEvent "rm all"
#     rm -rf ${MIGBOOT_MOUNTDIR}/* &>>${MIGSCRIPT_LOG} || exitError
#     logEvent "tar -x"
#     tar -xzvf /root/${MIGBKP_RASPBIANBOOT} -C /mnt &>>${MIGSCRIPT_LOG} || exitError
#     logEvent "cp migstate"
#     cp -rv ${MIGSSTATEDIR_TEMP} ${MIGBOOT_MOUNTDIR} &>>${MIGSCRIPT_LOG} || exitError
#     logEvent "Success Restore RaspbianBoot"

#     MIGLOG_STATE="END"
#     logEvent
# }

# function mainRestoreRaspBoot {
#     MIGLOG_STATE="INI"
#     logEvent

#     rm -vf ${MIGSSTATE_DIR}/MIG_RESTORE_RASPBIAN_BOOT_FAIL &>>${MIGSCRIPT_LOG}

#     if [[ ! -f /root/${MIGBKP_RASPBIANBOOT} ]] ; then
#         MIGLOG_STATE="FAIL"
#         logEvent "Missing /root/${MIGBKP_RASPBIANBOOT}"
#         exitError
#     fi

#     if [[ -f ${MIGSSTATE_DIR}/MIG_FSM_SFDISK_OK ]]; then
#         MIGLOG_STATE="FAIL"
#         logEvent "The Partition table was altered"
#         exitError
#     fi

#     restoreRaspianBoot

#     MIGLOG_STATE="END"
#     logEvent
# }

# mainRestoreRaspBoot
# exit 0