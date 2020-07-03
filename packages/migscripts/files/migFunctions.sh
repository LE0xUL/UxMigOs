#!/bin/bash

MIGSSTATE_DIR="/root/migstate"
MIGSSTATE_BOOTDIR="/mnt/boot/migstate"

MIGMMC="/dev/mmcblk0"
MIGBOOT_MOUNTDIR='/mnt/boot'
MIGBOOT_DEVICE='/dev/mmcblk0p1'
MIGROOTFS_DEVICE='/dev/mmcblk0p2'
MIGROOTFS_MOUNTDIR='/mnt/rootfs'
MIG_RAMDISK='/mnt/migramdisk'
MIGDOWNLOADS_DIR="${MIGROOTFS_MOUNTDIR}/root/migdownloads"

# MIGBUCKET_URL='http://10.0.0.21/balenaos'
MIGBUCKET_URL='https://storage.googleapis.com/balenamigration'
MIGBUCKET_FILETEST='test.file'
MIGBUCKET_ATTEMPTNUM=0
MIGBUCKET_ATTEMPTMAX=5

MIGWEBLOG_URL='https://eu.webhook.logs.insight.rapid7.com/v1/noformat'
MIGWEBLOG_KEYEVENT='f79248d1-bbe0-427b-934b-02a2dee5f24f'
MIGWEBLOG_KEYCOMMAND='642de669-cf83-4e19-a6bf-9548eb7f5210'

MIGBKP_RASPBIANBOOT="migboot-backup-raspbian.tgz"
MIGBKP_MIGSTATE_TMP="/tmp/migos_migstate_boot.tgz"

MIGCONFIG_FILE="mig.config"

MIG_FILE_RESIN_SFDISK="resin-partitions-${MIGCONFIG_BOOTSIZE}.sfdisk"
MIG_FILE_RESIN_ROOTA='p2-resin-rootA.img.gz'
MIG_FILE_RESIN_ROOTB='p3-resin-rootB.img.gz'
MIG_FILE_RESIN_STATE='p5-resin-state.img.gz'
MIG_FILE_RESIN_DATA='p6-resin-data.img.gz'
MIG_FILE_RESIN_BOOT="p1-resin-boot-${MIGCONFIG_BOOTSIZE}.img.gz"
MIG_FILE_RESIN_CONFIG_JSON='appBalena.config.json'

MIG_FILE_LIST_BUCKET=( \
    ${MIG_FILE_RESIN_SFDISK} \
    ${MIG_FILE_RESIN_BOOT} \
    ${MIG_FILE_RESIN_ROOTA} \
    ${MIG_FILE_RESIN_ROOTB} \
    ${MIG_FILE_RESIN_STATE} \
    ${MIG_FILE_RESIN_DATA} \
    'config3G.txt' \
    'cmdline3G.txt' \
    'appBalena3G.config.json' \
    'appBalena.config.json' \
)


MIG_FILE_LIST_MIGSTATE_BOOT=( \
    ${MIGCONFIG_FILE} \
    resin-wlan \
    wpa_supplicant.conf.bkp \
    en.network \
    wlan0.network \
    MIG_FSM_SFDISK_OK \
    MIG_FSM_ROOTA_OK \
    MIG_FSM_ROOTB_OK \
    MIG_FSM_STATE_OK \
    MIG_FSM_DATA_OK \
    MIG_FSM_BOOT_OK \
    MIG_FSM_CONFIG_OK \
    MIG_FSM_SUCCESS \
)

