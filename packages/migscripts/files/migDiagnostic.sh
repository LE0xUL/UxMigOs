#!/bin/bash

# wget -O - 'http://10.0.0.21/balenaos/migscripts/migDiagnostic.sh' | bash
# wget -O - 'http://10.0.0.21/balenaos/migscripts/migDiagnostic.sh' | sudo bash
# curl -s 'http://10.0.0.21/balenaos/migscripts/migDiagnostic.sh' | bash
# wget -O - 'https://storage.googleapis.com/balenamigration/migscripts/migDiagnostic.sh' | bash

MIGTIME_INI="$(cat /proc/uptime | grep -o '^[0-9]\+')"
## Device ID
MIGDID="$(hostname)"
[[ 0 -ne $? ]] && { echo "[FAIL] Can't set MIGDID"; exit $LINENO; }

MIGLOG_SCRIPTNAME="migDiagnostic.sh"
# MIGLOG_SCRIPTNAME=$(basename "$0")
# MIGLOG_SCRIPTNAME=${BASH_SOURCE[1]##*/}

# MIGSSTATEDIR_BOOT="/boot/migstate"
MIGSSTATE_DIR="/root/migstate"
MIGCOMMAND_LOG="${MIGSSTATE_DIR}/cmd.log"
MIGSCRIPT_LOG="${MIGSSTATE_DIR}/migDiagnostic.log"
# MIGSCRIPT_STATE='STATE'
MIGMMC="/dev/mmcblk0"
MIGBOOT_DEV='/dev/mmcblk0p1'
MIGCONFIG_FILE="${MIGSSTATE_DIR}/mig.config"
MIGCONFIG_BOOTSIZE=0

MIGWEBLOG_URL='https://eu.webhook.logs.insight.rapid7.com/v1/noformat'
MIGWEBLOG_KEYEVENT='f79248d1-bbe0-427b-934b-02a2dee5f24f'
MIGWEBLOG_KEYCOMMAND='642de669-cf83-4e19-a6bf-9548eb7f5210'

MIGBUCKET_URL='http://10.0.0.21/balenaos'
# MIGBUCKET_URL='https://storage.googleapis.com/balenamigration'
MIGBUCKET_FILETEST='test.file'

MIGOS_RASPBIAN_BOOT_FILE="/boot/MIGOS_RASPBIAN_BOOT_${MIGDID}"
MIGOS_INSTALLED_BOOT_FILE="/boot/MIGOS_BOOT_INSTALLED"

