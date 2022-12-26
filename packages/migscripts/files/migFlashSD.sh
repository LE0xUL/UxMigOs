#!/bin/bash

MIGLOG_SCRIPTNAME=$(basename "$0")
MIGSSTATE_DIR="/root/migstate"
MIGCOMMAND_LOG="/root/migstate/cmdFlashSD.log"
MIGSCRIPT_LOG="/root/migstate/migFlashSD.log"

# Use to log if any cmd fail
# USE: cmdFail MESSAGE
# USE: cmdFail MESSAGE logCommand <to run logCommand too>
function cmdFail {
    MIGLOG_MSG="${1:-CMDFAIL}"

    [[ -d ${MIGSSTATE_DIR} ]] && touch ${MIGSSTATE_DIR}/MIG_FLASH_SD_ERROR

    [[ "logCommand" == "$2" ]] && logCommand "${MIGLOG_MSG}" "${FUNCNAME[1]}" "${BASH_LINENO[0]}"

    logEvent "EXIT" "${MIGLOG_MSG}" "${FUNCNAME[1]}" "${BASH_LINENO[0]}" || \
    echo "UXMIGOS | ${MIGLOG_SCRIPTNAME} | ${FUNCNAME[1]} | ${BASH_LINENO[0]} | $(cat /proc/uptime | awk '{print $1}') | EXIT | ${MIGLOG_MSG}" | tee /dev/kmsg &>>${MIGSCRIPT_LOG}

    echo "" &>>${MIGSCRIPT_LOG}
    echo ">>>>>>>>    UXMIGOS FAIL FLASH SD    <<<<<<<<" | tee /dev/kmsg &>>${MIGSCRIPT_LOG}
    date &>>${MIGSCRIPT_LOG}
    echo "\n" &>>${MIGSCRIPT_LOG}
    logFilePush
    exit 1
}

##############################
#            MAIN            #
##############################

echo "" &>> ${MIGSCRIPT_LOG}
echo "" &>> ${MIGSCRIPT_LOG}
echo "########    UXMIGOS INI FLASH SD    ########" | tee /dev/kmsg &>>${MIGSCRIPT_LOG}
date &>> ${MIGSCRIPT_LOG}
echo "" &>> ${MIGSCRIPT_LOG}

[[ -f ${MIGSSTATE_DIR}/MIG_FLASH_SD_ERROR ]] && rm -v ${MIGSSTATE_DIR}/MIG_FLASH_SD_ERROR &>>${MIGSCRIPT_LOG}
[[ -f ${MIGSSTATE_DIR}/MIG_FLASH_SD_SUCCESS ]] && rm -v ${MIGSSTATE_DIR}/MIG_FLASH_SD_SUCCESS &>>${MIGSCRIPT_LOG}

source /root/migstate/mig.config || cmdFail "Fail source mig.config"
source /usr/bin/migFunctions.sh || cmdFail "Fail source migFunctions.sh"

logEvent "INI"

MIGFSM_STATE=''

while [[ ! -f ${MIGSSTATE_DIR}/MIG_FSM_SUCCESS ]]; do
    updateStateFSM || cmdFail "ERROR"
    migrationFSM || cmdFail "ERROR"
    updateBootMigState || cmdFail "ERROR"
done

touch ${MIGSSTATE_DIR}/MIG_FLASH_SD_SUCCESS

logEvent "SUCCESS" "BALENA MIGRATION SUCCESS"

echo "" &>>${MIGSCRIPT_LOG}
date &>>${MIGSCRIPT_LOG}
echo "========    UXMIGOS SUCCESS FLASH SD    ========" | tee /dev/kmsg &>>${MIGSCRIPT_LOG}
echo -e "\n\n" &>>${MIGSCRIPT_LOG}
logFilePush
exit 0