# Se usa normalmente en caso de error, y guarda un registro del resultado del comando el en log del script y tambien lo envia la web
# USE: logCommand 
# USE: logCommand MESSAGE 
# USE: logCommand MESSAGE FUNCNAME
# USE: logCommand MESSAGE FUNCNAME BASH_LINENO
# (implicitly the file ${MIGCOMMAND_LOG} is sent)
function logCommand {
    # MIGLOG_STATE="CMDLOG"
    MIGLOG_CMDMSG="$1"
    MIGLOG_CMDFUNCNAME="${2:-${FUNCNAME[1]}}"
    MIGLOG_CMDLINENO="${3:-${BASH_LINENO[0]}}"
    MIGLOG_CMDUPTIME="$(cat /proc/uptime | awk '{print $1}')"
    MIGLOG_CMDLOG="\n vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv \n $(cat ${MIGCOMMAND_LOG}) \n ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ \n"

    if [[ -f ${MIGSSTATE_DIR}/MIGOS_NETWORK_OK ]]; then
        echo -e '{ "os":"MIGOS", '\
        '"device":"'"${MIGCONFIG_DID}"'", '\
        '"script":"'"${MIGLOG_SCRIPTNAME}"'", '\
        '"function":"'"${MIGLOG_CMDFUNCNAME}"'", '\
        '"line":"'"${MIGLOG_CMDLINENO}"'", '\
        '"uptime":"'"${MIGLOG_CMDUPTIME}"'", '\
        '"state":"'"CMDLOG"'", '\
        '"msg":"'"${MIGLOG_CMDMSG}"'", '\
        '"cmdlog":"'"${MIGLOG_CMDLOG}"'"}' |& \
        tee -a ${MIGSCRIPT_LOG} |& \
        curl -ki --data @- "${MIGWEBLOG_URL}/${MIGWEBLOG_KEYCOMMAND}" &>>${MIGSCRIPT_LOG} && \
        { echo "MIGOS | ${MIGLOG_SCRIPTNAME} | logCommand | $LINENO | $(cat /proc/uptime | awk '{print $1}') | OK | ${MIGLOG_CMDMSG}" | tee /dev/kmsg &>>${MIGSCRIPT_LOG}; } || \
        { echo "MIGOS | ${MIGLOG_SCRIPTNAME} | logCommand | $LINENO | $(cat /proc/uptime | awk '{print $1}') | FAIL | Can not send CMDLOG, curl fail" | tee /dev/kmsg &>>${MIGSCRIPT_LOG}; }
    else
        echo "MIGOS | ${MIGLOG_SCRIPTNAME} | ${FUNCNAME[1]} | ${BASH_LINENO[0]} | ${MIGLOG_CMDUPTIME} | CMDLOG | ${MIGLOG_CMDMSG}" | tee /dev/kmsg &>>${MIGSCRIPT_LOG}
        cat ${MIGCOMMAND_LOG} &>>${MIGSCRIPT_LOG}
        echo "MIGOS | ${MIGLOG_SCRIPTNAME} | ${FUNCNAME[1]} | ${BASH_LINENO[0]} | $(cat /proc/uptime | awk '{print $1}') | FAIL | Can not send CMDLOG, No network" | tee /dev/kmsg &>>${MIGSCRIPT_LOG}
    fi

    return 0
}

# Registra un evento en el archivo de log, lo muestra por kmsg y lo envia a la web (Si puede)
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

    if [[ -f ${MIGSSTATE_DIR}/MIGOS_NETWORK_OK ]]; then
        echo '{ "os":"MIGOS", '\
        '"device":"'"${MIGCONFIG_DID}"'", '\
        '"script":"'"${MIGLOG_SCRIPTNAME}"'", '\
        '"function":"'"${MIGLOG_FUNCNAME}"'", '\
        '"line":"'"${MIGLOG_LINENO}"'", '\
        '"uptime":"'"${MIGLOG_UPTIME}"'", '\
        '"state":"'"${MIGLOG_STATE}"'", '\
        '"msg":"'"${MIGLOG_MSG}"'"}' |& \
        tee -a ${MIGSCRIPT_LOG} /dev/kmsg |& \
        curl -kvi -H "Accept: application/json" \
        -X POST \
        --data @- \
        "${MIGWEBLOG_URL}/${MIGWEBLOG_KEYEVENT}" &>${MIGCOMMAND_LOG} || logCommand "Curl fail at send logEvent"
        # "${MIGWEBLOG_URL}/${MIGWEBLOG_KEYEVENT}" &>${MIGCOMMAND_LOG} >>${MIGSCRIPT_LOG} || logCommand "Curl fail at send logEvent"
    else
        echo "MIGOS | ${MIGLOG_SCRIPTNAME} | ${MIGLOG_FUNCNAME} | ${MIGLOG_LINENO} | ${MIGLOG_UPTIME} | ${MIGLOG_STATE} | ${MIGLOG_MSG}" | tee /dev/kmsg &>>${MIGSCRIPT_LOG}
    fi

    return 0
}

# USE: execCmmd "COMMANDS" [logSuccess || logCommand]
function execCmmd {
    echo "" &>>${MIGSCRIPT_LOG}
    echo "[${BASH_LINENO[0]}]>>> $1" &>>${MIGSCRIPT_LOG}
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
    if [[ -f ${MIGSSTATE_DIR}/MIGOS_NETWORK_OK ]]; then
        logEvent "INFO" "$(curl -k --upload-file ${MIGSCRIPT_LOG} https://filepush.co/upload/)" "${FUNCNAME[1]}" "${BASH_LINENO[0]}"
    else
        echo "MIGOS | ${MIGLOG_SCRIPTNAME} | ${FUNCNAME[1]} | ${BASH_LINENO[0]} | $(cat /proc/uptime | awk '{print $1}') | FAIL | Can't send logFilePush" | tee /dev/kmsg &>>${MIGSCRIPT_LOG}
    fi
    return 0
}