# USE: logCommand 
# USE: logCommand MESSAGE 
# USE: logCommand MESSAGE FUNCNAME
# USE: logCommand MESSAGE FUNCNAME BASH_LINENO
# (implicitly the file set by ${MIGCOMMAND_LOG} is sent)
function logCommand {
    MIGLOG_CMDMSG="$1"
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

# USE: exitError MESSAGE 
# USE: exitError MESSAGE logCommand <to run logCommand too>
function exitError {
    touch ${MIGSSTATE_DIR}/MIG_DIAGNOSTIC_FAIL
    MIGLOG_MSG="${1:-DIAGNOSTIC_FAIL}"

    [[ "logCommand" == "$2" ]] && logCommand "${MIGLOG_MSG}" "${FUNCNAME[1]}" "${BASH_LINENO[0]}"

    logEvent "EXIT" "${MIGLOG_MSG}" "${FUNCNAME[1]}" "${BASH_LINENO[0]}"
    
    echo "" &>>${MIGSCRIPT_LOG}
    date |& tee -a ${MIGSCRIPT_LOG}
    echo "[ ####    DIAGNOSTIC FAIL    #### ]" |& tee -a ${MIGSCRIPT_LOG}
    echo "" &>>${MIGSCRIPT_LOG}
    echo "${MIGLOG_SCRIPTNAME}:${FUNCNAME[1]}[${BASH_LINENO[0]}] ${MIGLOG_MSG}" |& tee -a ${MIGSCRIPT_LOG}

    logFilePush
    rm -vf ${MIGSSTATE_DIR}/MIG_DIAGNOSTIC_IS_RUNING
    exit $LINENO
}

function validateOS {
    logEvent "INI"

    source '/etc/os-release' &>${MIGCOMMAND_LOG} || \
    exitError "FAIL source /etc/os-release" logCommand

    # if [[ -f '/etc/os-release' ]]; then
    #     source '/etc/os-release'
    # else
    #     MIGSCRIPT_STATE="FAIL"
    #     logEvent "/etc/os-release missing"
    #     >${MIGCOMMAND_LOG}
    #     exitError
    # fi    

    [[ 'raspbian' = ${ID} ]] && \
    logEvent "OK" "raspbian detected: ${PRETTY_NAME}" || 
    exitError "Wrong OS: ${ID} / ${PRETTY_NAME}"

    # if [[ 'raspbian' = ${ID} ]]; then
    #     MIGSCRIPT_STATE="OK"
    #     logEvent "OK" "raspbian detected: ${PRETTY_NAME}"
    # else
    #     MIGSCRIPT_STATE="FAIL"
    #     logEvent "Wrong OS: ${ID} / ${PRETTY_NAME}"
    #     >${MIGCOMMAND_LOG}
    #     exitError
    # fi

    logEvent "END"
    return 0
}

# https://www.raspberrypi-spy.co.uk/2012/09/checking-your-raspberry-pi-board-version/
function validateRPI {
    logEvent "INI"

    if [[ -f '/proc/device-tree/model' ]]; then
        MIG_RPI_MODEL=$(cat /proc/device-tree/model)
        MIG_RPI_NAME=$(echo ${MIG_RPI_MODEL} | awk '{print $1 $2}')
        MIG_RPI_VER=$(echo ${MIG_RPI_MODEL} | awk '{print $3}')

        [[ 'RaspberryPi' == "${MIG_RPI_NAME}" ]] && \
        [[ 3 -eq ${MIG_RPI_VER} ]] && \
        logEvent "OK" "RaspberryPi 3 detected: ${MIG_RPI_MODEL}" || \
        exitError "Wrong RPI: ${MIG_RPI_MODEL}"

        # if [[ 'RaspberryPi' == "${MIG_RPI_NAME}" ]] && [[ 3 -eq ${MIG_RPI_VER} ]]; then
        #     MIGSCRIPT_STATE="OK"
        #     logEvent "RaspberryPi 3 detected: ${MIG_RPI_MODEL}"
        # else
        #     MIGSCRIPT_STATE="FAIL"
        #     logEvent "Wrong RPI: ${MIG_RPI_MODEL}"
        #     >${MIGCOMMAND_LOG}
        #     exitError
        # fi
    else
        # MIGSCRIPT_STATE="FAIL"
        # logEvent "/proc/device-tree/model missing"
        # >${MIGCOMMAND_LOG}
        # exitError

        exitError "ERROR" "Missing /proc/device-tree/model"
    fi    

    logEvent "END"
    return 0
}

function validateBootPartition {
    logEvent "INI"

    [[ -b "${MIGBOOT_DEV}" ]] && \
    logEvent "OK" "${MIGBOOT_DEV} detected" || \
    exitError "Missing ${MIGBOOT_DEV}"

    # if [[ -b "${MIGBOOT_DEV}" ]]; then
    #     MIGSCRIPT_STATE="OK"
    #     logEvent "${MIGBOOT_DEV} detected"
    # else
    #     MIGSCRIPT_STATE="FAIL"
    #     logEvent "${MIGBOOT_DEV} missing"
    #     exitError
    # fi

    # MIGBOOT_MOUNT=$(mount | grep "${MIGBOOT_DEV}.on./boot")
    mount &>${MIGCOMMAND_LOG} && \
    cat ${MIGCOMMAND_LOG} >> ${MIGSCRIPT_LOG} && \
    cat ${MIGCOMMAND_LOG} | grep "${MIGBOOT_DEV}.on./boot" &>>${MIGSCRIPT_LOG} || \
    exitError "Boot device do not mounted: ${MIGBOOT_DEV}" logCommand
    # {
        # MIGSCRIPT_STATE="FAIL";
        # logEvent "Boot device do not mounted: ${MIGBOOT_DEV}";
        # logCommand;
        # exitError;
    # }

    # if [[ 0 -ne $? ]]; then
    #     MIGSCRIPT_STATE="FAIL"
    #     logEvent "Boot device do not mounted: ${MIGBOOT_DEV}"
    #     mount &>${MIGCOMMAND_LOG} && cat ${MIGCOMMAND_LOG} >> ${MIGSCRIPT_LOG}
    #     logCommand
    #     exitError
    # fi
    
    # fdisk -l ${MIGMMC} 2>&1 | tee ${MIGCOMMAND_LOG}
    # fdisk -l ${MIGMMC} |& tee ${MIGCOMMAND_LOG}
    # logCommand

    fdisk -l ${MIGMMC} &>${MIGCOMMAND_LOG} && \
    cat ${MIGCOMMAND_LOG} >> ${MIGSCRIPT_LOG} || \
    exitError "FAIL at exec fdisk -l" logCommand
    # { logCommand; exitError; }

    MIGBOOT_DATA=$(fdisk -l ${MIGMMC} | grep ${MIGBOOT_DEV})
    MIGBOOT_START=$(echo ${MIGBOOT_DATA} | awk '{print $2}')
    MIGBOOT_END=$(echo ${MIGBOOT_DATA} | awk '{print $3}')
    MIGBOOT_SECTORS=$(echo ${MIGBOOT_DATA} | awk '{print $4}')
    MIGBOOT_SIZE=$(echo ${MIGBOOT_DATA} | awk '{print $5}')

    case ${MIGBOOT_SIZE} in
        '40M')
            logEvent "OK" "${MIGBOOT_SIZE} detected"
            if [[ 8192 -eq ${MIGBOOT_START} ]] && [[ 90111 -eq ${MIGBOOT_END} ]] && [[ 81920 -eq ${MIGBOOT_SECTORS} ]]; then
                logEvent "OK" "Logical sectors verified: ${MIGBOOT_START} : ${MIGBOOT_END} : ${MIGBOOT_SECTORS}"
                echo "MIGCONFIG_BOOTSIZE=40" >>${MIGCONFIG_FILE}
                MIGCONFIG_BOOTSIZE=40
            else
                # MIGSCRIPT_STATE="FAIL"
                # logEvent "Logical sectors missmatch: ${MIGBOOT_START} : ${MIGBOOT_END} : ${MIGBOOT_SECTORS}"
                # >${MIGCOMMAND_LOG}
                # exitError
                exitError "Logical sectors missmatch: ${MIGBOOT_START} : ${MIGBOOT_END} : ${MIGBOOT_SECTORS}"
            fi
            ;;

        '60M')
            logEvent "OK" "${MIGBOOT_SIZE} detected"
            if [[ 8192 -eq ${MIGBOOT_START} ]] && [[ 131071 -eq ${MIGBOOT_END} ]] && [[ 122880 -eq ${MIGBOOT_SECTORS} ]]; then
                logEvent "OK" "Logical sectors verified: ${MIGBOOT_START} : ${MIGBOOT_END} : ${MIGBOOT_SECTORS}"
                echo "MIGCONFIG_BOOTSIZE=60" >>${MIGCONFIG_FILE}
                MIGCONFIG_BOOTSIZE=60
            else
                # MIGSCRIPT_STATE="FAIL"
                # logEvent "Logical sectors missmatch: ${MIGBOOT_START} : ${MIGBOOT_END} : ${MIGBOOT_SECTORS}"
                # >${MIGCOMMAND_LOG}
                # exitError
                exitError "Logical sectors missmatch: ${MIGBOOT_START} : ${MIGBOOT_END} : ${MIGBOOT_SECTORS}"
            fi
            ;;

        '256M')
            logEvent "OK" "${MIGBOOT_SIZE} detected"
            if [[ 8192 -eq ${MIGBOOT_START} ]] && [[ 532479 -eq ${MIGBOOT_END} ]] && [[ 524288 -eq ${MIGBOOT_SECTORS} ]]; then
                logEvent "Logical sectors verified: ${MIGBOOT_START} : ${MIGBOOT_END} : ${MIGBOOT_SECTORS}"
                echo "MIGCONFIG_BOOTSIZE=256" >>${MIGCONFIG_FILE}
                MIGCONFIG_BOOTSIZE=256
            else
                # MIGSCRIPT_STATE="FAIL"
                # logEvent "Logical sectors missmatch: ${MIGBOOT_START} : ${MIGBOOT_END} : ${MIGBOOT_SECTORS}"
                # >${MIGCOMMAND_LOG}
                exitError "Logical sectors missmatch: ${MIGBOOT_START} : ${MIGBOOT_END} : ${MIGBOOT_SECTORS}"
            fi
            ;;

        *)
            # MIGSCRIPT_STATE="FAIL"
            # logEvent "${MIGBOOT_SIZE} not suported"
            # >${MIGCOMMAND_LOG}
            exitError "${MIGBOOT_SIZE} not suported"
    esac

    logEvent "END"
    return 0
}

