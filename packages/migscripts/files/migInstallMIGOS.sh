#!/bin/bash

# wget -O - 'http://10.0.0.21/balenaos/migscripts/migInstallMIGOS.sh' | bash
# curl -s 'http://10.0.0.21/balenaos/migscripts/migInstallMIGOS.sh' | bash
# wget -O - 'https://storage.googleapis.com/balenamigration/migscripts/migInstallMIGOS.sh?ignoreCache=1' | bash
# curl 'https://storage.googleapis.com/balenamigration/migscripts/migInstallMIGOS.sh?ignoreCache=1' --output migInstallMIGOS.sh

MIGTIME_INI="$(cat /proc/uptime | grep -o '^[0-9]\+')"
MIGDID="$(hostname)"

[[ 0 -ne $? ]] && { echo "[FAIL] Can't set MIGDID"; exit $LINENO; }

MIGLOG_SCRIPTNAME="migInstallMIGOS.sh"
MIGSSTATEDIR_BOOT="/boot/migstate"
MIGSSTATEDIR_ROOT="/root/migstate"
MIGSSTATE_DIR="${MIGSSTATEDIR_ROOT}"
MIGDOWN_DIR="/root/migdownloads"

MIGCOMMAND_LOG="${MIGSSTATE_DIR}/cmd.log"
MIGSCRIPT_LOG="${MIGSSTATE_DIR}/migInstallMIGOS.log"
# MIGSCRIPT_STATE='STATE'
MIGCONFIG_FILE="${MIGSSTATE_DIR}/mig.config"
## Device ID
MIGMMC="/dev/mmcblk0"
MIGBOOT_DEV='/dev/mmcblk0p1'
MIGBOOT_DIR='/boot'
MIGBKP_RASPBIANBOOT="/root/migboot-backup-raspbian.tgz"

# TODO: MIGOS_VERSION="$(git describe)"
# TODO: MIGOS_BALENA_FILENAME="migboot-migos-balena_${MIGOS_VERSION}.tgz"
MIGOS_BALENA_FILENAME="migboot-migos-balena.tgz"
MIGOS_RASPBIAN_BOOT_FILE="/boot/MIGOS_RASPBIAN_BOOT_${MIGDID}"
MIGOS_INSTALLED_BOOT_FILE="/boot/MIGOS_BOOT_INSTALLED"

MIGWEBLOG_URL='https://eu.webhook.logs.insight.rapid7.com/v1/noformat'
MIGWEBLOG_KEYEVENT='f79248d1-bbe0-427b-934b-02a2dee5f24f'
MIGWEBLOG_KEYCOMMAND='642de669-cf83-4e19-a6bf-9548eb7f5210'

MIGBUCKET_URL='http://10.0.0.21/balenaos'
# MIGBUCKET_URL='https://storage.googleapis.com/balenamigration'
MIGBUCKET_FILETEST='test.file'

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