function testBucketConnection {
    logEvent "INI"

    [[ -f ${MIGSSTATE_DIR}/MIGOS_NETWORK_ERROR ]] && rm -fv ${MIGSSTATE_DIR}/MIGOS_NETWORK_ERROR &>>${MIGSCRIPT_LOG}
    [[ -f ${MIGSSTATE_DIR}/MIGOS_NETWORK_OK ]] && rm -fv ${MIGSSTATE_DIR}/MIGOS_NETWORK_OK &>>${MIGSCRIPT_LOG}

    execCmmd 'cat /etc/resolv.conf | grep "8.8.8.8" || echo "nameserver 8.8.8.8" >> /etc/resolv.conf' logCommand

	until $(execCmmd "wget -q --tries=10 --timeout=10 --spider ${MIGBUCKET_URL}/${MIGBUCKET_FILETEST}" logSuccess); do
		if [ ${MIGBUCKET_ATTEMPTNUM} -eq ${MIGBUCKET_ATTEMPTMAX} ];then
			logEvent "ERROR" "No Network Connection"
			touch ${MIGSSTATE_DIR}/MIGOS_NETWORK_ERROR
			return 1
	    fi

	    MIGBUCKET_ATTEMPTNUM=$(($MIGBUCKET_ATTEMPTNUM+1))
		logEvent "FAIL" "Network attempt ${MIGBUCKET_ATTEMPTNUM}"
	    sleep 10
	done
    
    touch ${MIGSSTATE_DIR}/MIGOS_NETWORK_OK
    logEvent "OK" "Network Connection"
    
    logEvent "END"
    return 0
}

# USE: migDownFile URL FILENAME DESTINATION
function migDownFile {
    MIGDOWN_URL=$1
    MIGDOWN_FILENAME=$2
    MIGDOWN_DIRECTORY=$3
    MIGDOWN_ATTEMPTNUM=0
    MIGDOWN_ATTEMPTMAX=2

    logEvent "INFO" "Try to wget ${MIGDOWN_FILENAME}"
    
    until $(execCmmd "wget ${MIGDOWN_URL}/${MIGDOWN_FILENAME} -O ${MIGDOWN_DIRECTORY}/${MIGDOWN_FILENAME}"); do
        if [ ${MIGDOWN_ATTEMPTNUM} -eq ${MIGDOWN_ATTEMPTMAX} ];then
            logEvent "ERROR" "Can't download ${MIGDOWN_FILENAME}"
            return 1
        fi

        MIGDOWN_ATTEMPTNUM=$(($MIGDOWN_ATTEMPTNUM+1))
        logEvent "FAIL" "Download attempt ${MIGDOWN_ATTEMPTNUM}"
        sleep 10
    done
    
    logEvent "OK" "Success wget ${MIGDOWN_FILENAME}"
    return 0
}

function downloadBucketFilesInRamdisk {
    logEvent "INI"
    MIGMD5_ATTEMPTMAX=2

    [[ -f ${MIGSSTATE_DIR}/MIG_RAMDISK_OK ]] || { logEvent "ERROR" "Missing ${MIGSSTATE_DIR}/MIG_RAMDISK_OK"; return 1; }
    [[ -d ${MIG_RAMDISK} ]] && cd ${MIG_RAMDISK} || { logEvent "ERROR" "Missing ${MIG_RAMDISK}"; return 1; }
    [[ -f ${MIGSSTATE_DIR}/MIGOS_NETWORK_OK ]] || { logEvent "ERROR" "No network connention"; return 1; }

    for FILENAME_TO_DOWN in ${MIG_FILE_LIST_BUCKET[@]}
    do
        MIGMD5_ATTEMPTNUM=0
        MIGMD5_CHECK_OK=false

        while ! $MIGMD5_CHECK_OK
        do
            MIGMD5_ATTEMPTNUM=$(($MIGMD5_ATTEMPTNUM+1))
            
            if [[ ! -f ${MIG_RAMDISK}/${FILENAME_TO_DOWN} ]]; then
                migDownFile ${MIGBUCKET_URL} ${FILENAME_TO_DOWN} ${MIG_RAMDISK} || \
                { logEvent "ERROR" "Can't download ${FILENAME_TO_DOWN}"; return 1; }
            else
                logEvent "INFO" "Found ${FILENAME_TO_DOWN} in ${MIG_RAMDISK}";
            fi

            migDownFile ${MIGBUCKET_URL} ${FILENAME_TO_DOWN}.md5 ${MIG_RAMDISK} || \
            { logEvent "ERROR" "Can't download ${FILENAME_TO_DOWN}.md5"; return 1; }

            cd ${MIG_RAMDISK} &>>${MIGSCRIPT_LOG} && \
            md5sum --check ${FILENAME_TO_DOWN}.md5 &>>${MIGSCRIPT_LOG}

            if [[ $? -eq 0 ]]; then
                MIGMD5_CHECK_OK=true
                logEvent "OK" "Success MD5 check of ${FILENAME_TO_DOWN}"
            elif [[ ${MIGMD5_ATTEMPTNUM} -lt ${MIGMD5_ATTEMPTMAX} ]]; then
                logEvent "FAIL" "Fail MD5 check of ${MIG_RAMDISK}/${FILENAME_TO_DOWN} attempt ${MIGMD5_ATTEMPTNUM}"
                execCmmd "rm -vf ${MIG_RAMDISK}/${FILENAME_TO_DOWN}" logSuccess
                execCmmd "rm -vf ${MIG_RAMDISK}/${FILENAME_TO_DOWN}.md5" logSuccess
            else
                logEvent "ERROR" "Fail MD5 check of ${MIG_RAMDISK}/${FILENAME_TO_DOWN} attempt ${MIGMD5_ATTEMPTNUM}"
                execCmmd "rm -vf ${MIG_RAMDISK}/${FILENAME_TO_DOWN}" logSuccess
                execCmmd "rm -vf ${MIG_RAMDISK}/${FILENAME_TO_DOWN}.md5" logSuccess
                return 1
            fi
        done

        logEvent "OK" "Success download of ${FILENAME_TO_DOWN}"
    done

    logEvent "END"
}