function validationNetwork {
    logEvent "INI"

    if [[ -f '/etc/dhcpcd.conf' ]]; then
        STATIC_IP=$(cat /etc/dhcpcd.conf | grep -vE "^#" | grep -E "static.*ip_address")
        if [[ 0 -eq $? ]]; then 
            MIGNET_IPSTATIC=1
            logEvent "OK" "Static IP detected: ${STATIC_IP}"
        else
            logEvent "OK" "DHCP detected"
        fi
    else
        # MIGSCRIPT_STATE="FAIL"
        # logEvent "Missing /etc/dhcpcd.conf"
        # >${MIGCOMMAND_LOG}
        exitError "Missing /etc/dhcpcd.conf"
    fi

    echo ">>> ip a" &>>${MIGSCRIPT_LOG}
    ip a &>${MIGCOMMAND_LOG} && \
    cat ${MIGCOMMAND_LOG} >> ${MIGSCRIPT_LOG} || \
    exitError "FAIL at exec 'ip a'" logCommand

    echo ">>> ip r" &>>${MIGSCRIPT_LOG}
    ip r &>${MIGCOMMAND_LOG} && \
    cat ${MIGCOMMAND_LOG} >> ${MIGSCRIPT_LOG} || \
    exitError "FAIL at exec 'ip r'" logCommand

    for interface in $(ls /sys/class/net)
    do
        case ${interface:0:2} in
            # loop
            'lo')
                # echo "loop"
                ;;
            # Ethernet
            'et')
                if [[ 1 -eq $(cat /sys/class/net/${interface}/carrier) ]]; then
                    logEvent "OK" "Ethernet connection detected: ${interface}"
                    echo "MIGCONFIG_ETH_CONN='UP'" >>${MIGCONFIG_FILE}
                    
                    MIGNET_ETHSTATIC=$(cat /etc/dhcpcd.conf | grep -vE "^#" | grep -E "interface.*${interface}")

                    if [[ 0 -eq $? ]] && [[ 1 -eq ${MIGNET_IPSTATIC} ]];then
                        echo "MIGCONFIG_ETH_DHCP='NO'" >>${MIGCONFIG_FILE}

                        MIGNET_ETHIPMASK=$(ip a show dev ${interface} | grep "inet " | awk '{print $2}')
                        echo "MIGCONFIG_ETH_IPMASK='${MIGNET_ETHIPMASK}'" >>${MIGCONFIG_FILE}

                        MIGNET_ETHGWIP=$(ip r show dev ${interface} | grep "via " | awk '{print $3}')
                        echo "MIGCONFIG_ETH_GWIP='${MIGNET_ETHGWIP}'" >>${MIGCONFIG_FILE}

                        MIGNET_ETHDNSIP=$(cat /etc/resolv.conf | grep -vE "^#" | grep -m 1 nameserver | awk '{print $2}')
                        echo "MIGCONFIG_ETH_DNSIP='${MIGNET_ETHDNSIP}'" >>${MIGCONFIG_FILE}
                    else
                        echo "MIGCONFIG_ETH_DHCP='YES'" >>${MIGCONFIG_FILE}
                    fi
                else
                    logEvent "FAIL" "No Ethernet connection detected: ${interface}"
                fi
                ;;
            # Wireless
            'wl')
                if [[ 1 -eq $(cat /sys/class/net/${interface}/carrier) ]]; then
                    logEvent "OK" "Wireless connection detected: ${interface}"
                    echo "MIGCONFIG_WLAN_CONN='UP'" >>${MIGCONFIG_FILE}
                    
                    iwgetid ${interface} --raw &>${MIGCOMMAND_LOG} || \
                    exitError "FAIL at exec 'iwgetid ${interface} --raw'" logCommand

                    MIGNET_WLANSSID=$(iwgetid ${interface} --raw)

                    if [[ -n ${MIGNET_WLANSSID} ]];then
                        logEvent "OK" "Wireless SSID detected: ${MIGNET_WLANSSID}"
                        echo "MIGCONFIG_WLAN_SSID='${MIGNET_WLANSSID}'" >>${MIGCONFIG_FILE}
                    else
                        logEvent "FAIL" "No Wireless SSID detected: ${MIGNET_WLANSSID}"
                    fi

                    cat '/etc/wpa_supplicant/wpa_supplicant.conf' &>${MIGCOMMAND_LOG} && \
                    grep 'psk' ${MIGCOMMAND_LOG} | cut -d '=' -f 2 &>var.tmp && \
                    MIGNET_WLANPSK=$(cat var.tmp) || \
                    exitError "ERROR to get psk" logCommand
                    
                    if [[ -n ${MIGNET_WLANPSK} ]];then
                        logEvent "OK" "Wireless PSK detected: ${MIGNET_WLANPSK//\"}"
                        echo "MIGCONFIG_WLAN_PSK='${MIGNET_WLANPSK//\"}'" >>${MIGCONFIG_FILE}
                    else
                        logEvent "FAIL" "No Wireless PSK detected: ${MIGNET_WLANPSK}"
                    fi
                    
                    MIGNET_WLANSTATIC=$(cat /etc/dhcpcd.conf | grep -vE "^#" | grep -E "interface.*${interface}")

                    if [[ 0 -eq $? ]] && [[ 1 -eq ${MIGNET_IPSTATIC} ]];then
                        echo "MIGCONFIG_WLAN_DHCP='NO'" >>${MIGCONFIG_FILE}

                        MIGNET_WLANIPMASK=$(ip a show dev ${interface} | grep "inet " | awk '{print $2}')
                        echo "MIGCONFIG_WLAN_IPMASK='${MIGNET_WLANIPMASK}'" >>${MIGCONFIG_FILE}

                        MIGNET_WLANGWIP=$(ip r show dev ${interface} | grep "via " | awk '{print $3}')
                        echo "MIGCONFIG_WLAN_GWIP='${MIGNET_WLANGWIP}'" >>${MIGCONFIG_FILE}

                        MIGNET_WLANDNSIP=$(cat /etc/resolv.conf | grep -vE "^#" | grep -m 1 nameserver | awk '{print $2}')
                        echo "MIGCONFIG_WLAN_DNSIP='${MIGNET_WLANDNSIP}'" >>${MIGCONFIG_FILE}
                    else
                        echo "MIGCONFIG_WLAN_DHCP='YES'" >>${MIGCONFIG_FILE}
                    fi
                else
                    logEvent "FAIL" "No Wireless connection detected: ${interface}"
                fi
                ;;
            # 3G
            'pp')
                if [[ 1 -eq $(cat /sys/class/net/${interface}/carrier) ]]; then
                    logEvent "OK" "3G connection detected: ${interface}"
                    echo "MIGCONFIG_3G_CONN='UP'" >>${MIGCONFIG_FILE}
                else
                    logEvent "FAIL" "No 3G connection detected: ${interface}"
                fi
                ;;
            *)
                logEvent "FAIL" "unrecognized network interface: ${interface}"
                ;;
        esac    
    done

    logEvent "END"
    return 0
}