function logFilePush {
    MIGLOG_FILEPUSH_URLLOG=$(curl --upload-file "${MIGSCRIPT_LOG}" https://filepush.co/upload/)
    logEvent "INFO" "${MIGLOG_FILEPUSH_URLLOG}"
    echo "${MIGLOG_FILEPUSH_URLLOG}"
}

function restoreRaspbianBoot {
    logEvent "INI"

    if [[ -f ${MIGSSTATE_DIR}/MIG_MIGOS_IN_BOOT_OK ]] || [[ -f ${MIGOS_INSTALLED_BOOT_FILE} ]]; then
        if [[ -f ${MIGBKP_RASPBIANBOOT} ]];then
            execCmmd "rm -vrf ${MIGBOOT_DIR}/*" logSuccess && \
            execCmmd "tar -xzvf ${MIGBKP_RASPBIANBOOT} -C /" logSuccess && \
            execCmmd "rm -vf ${MIGSSTATE_DIR}/MIG_INSTALL_MIGOS_SUCCESS" logSuccess && \
            execCmmd "rm -vf ${MIGSSTATE_DIR}/MIG_MIGOS_IN_BOOT_OK"  logSuccess && \
            logEvent "OK" "Restaured Raspbian Backup in boot partition" || \
            logEvent "FAIL" "Can't restore Raspbian Backup in boot partition"
        else
            logEvent "FAIL" "Missing Raspbian BackUp File: ${MIGBKP_RASPBIANBOOT}"
        fi
    fi

    logEvent "END"
}

# USE: exitError MESSAGE
function exitError {
    touch ${MIGSSTATE_DIR}/MIG_INSTALL_MIGOS_FAIL
    MIGEXIT_LOGMSG="${1:-INSTALL_MIGOS_FAIL}"
    MIGEXIT_PARAM2=$2
    MIGEXIT_PARAM3=$3

    [[ "logCommand" == "${MIGEXIT_PARAM2}" ]] && logCommand "${MIGEXIT_LOGMSG}" "${FUNCNAME[1]}" "${BASH_LINENO[0]}"
    [[ "restoreRaspbianBoot" == "${MIGEXIT_PARAM2}" ]] && restoreRaspbianBoot
    [[ "restoreRaspbianBoot" == "${MIGEXIT_PARAM3}" ]] && restoreRaspbianBoot


    logEvent "EXIT" "${MIGEXIT_LOGMSG}" "${FUNCNAME[1]}" "${BASH_LINENO[0]}"
    
    echo "" &>>${MIGSCRIPT_LOG}
    date |& tee -a ${MIGSCRIPT_LOG}
    echo "[ ####    INSTALL MIGOS FAIL    #### ]" |& tee -a ${MIGSCRIPT_LOG}
    echo "" &>>${MIGSCRIPT_LOG}
    echo "${MIGLOG_SCRIPTNAME}:${FUNCNAME[1]}[${BASH_LINENO[0]}] ${MIGEXIT_LOGMSG}" |& tee -a ${MIGSCRIPT_LOG}

    logFilePush
    rm -vf ${MIGSSTATE_DIR}/MIG_INSTALL_MIGOS_IS_RUNING
    exit $LINENO
}

function backupBootPartition {
    logEvent "INI"

    [[ -f ${MIGOS_RASPBIAN_BOOT_FILE} ]] && \
    logEvent "OK" "Validated Raspbian boot partition" || \
    exitError "Missing validation Raspbian boot file: ${MIGOS_RASPBIAN_BOOT_FILE}"

    if [[ -f ${MIGBKP_RASPBIANBOOT} ]]; then
        logEvent "INFO" "Raspbian boot backup file was detected in the system: ${MIGBKP_RASPBIANBOOT}"
    else
        execCmmd "tar -czvf ${MIGBKP_RASPBIANBOOT} ${MIGBOOT_DIR}" logSuccess && \
        logEvent "OK" "Created boot backup file: ${MIGBKP_RASPBIANBOOT}" || \
        exitError "FAIL at make raspbian boot backup file: ${MIGBKP_RASPBIANBOOT}"
    fi
    
    logEvent "END"
}

function migos2Boot {
    logEvent "INI"

    execCmmd "rm -vfr ${MIGBOOT_DIR}/*" logSuccess || \
    exitError "Fail at exec: rm -vfr ${MIGBOOT_DIR}/*" restoreRaspbianBoot

    execCmmd "tar -xzvf ${MIGDOWN_DIR}/${MIGOS_BALENA_FILENAME} -C ${MIGBOOT_DIR}" logSuccess || \
    exitError "tar -xzvf ${MIGDOWN_DIR}/${MIGOS_BALENA_FILENAME} -C ${MIGBOOT_DIR}" restoreRaspbianBoot

    execCmmd "touch ${MIGSSTATE_DIR}/MIG_MIGOS_IN_BOOT_OK" logSuccess || \
    exitError "touch ${MIGSSTATE_DIR}/MIG_MIGOS_IN_BOOT_OK" restoreRaspbianBoot
    
    logEvent "OK" "Installed MIGOS in boot partition"
    
    execCmmd "ls -alh ${MIGBOOT_DIR}" logCommand

    logEvent "END"
}

# USE: migDownFile URL FILENAME DESTINATION
function migDownFile {
    MIGDOWN_URL=$1
    MIGDOWN_FILENAME=$2
    MIGDOWN_DIRECTORY=$3
    MIGDOWN_ATTEMPTNUM=0
    MIGDOWN_ATTEMPTMAX=2

    logEvent "INFO" "Try to wget ${MIGDOWN_FILENAME}"
    
    until $(wget "${MIGDOWN_URL}/${MIGDOWN_FILENAME}" -O ${MIGDOWN_DIRECTORY}/${MIGDOWN_FILENAME} &>${MIGCOMMAND_LOG}); do
        if [ ${MIGDOWN_ATTEMPTNUM} -eq ${MIGDOWN_ATTEMPTMAX} ];then
            logEvent "ERROR" "Can't download ${MIGDOWN_FILENAME}"
            return 1
        fi

        MIGDOWN_ATTEMPTNUM=$(($MIGDOWN_ATTEMPTNUM+1))
        logEvent "FAIL" "Download attempt ${MIGDOWN_ATTEMPTNUM}"
        sleep 10
    done
    
    logEvent "OK" "wget ${MIGDOWN_FILENAME}"
    return 0
}

function downFilesFromBucket {
    logEvent "INI"
    MIGMD5_ATTEMPTMAX=2

    MIG_FILE_BUCKET_LIST=(  \
        'appBalena.config.json' \
        'migboot-migos-balena.tgz' \
        "resin-partitions-${MIGCONFIG_BOOTSIZE}.sfdisk" \
        "p1-resin-boot-${MIGCONFIG_BOOTSIZE}.img.gz" \
        'p2-resin-rootA.img.gz' \
        'p3-resin-rootB.img.gz' \
        'p5-resin-state.img.gz' \
        'p6-resin-data.img.gz' \
    )

    execCmmd "mkdir -vp ${MIGDOWN_DIR}" logSuccess || \
    exitError "Fail at exec 'mkdir -vp ${MIGDOWN_DIR}'"

    for fileName in ${MIG_FILE_BUCKET_LIST[@]}
    do
        MIGMD5_ATTEMPTNUM=0
        MIGMD5_CHECK_OK=false

        while ! $MIGMD5_CHECK_OK
        do
            MIGMD5_ATTEMPTNUM=$(($MIGMD5_ATTEMPTNUM+1))
            
            if [[ ! -f ${MIGDOWN_DIR}/${fileName} ]]; then
                migDownFile ${MIGBUCKET_URL} ${fileName} ${MIGDOWN_DIR} || \
                exitError "Can't download ${fileName}" logCommand
            else
                logEvent "INFO" "Found ${fileName} in ${MIGDOWN_DIR}";
            fi

            migDownFile ${MIGBUCKET_URL} ${fileName}.md5 ${MIGDOWN_DIR} || \
            exitError "Can't download ${fileName}.md5" logCommand

            cd ${MIGDOWN_DIR} &>>${MIGSCRIPT_LOG} && \
            md5sum --check ${fileName}.md5 &>>${MIGSCRIPT_LOG}

            if [[ $? -eq 0 ]]; then
                MIGMD5_CHECK_OK=true
                logEvent "OK" "Success MD5 check of ${fileName}"
            elif [[ ${MIGMD5_ATTEMPTNUM} -lt ${MIGMD5_ATTEMPTMAX} ]]; then
                logEvent "FAIL" "Fail MD5 check of ${MIGDOWN_DIR}/${fileName} attempt ${MIGMD5_ATTEMPTNUM}"
                rm -vf ${MIGDOWN_DIR}/${fileName} &>>${MIGSCRIPT_LOG}
                rm -vf ${MIGDOWN_DIR}/${fileName}.md5 &>>${MIGSCRIPT_LOG}
            else
                rm -vf ${MIGDOWN_DIR}/${fileName} &>>${MIGSCRIPT_LOG}
                rm -vf ${MIGDOWN_DIR}/${fileName}.md5 &>>${MIGSCRIPT_LOG}
                exitError "Fail MD5 check of ${MIGDOWN_DIR}/${fileName} attempt ${MIGMD5_ATTEMPTNUM}"
            fi
        done

        # logEvent "OK" "Success download of ${fileName}"
    done

    logEvent "END"
}

function migState2Boot {
    logEvent "INI"

    execCmmd "rm -vfr ${MIGSSTATEDIR_BOOT}" logSuccess || \
    exitError "Can't clean ${MIGSSTATEDIR_BOOT}"

    execCmmd "cp -rv ${MIGSSTATE_DIR} ${MIGBOOT_DIR}" logSuccess && \
    logEvent "OK" "Copyed migState in boot partition" || \
    exitError "Can't copy migstate 2 Boot"

    execCmmd "ls -alh ${MIGBOOT_DIR}/migstate" logCommand

    logEvent "END"
}

function validateDiagnostic {
    logEvent "INI"

    MIGTIMESTAMP_DIAGNOSTICSUCCESS=$(stat -c %Y ${MIGSSTATE_DIR}/MIG_DIAGNOSTIC_SUCCESS |& tee ${MIGCOMMAND_LOG})
    [[ 0 -ne $? ]] && exitError "Fail at exec 'stat -c %Y ${MIGSSTATE_DIR}/MIG_DIAGNOSTIC_SUCCESS'" logCommand
    echo "MIGTIMESTAMP_DIAGNOSTICSUCCESS: ${MIGTIMESTAMP_DIAGNOSTICSUCCESS}" &>>${MIGSCRIPT_LOG}

    MIGTIMESTAMP_SYSTEMNOW=$(date "+%s" |& tee ${MIGCOMMAND_LOG})
    [[ 0 -ne $? ]] && exitError "Fail at exec 'date +%s'" logCommand
    echo "MIGTIMESTAMP_SYSTEMNOW: ${MIGTIMESTAMP_SYSTEMNOW}" &>>${MIGSCRIPT_LOG}

    MIGTIMESTAMP_DIFFERENCE=$((MIGTIMESTAMP_SYSTEMNOW - MIGTIMESTAMP_DIAGNOSTICSUCCESS))
    echo "MIGTIMESTAMP_DIFFERENCE: ${MIGTIMESTAMP_DIFFERENCE}" &>>${MIGSCRIPT_LOG}

    [[ ${MIGTIMESTAMP_DIFFERENCE} -lt 0 ]] && \
    exitError "Futuristic MIG_DIAGNOSTIC_SUCCESS timestamp [${MIGTIMESTAMP_DIFFERENCE}]"

    [[ ${MIGTIMESTAMP_DIFFERENCE} -gt 600 ]] && \
    exitError "'Diagnostic' is too old. Please, run it again."

    logEvent "OK" "Valid MIG_DIAGNOSTIC_SUCCESS"
    logEvent "END"
}

function testMigState {
    logEvent "INI"
    
    if [[ ! -f ${MIGSSTATE_DIR}/MIG_DIAGNOSTIC_SUCCESS ]]; then
        exitError "[FAIL] Is necessary run first the Diagnostic script with success result."
    elif [[ -f ${MIGSSTATE_DIR}/MIG_INSTALL_MIGOS_SUCCESS ]] && [[ -f ${MIGOS_INSTALLED_BOOT_FILE} ]]; then
        exitError "MIGOS is already installed in the system. Reboot the system to initiate the migration process"
    elif [[ -f ${MIGOS_INSTALLED_BOOT_FILE} ]]; then
        exitError "[FAIL] MIGOS_BOOT is present in the system"
    elif [[ -f ${MIGSSTATE_DIR}/MIG_INSTALL_MIGOS_SUCCESS ]]; then
        exitError "[FAIL] INSTALL MIGOS was SUCCESS but MIGOS_BOOT is not present in the system"
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

function testInstallMigosRunning {
    sleep 0.$[ ( $RANDOM % 10 ) ]s
    
    if [[ -f ${MIGSSTATE_DIR}/MIG_INSTALL_MIGOS_IS_RUNING ]]
    then
        echo "[FAIL] Another Install MIGOS script is running"
        exit $LINENO
    fi
}

function iniMigosInstall {
    testIsRoot
    testBucketConnection
    testInstallMigosRunning

    mkdir -vp ${MIGSSTATE_DIR}
    touch ${MIGSSTATE_DIR}/MIG_INSTALL_MIGOS_IS_RUNING

    echo "" &>>${MIGSCRIPT_LOG}
    echo "" &>>${MIGSCRIPT_LOG}
    echo "[ ####    INSTALL MIGOS INI    #### ]" |& tee -a ${MIGSCRIPT_LOG}
    date |& tee -a ${MIGSCRIPT_LOG}
    logEvent "INI"

    rm -vf  ${MIGSSTATE_DIR}/MIG_INSTALL_MIGOS_FAIL &>>${MIGSCRIPT_LOG} || exitError

    testMigState
    validateDiagnostic
    backupBootPartition

    source ${MIGCONFIG_FILE} &>${MIGCOMMAND_LOG} || \
    exitError "FAIL at exec: source ${MIGCONFIG_FILE}" logCommand

    downFilesFromBucket
    migos2Boot
    migState2Boot

    touch ${MIGSSTATE_DIR}/MIG_INSTALL_MIGOS_SUCCESS

    logEvent "SUCCESS" "TOTAL TIME: $(( $(cat /proc/uptime | grep -o '^[0-9]\+') - ${MIGTIME_INI} )) seconds"

    echo "" &>>${MIGSCRIPT_LOG}
    date | tee -a ${MIGSCRIPT_LOG}
    echo "[ ####    INSTALL MIGOS SUCCESS    #### ]" |& tee -a ${MIGSCRIPT_LOG}
    
    cp ${MIGSCRIPT_LOG} ${MIGBOOT_DIR} |& tee -a ${MIGSCRIPT_LOG}
    logFilePush
    rm -vf ${MIGSSTATE_DIR}/MIG_INSTALL_MIGOS_IS_RUNING
    echo "reboot"
    # shutdown -r now
    # shutdown -r +1
}

iniMigosInstall

echo $LINENO
exit 0