function checkDownFilesInRamdisk {
    logEvent "INI"

    [[ -f ${MIGSSTATE_DIR}/MIG_RAMDISK_OK ]] || { logEvent "ERROR" "Missing ${MIGSSTATE_DIR}/MIG_RAMDISK_OK"; return 1; }
    [[ -d ${MIG_RAMDISK} ]] && cd ${MIG_RAMDISK} || { logEvent "ERROR" "Missing ${MIG_RAMDISK} "; return 1; }

    for FILENAME_TO_CHECK in ${MIG_FILE_LIST_BUCKET[@]}
    do
        [[ -f ${MIG_RAMDISK}/${FILENAME_TO_CHECK} ]] || { logEvent "ERROR" "Missing ${MIG_RAMDISK}/${FILENAME_TO_CHECK}"; return 1; }
        [[ -f ${MIG_RAMDISK}/${FILENAME_TO_CHECK}.md5 ]] || { logEvent "ERROR" "Missing ${MIG_RAMDISK}/${FILENAME_TO_CHECK}.md5"; return 1; }

        cd ${MIG_RAMDISK} &>>${MIGSCRIPT_LOG} && \
        md5sum --check ${FILENAME_TO_CHECK}.md5 &>>${MIGSCRIPT_LOG} && \
        logEvent "OK" "Success MD5 check of ${FILENAME_TO_CHECK}" || \
        { logEvent "ERROR" "Fail MD5 check of ${MIG_RAMDISK}/${FILENAME_TO_CHECK}"; return 1; }
    done

    logEvent "END"
    return 0
}

function updateStateFSM {
    logEvent "INI"

    if [[ ! -f ${MIGSSTATE_DIR}/MIG_FSM_SFDISK_OK ]]; then
        MIGFSM_STATE='SFDISK'
        logEvent "INFO" "Set FSM State SFDISK"
    elif [[ ! -f ${MIGSSTATE_DIR}/MIG_FSM_ROOTA_OK ]]; then
        MIGFSM_STATE='ROOTA'
        logEvent "INFO" "Set FSM State ROOTA"
    elif [[ ! -f ${MIGSSTATE_DIR}/MIG_FSM_ROOTB_OK ]]; then
        MIGFSM_STATE='ROOTB'
        logEvent "INFO" "Set FSM State ROOTB"
    elif [[ ! -f ${MIGSSTATE_DIR}/MIG_FSM_STATE_OK ]]; then
        MIGFSM_STATE='STATE'
        logEvent "INFO" "Set FSM State STATE"
    elif [[ ! -f ${MIGSSTATE_DIR}/MIG_FSM_DATA_OK ]]; then
        MIGFSM_STATE='DATA'
        logEvent "INFO" "Set FSM State DATA"
    elif [[ ! -f ${MIGSSTATE_DIR}/MIG_FSM_BOOT_OK ]]; then
        MIGFSM_STATE='BOOT'
        logEvent "INFO" "Set FSM State BOOT"
    elif [[ ! -f ${MIGSSTATE_DIR}/MIG_FSM_CONFIG_OK ]]; then
        MIGFSM_STATE='CONFIG'
        logEvent "INFO" "Set FSM State CONFIG"
    else
        MIGFSM_STATE='SUCCESS'
        logEvent "INFO" "Set FSM State SUCCESS"
    fi

    logEvent "END"
    return 0
}