function checkNetworkStatus {
    logEvent "INI"

    if [[ 'UP' == "${MIGCONFIG_ETH_CONN}" ]] || [[ 'UP' == "${MIGCONFIG_WLAN_CONN}" ]] || [[ 'UP' == "${MIGCONFIG_3G_CONN}" ]]; then
        if [[ 'UP' == "${MIGCONFIG_ETH_CONN}" ]] || [[ 'UP' == "${MIGCONFIG_WLAN_CONN}" ]]; then
            logEvent "OK" "Valid connection detected"
        else
            exitError "3G connection is not supported in the migrate process"
        fi
    else
        exitError "No network connection detected"
    fi

    logEvent "END"
}

function checkFilesAtBucket {
    logEvent "INI"

    fileList=(  'appBalena.config.json' \
                'migboot-migos-balena.tgz' \
                "p1-resin-boot-${MIGCONFIG_BOOTSIZE}.img.gz" \
                'p2-resin-rootA.img.gz' \
                'p3-resin-rootB.img.gz' \
                'p5-resin-state.img.gz' \
                'p6-resin-data.img.gz' \
                "resin-partitions-${MIGCONFIG_BOOTSIZE}.sfdisk" \
                )

    for fileName in ${fileList[@]}
    do
        wget -q --tries=10 --timeout=10 --spider "${MIGBUCKET_URL}/${fileName}" &>${MIGCOMMAND_LOG} && \
        logEvent "OK" "${fileName} found in the bucket server" || \
        exitError "ERROR to find ${fileName} in the bucket server" logCommand

        # if [[ $? -ne 0 ]]; then
        #     MIGSCRIPT_STATE="FAIL"
        #     logEvent "${fileName} missing in the bucket"
        #     logCommand
        #     exitError
        # else 
        #     MIGSCRIPT_STATE="OK"
        #     logEvent "${fileName} found in the bucket"
        # fi        
    done

    for fileName in ${fileList[@]}
    do
        wget -q --tries=10 --timeout=10 --spider "${MIGBUCKET_URL}/${fileName}.md5" &>${MIGCOMMAND_LOG} && \
        logEvent "OK" "${fileName}.md5 found in the bucket server" || \
        exitError "ERROR to find ${fileName}.md5 in the bucket server" logCommand

        # if [[ $? -ne 0 ]]; then
        #     MIGSCRIPT_STATE="FAIL"
        #     logEvent "${fileName}.md5 missing in the bucket"
        #     logCommand
        #     exitError
        # else 
        #     MIGSCRIPT_STATE="OK"
        #     logEvent "${fileName}.md5 found in the bucket"
        # fi
    done

    logEvent "END"
}

