#!/bin/bash

upSeconds="$(cat /proc/uptime | grep -o '^[0-9]\+')"
upMins=$((${upSeconds} / 60))
MIGLOG_SCRIPTNAME=$(basename "$0")

MIGSSTATE_DIR="/root/migstate"

MIGCOMMAND_LOG="${MIGSSTATE_DIR}/cmdwatch.log"
MIGSCRIPT_LOG="${MIGSSTATE_DIR}/migwatch.log"


function cmdFail {
    if [[ -f ${MIGSCRIPT_LOG} ]]; then
        logEvent "EXIT" "${MIGLOG_MSG}" "${FUNCNAME[1]}" "${BASH_LINENO[0]}" || \
        echo "UXMIGOS | ${MIGLOG_SCRIPTNAME} | ${FUNCNAME[1]} | ${BASH_LINENO[0]} | $(cat /proc/uptime | awk '{print $1}') | EXIT | ${MIGLOG_MSG}" | tee /dev/kmsg &>>${MIGSCRIPT_LOG}

        echo "" &>>${MIGSCRIPT_LOG}
        echo ">>>>>>>>    UXMIGOS FAIL SUPERVISOR    <<<<<<<<" | tee /dev/kmsg &>>${MIGSCRIPT_LOG}
        date &>>${MIGSCRIPT_LOG}
        echo "\n" &>>${MIGSCRIPT_LOG}
    else
        echo "UXMIGOS | ${MIGLOG_SCRIPTNAME} | ${FUNCNAME[1]} | ${BASH_LINENO[0]} | $(cat /proc/uptime | awk '{print $1}') | EXIT | ${MIGLOG_MSG}" | tee /dev/kmsg
    fi

    restoreBackupBoot
    
    logFilePush
    exit 1
}

##############################
#            MAIN            #
##############################

mkdir -vp ${MIGSSTATE_DIR} || \
{
    echo "UXMIGOS | ${MIGLOG_SCRIPTNAME} | ${FUNCNAME[1]} | ${BASH_LINENO[0]} | $(cat /proc/uptime | awk '{print $1}') | FAIL | ERROR to exec 'mkdir -vp ${MIGSSTATE_DIR}'" | \
    tee /dev/kmsg
}

# Wait to system init and network connect
sleep 30

echo "" &>> ${MIGSCRIPT_LOG}
echo "" &>> ${MIGSCRIPT_LOG}
echo "########    UXMIGOS INI SUPERVISOR    ########" | tee /dev/kmsg &>>${MIGSCRIPT_LOG}
date &>> ${MIGSCRIPT_LOG}
echo "" &>> ${MIGSCRIPT_LOG}

if [[ ! -f /root/migstate/mig.config ]]; then
    source /usr/bin/migFunctions.sh || cmdFail "Fail source migFunctions.sh"
    checkInit || cmdFail
fi

source /root/migstate/mig.config || cmdFail "Fail source mig.config"
source /usr/bin/migFunctions.sh || cmdFail "Fail source migFunctions.sh"

testBucketConnection

checkInit || cmdFail
checkRamdisk || cmdFail

if [[ ! -f ${MIGSSTATE_DIR}/UXMIGOS_NETWORK_OK ]]; then
    restoreNetworkConfig || cmdFail
    checkConfigWPA || cmdFail
    testBucketConnection || cmdFail "Fail Network Connection"
fi

checkDataFS || cmdFail
downloadBucketFilesInRamdisk || cmdFail
# checkDownFilesInRamdisk || cmdFail

migFlashSD.sh || cmdFail

echo "" &>>${MIGSCRIPT_LOG}
date &>>${MIGSCRIPT_LOG}
echo "========    UXMIGOS SUCCESS SUPERVISOR    ========" | tee /dev/kmsg &>>${MIGSCRIPT_LOG}
echo -e "\n\n" &>>${MIGSCRIPT_LOG}
logFilePush

# shutdown -r now
reboot