function migrationFSM {
    logEvent "INI"

    case ${MIGFSM_STATE} in
        'SFDISK')
            logEvent "INFO" "SFDISK > ${MIGMMC}"
            execCmmd "sfdisk ${MIGMMC} < ${MIG_RAMDISK}/${MIG_FILE_RESIN_SFDISK}" logSuccess || \
            { LogEvent "ERROR" "Fail flash SFDISK"; return 1; }
            touch ${MIGSSTATE_DIR}/MIG_FSM_SFDISK_OK 
            logEvent "OK" "SFDISK -> ${MIGMMC}"
            ;;

        'ROOTA')
            logEvent "INFO" "ROOTA - gunzip | dd"
            execCmmd "gunzip -c ${MIG_RAMDISK}/${MIG_FILE_RESIN_ROOTA} | dd of=${MIGMMC}p2 bs=4M" logSuccess || \
            { LogEvent "ERROR" "Fail flash ROOTA"; return 1; }
            touch ${MIGSSTATE_DIR}/MIG_FSM_ROOTA_OK 
            logEvent "OK" "ROOTA -> ${MIGMMC}p2"
            ;;

        'ROOTB')
            logEvent "INFO" "ROOTB - gunzip | dd"
            execCmmd "gunzip -c ${MIG_RAMDISK}/${MIG_FILE_RESIN_ROOTB} | dd of=${MIGMMC}p3 bs=4M" logSuccess || \
            { LogEvent "ERROR" "Fail flash ROOTB"; return 1; }
            touch ${MIGSSTATE_DIR}/MIG_FSM_ROOTB_OK 
            logEvent "OK" "ROOTB -> ${MIGMMC}p3"
            ;;
            
        'STATE')
            logEvent "INFO" "STATE - gunzip | dd"
            execCmmd "gunzip -c ${MIG_RAMDISK}/${MIG_FILE_RESIN_STATE} | dd of=${MIGMMC}p5 bs=4M" logSuccess || \
            { LogEvent "ERROR" "Fail flash STATE"; return 1; }
            touch ${MIGSSTATE_DIR}/MIG_FSM_STATE_OK 
            logEvent "OK" "STATE -> ${MIGMMC}p5"
            ;;
            
        'DATA')
            logEvent "INFO" "DATA - gunzip | dd"
            execCmmd "gunzip -c ${MIG_RAMDISK}/${MIG_FILE_RESIN_DATA} | dd of=${MIGMMC}p6 bs=4M" logSuccess || \
            { LogEvent "ERROR" "Fail flash DATA"; return 1; }
            touch ${MIGSSTATE_DIR}/MIG_FSM_DATA_OK 
            logEvent "OK" "DATA -> ${MIGMMC}p6"
            ;;
            
        'BOOT')
            makeMigstateBootBackup || return 1

            execCmmd "mount | grep ${MIGBOOT_DEVICE}" logSuccess && \
            { LogEvent "ERROR" "Fail ${MIGBOOT_DEVICE} is mounted"; return 1; }

            logEvent "INFO" "BOOT - gunzip | dd"
            execCmmd "gunzip -c ${MIG_RAMDISK}/${MIG_FILE_RESIN_BOOT} | dd of=${MIGBOOT_DEVICE} bs=4M" logSuccess || \
            { LogEvent "ERROR" "Fail flash BOOT"; return 1; }
            
            touch ${MIGSSTATE_DIR}/MIG_FSM_BOOT_OK 
            logEvent "OK" "BOOT -> ${MIGBOOT_DEVICE}"

            restoreMigstateBootBackup || return 1
            ;;
            
        'CONFIG')
            bootMount UPDATE_BOOT_CONFIG || return 1
            
            execCmmd "cp ${MIGSSTATE_DIR}/${MIG_FILE_RESIN_CONFIG_JSON} ${MIGBOOT_MOUNTDIR}/config.json" logSuccess || \
            { LogEvent "ERROR"; bootUmount UPDATE_BOOT_CONFIG; return 1; }

            if [[ -f ${MIGSSTATE_DIR}/resin-wlan ]]; then
                execCmmd "mkdir -vp ${MIGBOOT_MOUNTDIR}/system-connections" logSuccess && \
                execCmmd "cp -v ${MIGSSTATE_DIR}/resin-wlan ${MIGBOOT_MOUNTDIR}/system-connections/" logSuccess || \
                { LogEvent "ERROR"; bootUmount UPDATE_BOOT_CONFIG; return 1; }
            else
                logEvent "INFO" "missing resin-wlan"
            fi

            if [[ -f ${MIGSSTATE_DIR}/resin-ethernet ]]; then
                execCmmd "mkdir -vp ${MIGBOOT_MOUNTDIR}/system-connections" logSuccess && \
                execCmmd "cp -v ${MIGSSTATE_DIR}/resin-ethernet ${MIGBOOT_MOUNTDIR}/system-connections/" logSuccess || \
                { LogEvent "ERROR"; bootUmount UPDATE_BOOT_CONFIG; return 1; }
            else
                logEvent "INFO" "missing resin-ethernet"
            fi

            if [[ -f ${MIGSSTATE_DIR}/resin-3g ]]; then
                execCmmd "mkdir -vp ${MIGBOOT_MOUNTDIR}/system-connections" logSuccess && \
                execCmmd "cp -v ${MIGSSTATE_DIR}/resin-3g ${MIGBOOT_MOUNTDIR}/system-connections/" logSuccess || \
                { LogEvent "ERROR"; bootUmount UPDATE_BOOT_CONFIG; return 1; }

                execCmmd "cp -v /usr/bin/carrierSetup.sh ${MIGBOOT_MOUNTDIR}/toggleModem.sh" logSuccess || \
                { LogEvent "ERROR"; bootUmount UPDATE_BOOT_CONFIG; return 1; }

                execCmmd "cp -fv ${MIG_RAMDISK}/cmdline3G.txt ${MIGBOOT_MOUNTDIR}/cmdline.txt" logSuccess || \
                { LogEvent "ERROR"; bootUmount UPDATE_BOOT_CONFIG; return 1; }

                execCmmd "cp -fv ${MIG_RAMDISK}/config3G.txt ${MIGBOOT_MOUNTDIR}/config.txt" logSuccess || \
                { LogEvent "ERROR"; bootUmount UPDATE_BOOT_CONFIG; return 1; }

                execCmmd "cp -fv ${MIG_RAMDISK}/appBalena3G.config.json ${MIGBOOT_MOUNTDIR}/config.json" logSuccess || \
                { LogEvent "ERROR"; bootUmount UPDATE_BOOT_CONFIG; return 1; }

            else
                logEvent "INFO" "missing resin-3g"
            fi
            
            touch ${MIGSSTATE_DIR}/MIG_FSM_CONFIG_OK 
            logEvent "OK" "CONFIG -> ${MIGBOOT_DEVICE}"
            bootUmount UPDATE_BOOT_CONFIG || return 1
            ;;

        'SUCCESS')
            touch ${MIGSSTATE_DIR}/MIG_FSM_SUCCESS
            logEvent "INFO" "SUCCESS -- Reboot NOW!!!"
            ;;
        *)
            logEvent "ERROR" "Missing STATE ${MIGFSM_STATE}"
            return 1
    esac

    logEvent "END"
    return 0
}