function testMigState {
    logEvent "INI"
    
    if [[ -f ${MIGSSTATE_DIR}/MIG_INSTALL_MIGOS_SUCCESS ]] && [[ -f ${MIGOS_INSTALLED_BOOT_FILE} ]]; then
        exitError "MIGOS is already installed in the system. Reboot the system to initiate the migration process"
    elif [[ -f ${MIGOS_INSTALLED_BOOT_FILE} ]]; then
        exitError "[FAIL] MIGOS_BOOT is present in the system"
    elif [[ -f ${MIGSSTATE_DIR}/MIG_INSTALL_MIGOS_SUCCESS ]]; then
        exitError "[FAIL] INSTALL MIGOS was SUCCESS but MIGOS_BOOT is not present in the system"
    else
        rm -rf ${MIGSSTATE_DIR} && \
        echo "[OK] ${MIGSSTATE_DIR} deleted" || \
        exitError "[FAIL] Can't delete ${MIGSSTATE_DIR}"

        mkdir -vp ${MIGSSTATE_DIR}
    fi
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
    wget -q --tries=10 --timeout=10 --spider "$MIGBUCKET_URL/$MIGBUCKET_FILETEST"

    if [[ $? -ne 0 ]]; then
        echo "[FAIL] No connection to the bucket server detected"
        echo "Is necessary a connection to the bucket server to run this script."
        exit $LINENO
    else
        echo "[OK] Network"
    fi
}