# USE: bootMount USED_BY
function bootMount {
    if [[ -z "$1" ]]; then
        logEvent "ERROR" "Missing 'USED_BY' file parameter"
        return 1
    fi
    
    [[ -d ${MIGBOOT_MOUNTDIR} ]] || execCmmd "mkdir -vp ${MIGBOOT_MOUNTDIR}" logSuccess

    if [[ ! -f ${MIGSSTATE_DIR}/MIG_BOOT_DEVICE_MOUNTED ]]; then
        execCmmd "mount -vo rw ${MIGBOOT_DEVICE} ${MIGBOOT_MOUNTDIR}" logSuccess && \
        execCmmd "touch ${MIGSSTATE_DIR}/MIG_BOOT_DEVICE_MOUNTED" || \
        return 1
    fi

    execCmmd "touch ${MIGSSTATE_DIR}/MIG_BOOT_DEVICE_USED_BY_$1" || return 1

    return 0
}

# USE: bootUmount USED_BY
function bootUmount {
    if [[ -n "$1" ]]; then
        execCmmd "rm -v ${MIGSSTATE_DIR}/MIG_BOOT_DEVICE_USED_BY_$1" logSuccess || \
        return 1
    else
        logEvent "ERROR" "Missing 'USED_BY' file parameter"
        return 1
    fi

    ls ${MIGSSTATE_DIR}/MIG_BOOT_DEVICE_USED_BY_* 
    if [[ 0 -eq $? ]]; then
        logEvent "INFO" "BOOT is in use. Can't umount"
    elif [[ -f ${MIGSSTATE_DIR}/MIG_BOOT_DEVICE_MOUNTED ]]; then
        execCmmd "umount -v ${MIGBOOT_DEVICE}" logSuccess  && \
        execCmmd "rm -v ${MIGSSTATE_DIR}/MIG_BOOT_DEVICE_MOUNTED" logSuccess || \
        return 1
    else
        logEvent "ERROR" "Missing MIG_BOOT_DEVICE_MOUNTED"
        return 1
    fi

    return 0
}

# try to restore migstate, network and FSM config
function checkInit {
    logEvent "INI"

    if [[ -f ${MIGSSTATE_DIR}/MIG_INIT_MIGSTATE_BOOT_FOUND ]]; then
        logEvent "OK" "/init was successfully completed"
    else
        bootMount CHECK_INIT || return 1

        if [[ -d ${MIGSSTATE_BOOTDIR} ]]; then
            execCmmd "touch ${MIGSSTATE_DIR}/MIG_MIGSTATE_BOOT_FOUND"

            for FILENAME_TO_RESTORE in ${MIG_FILE_LIST_MIGSTATE_BOOT[@]}
            do
                if [[ -f ${MIGSSTATE_BOOTDIR}/${FILENAME_TO_RESTORE} ]]; then
                    execCmmd "cp -v ${MIGSSTATE_BOOTDIR}/${FILENAME_TO_RESTORE} ${MIGSSTATE_DIR}" logSuccess || \
                    {
                        logEvent "ERROR" "FAIL at copy ${FILENAME_TO_RESTORE}"
                        bootUmount CHECK_INIT
                        return 1
                    }
                else
                    logEvent "FAIL" "Missing ${FILENAME_TO_RESTORE} in ${MIGSSTATE_BOOTDIR}"
                fi
            done
            
            bootUmount CHECK_INIT || return 1
            restoreNetworkConfig || return 1
        else
            logEvent "ERROR" "${MIGSSTATE_BOOTDIR} NOT FOUND"
            bootUmount CHECK_INIT
            return 1
        fi
    fi

    logEvent "END"

    return 0
}

function checkRamdisk {
    logEvent "INI"

    # check if RAMDISK was created
    if [[ -f ${MIGSSTATE_DIR}/MIG_INIT_RAMDISK_OK ]]; then
        execCmmd "touch ${MIGSSTATE_DIR}/MIG_RAMDISK_OK"
        LogEvent "OK" "${MIG_RAMDISK} was successfully created"
    else
        createRamdisk || \
        {
            logEvent "ERROR" "Can't create RAMDISK"
            return 1
        }
    fi

    logEvent "END"
    return 0
}

function checkConfigWPA {
    logEvent "INI"

    if [[ -f ${MIGSSTATE_DIR}/wpa_supplicant.conf.bkp ]]; then
        execCmmd "mkdir -vp /etc/wpa_supplicant/" logSuccess && \
        execCmmd "cp -v ${MIGSSTATE_DIR}/wpa_supplicant.conf.bkp /etc/wpa_supplicant/wpa_supplicant.conf" logSuccess && \
        logEvent "OK" "wpa_supplicant.conf.bkp copyed" || \
        { 
            logEvent "ERROR" "can't copy wpa_supplicant.conf.bkp"
            return 1
        }

        execCmmd "systemctl restart wpa_supplicant@wlan0" logSuccess || \
        { 
            logEvent "ERROR" "Fail at 'restart wpa_supplicant@wlan0'"
            return 1
        }
    else
        logEvent "FAIL" "wpa_supplicant.conf.bkp NOT FOUND"
    fi

    logEvent "END"
    return 0
}

function check3GConnection {
    logEvent "INI"

    if [[ 'UP' == "${MIGCONFIG_3G_CONN}" ]]; then 
        execCmmd "systemctl restart mig3gconn" logSuccess && \
        execCmmd "sleep 30" || \
        { 
            logEvent "ERROR" "Fail at 'restart mig3gconn'"
            return 1
        }
    else
        logEvent "FAIL" "Not 3G configuration detected"
    fi

    logEvent "END"
    return 0
}

function restoreNetworkConfig {
    logEvent "INI"

    if [[ -f ${MIGSSTATE_DIR}/en.network ]]; then
        execCmmd "mkdir -vp /etc/systemd/network/" logSuccess && \
        execCmmd "cp -v ${MIGSSTATE_DIR}/en.network /etc/systemd/network/en.network" && \
        logEvent "OK" "en.network copyed" || \
        { 
            logEvent "ERROR" "can't copy en.network"
            return 1
        }
    else
        logEvent "FAIL" "en.network NOT FOUND"
    fi

    if [[ -f ${MIGSSTATE_DIR}/wlan0.network ]]; then
        execCmmd "mkdir -vp /etc/systemd/network/" logSuccess && \
        execCmmd "cp -v ${MIGSSTATE_DIR}/wlan0.network /etc/systemd/network/wlan0.network" logSuccess && \
        logEvent "OK" "wlan0.network copyed" || \
        { 
            logEvent "ERROR" "can't copy wlan0.network"
            return 1
        }
    else
        logEvent "FAIL" "wlan0.network NOT FOUND"
    fi

    checkConfigWPA || return 1
    check3GConnection || return 1

    logEvent "END"
    return 0
}

function checkRootFS {
    logEvent "INI"

    [[ -d ${MIGROOTFS_MOUNTDIR} ]] || execCmmd "mkdir -vp ${MIGROOTFS_MOUNTDIR}" logSuccess || return 1

    execCmmd "mount -v ${MIGROOTFS_DEVICE} ${MIGROOTFS_MOUNTDIR}" logSuccess || return 1

    # try to copy backup of raspbian boot
    if [[ -f /root/${MIGBKP_RASPBIANBOOT} ]]; then
        logEvent "OK" "${MIGBKP_RASPBIANBOOT} found in /root"
    elif [[ -f ${MIGROOTFS_MOUNTDIR}/root/${MIGBKP_RASPBIANBOOT} ]]; then
        execCmmd "cp -v ${MIGROOTFS_MOUNTDIR}/root/${MIGBKP_RASPBIANBOOT} /root" logSuccess || return 1
    else
        logEvent "FAIL" "${MIGBKP_RASPBIANBOOT} not found in ${MIGROOTFS_MOUNTDIR}/root"
    fi

    #try to copy migdownloads files
    if [[ -d ${MIGDOWNLOADS_DIR} ]]; then
        logEvent "OK" "Found ${MIGDOWNLOADS_DIR}"

        [[ -f ${MIGSSTATE_DIR}/MIG_RAMDISK_OK ]] || { logEvent "ERROR" "Missing ${MIGSSTATE_DIR}/MIG_RAMDISK_OK"; return 1; }
        [[ -d ${MIG_RAMDISK} ]] && cd ${MIG_RAMDISK} || { logEvent "ERROR" "Missing ${MIG_RAMDISK}"; return 1; }

        for FILENAME_TO_COPY in ${MIG_FILE_LIST_BUCKET[@]}
        do
            if [[ -f ${MIGDOWNLOADS_DIR}/${FILENAME_TO_COPY} ]]; then
                execCmmd "cp -v ${MIGDOWNLOADS_DIR}/${FILENAME_TO_COPY} ${MIG_RAMDISK}" logSuccess && \
                logEvent "OK" "${FILENAME_TO_COPY} found in FSROOT and copyed to ${MIG_RAMDISK}" || \
                return 1
            fi
        done
    else
        logEvent "FAIL" "Not Found ${MIGDOWNLOADS_DIR}"

    fi

    execCmmd "umount -v ${MIGROOTFS_DEVICE}" logSuccess || return 1

    logEvent "END"
    return 0
}