function testDiagnosticRunning {
    sleep 0.$[ ( $RANDOM % 10 ) ]s

    if [[ -f ${MIGSSTATE_DIR}/MIG_DIAGNOSTIC_IS_RUNING ]]
    then
        echo "[FAIL] Another diagnostic script is running"
        exit $LINENO
    fi
}

function iniDiagnostic {
    testIsRoot
    testBucketConnection
    testDiagnosticRunning

    mkdir -vp ${MIGSSTATE_DIR} || \
    {
        echo "[FAIL] Can't create ${MIGSSTATE_DIR}"
        exit $LINENO
    }

    touch ${MIGSSTATE_DIR}/MIG_DIAGNOSTIC_IS_RUNING

    testMigState

    touch ${MIGSSTATE_DIR}/MIG_DIAGNOSTIC_IS_RUNING

    echo "[ ####    DIAGNOSTIC INI    #### ]" |& tee -a ${MIGSCRIPT_LOG}
    date |& tee -a ${MIGSCRIPT_LOG}

    logEvent "INI"

    echo "MIGCONFIG_DID='${MIGDID}'" |& tee -a ${MIGCONFIG_FILE} ${MIGSCRIPT_LOG} &>${MIGCOMMAND_LOG} || \
    exitError "FAIL at inject MIGCONFIG_DID to ${MIGCONFIG_FILE}: ${MIGDID}" logCommand

    validateOS
    validateRPI
    validateBootPartition
    validationNetwork

    source ${MIGCONFIG_FILE} &>${MIGCOMMAND_LOG} || \
    exitError "FAIL at exec: source ${MIGCONFIG_FILE}" logCommand

    checkNetworkStatus
    checkFilesAtBucket

    touch ${MIGSSTATE_DIR}/MIG_DIAGNOSTIC_SUCCESS

    [[ -f ${MIGOS_RASPBIAN_BOOT_FILE} ]] || touch ${MIGOS_RASPBIAN_BOOT_FILE}

    logEvent "SUCCESS" "TOTAL TIME: $(( $(cat /proc/uptime | grep -o '^[0-9]\+') - ${MIGTIME_INI} )) seconds"

    echo "" &>>${MIGSCRIPT_LOG}
    cat ${MIGCONFIG_FILE} &>>${MIGSCRIPT_LOG}
    echo "" &>>${MIGSCRIPT_LOG}
    date &>>${MIGSCRIPT_LOG}
    echo "[ ####    DIAGNOSTIC SUCCESS    #### ]" |& tee -a ${MIGSCRIPT_LOG}

    logFilePush
    rm -vf ${MIGSSTATE_DIR}/MIG_DIAGNOSTIC_IS_RUNING
}

iniDiagnostic

echo $LINENO
exit 0