function makeMigstateBootBackup {
    logEvent "INI"
    
    bootMount MAKE_MIGSTATE_BOOT_BKP || return 1
    
    # backup old migstate
    if [[ -d ${MIGSSTATE_BOOTDIR} ]]; then
        execCmmd "cd ${MIGBOOT_MOUNTDIR}" logSuccess && \
        execCmmd "tar -czvf ${MIGBKP_MIGSTATE_TMP} migstate" logSuccess && \
        execCmmd "cd /tmp" logSuccess && \
        logEvent "OK" "Backup old migstate: Created ${MIGBKP_MIGSTATE_TMP}" || \
        { 
            logEvent "ERROR" "Fail at backup old migstate";
            bootUmount MAKE_MIGSTATE_BOOT_BKP
            return 1
        }
    fi

    bootUmount MAKE_MIGSTATE_BOOT_BKP || return 1
    logEvent "END"
    return 0
}

function restoreMigstateBootBackup {
    logEvent "INI"
    
    bootMount RESTORE_MIGSTATE_BOOT_BKP || return 1
    
    # Try to restore backup of old migstate
    if [[ -f ${MIGBKP_MIGSTATE_TMP} ]]; then
        execCmmd "tar -xzvf ${MIGBKP_MIGSTATE_TMP} -C ${MIGBOOT_MOUNTDIR}" logSuccess && \
        logEvent "OK" "Restored old migstate backup" || \
        { 
            logEvent "ERROR" "Can't restore tmp_backup migstate";
            bootUmount RESTORE_MIGSTATE_BOOT_BKP;
            return 1
        }
    else
        logEvent "ERROR" "Can't find tmp_backup migstate";
        bootUmount RESTORE_MIGSTATE_BOOT_BKP;
        return 1
    fi

    bootUmount RESTORE_MIGSTATE_BOOT_BKP || return 1
    logEvent "END"
    return 0
}

function restoreRaspbianBoot {
    logEvent "INI"
    
    [[ -f ${MIGSSTATE_DIR}/MIG_FSM_SFDISK_OK ]] && \
    { LogEvent "FAIL" "SFDISK present. The partition table was altered"; return 1; }


    makeMigstateBootBackup || return 1
    bootMount RESTORE_RASPB_BOOT || return 1

    if [[ -f /root/${MIGBKP_RASPBIANBOOT} ]];then
        execCmmd "rm -vrf ${MIGBOOT_DIR}/*" logSuccess && \
        execCmmd "tar -xzvf ${MIGBKP_RASPBIANBOOT} -C /" logSuccess && \
        logEvent "OK" "Restaured Raspbian Backup in boot partition" || \
        { 
            logEvent "ERROR" "Can't restore Raspbian Backup in boot partition"
            # TODO: RESTORE MIGOS BOOT???
            bootUmount RESTORE_RASPB_BOOT
            return 1
        }
    else
        logEvent "ERROR" "Missing Raspbian BackUp File: ${MIGBKP_RASPBIANBOOT}"
        bootUmount RESTORE_RASPB_BOOT;
        return 1
    fi

    bootUmount RESTORE_RASPB_BOOT || return 1
    restoreMigstateBootBackup || return 1

    logEvent "END"
    return 0
}

function createRamdisk {
    logEvent "INI"

    execCmmd "umount -v ${MIG_RAMDISK}" logSuccess

    execCmmd "mkdir -vp ${MIG_RAMDISK}" logSuccess && \
    execCmmd "rm -vrf ${MIG_RAMDISK}/*" logSuccess && \
    execCmmd "mount -vt tmpfs -o size=400M tmpramdisk ${MIG_RAMDISK}" logSuccess && \
    {
        touch ${MIGSSTATE_DIR}/MIG_RAMDISK_OK
        logEvent "OK" "RAMDISK was created"
    } || \
    { 
        logCommand "Fail at create RAMDISK"
        return 1
    }

    logEvent "END"
    return 0
}

function updateBootMigState {
    logEvent "INI"

    bootMount UPDATE_BOOT_MIGSTATE || return 1

    execCmmd "cp -rv ${MIGSSTATE_DIR} ${MIGBOOT_MOUNTDIR}" logSuccess && \
    logEvent "OK" "Updated MIGSTATE boot dir" || \
    return 1

    bootUmount UPDATE_BOOT_MIGSTATE || return 1
    
    logEvent "END"
    return 0
}