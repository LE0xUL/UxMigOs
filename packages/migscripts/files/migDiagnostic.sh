#!/bin/bash

# wget -O - 'http://10.0.0.211/balenaos/scripts/migDiagnostic.sh' | bash
# curl -s 'http://10.0.0.211/balenaos/scripts/migDiagnostic.sh' | bash
# wget -O - 'https://storage.googleapis.com/balenamigration/migscripts/migDiagnostic.sh' | bash

MIGSSTATEDIR_BOOT="/boot/migstate"
MIGSSTATEDIR_ROOT="/root/migstate"
MIGSSTATE_DIR="${MIGSSTATEDIR_ROOT}"
MIGCOMMAND_LOG="${MIGSSTATE_DIR}/cmd.log"
MIGSCRIPT_LOG="${MIGSSTATE_DIR}/diagnostic.log"
MIGSCRIPT_STAGE='STAGE'
MIGSCRIPT_EVENT='EVENT'
MIGSCRIPT_STATE='STATE'
MIGCONFIG_FILE="${MIGSSTATE_DIR}/mig.config"
## Device ID
MIGDID="$(hostname)"
MIGMMC="/dev/mmcblk0"
MIGBOOT_DEV='/dev/mmcblk0p1'

MIGWEBLOG_URL='https://eu.webhook.logs.insight.rapid7.com/v1/noformat'
MIGWEBLOG_KEYEVENT='f79248d1-bbe0-427b-934b-02a2dee5f24f'
MIGWEBLOG_KEYCOMMAND='642de669-cf83-4e19-a6bf-9548eb7f5210'

MIGBUCKET_URL='http://10.0.0.211/balenaos'
# MIGBUCKET_URL='https://storage.googleapis.com/balenamigration'
MIGBUCKET_FILETEST='testbucketconnection.file'

function diagExitError {
    touch ${MIGSSTATE_DIR}/MIG_DIAGNOSTIC_FAIL

    [[ -f ${MIGCOMMAND_LOG} ]] && cat ${MIGCOMMAND_LOG}
    
    echo -e "\n\n" | tee -a ${MIGSCRIPT_LOG}
    echo -e "###################" | tee -a ${MIGSCRIPT_LOG}
    echo -e "# DIAGNOSTIC FAIL #" | tee -a ${MIGSCRIPT_LOG}
    echo -e "###################" | tee -a ${MIGSCRIPT_LOG}
    echo -e "\n" | tee -a ${MIGSCRIPT_LOG}
    date | tee -a ${MIGSCRIPT_LOG}
    echo -e "\n\n" | tee -a ${MIGSCRIPT_LOG}
    echo "${BASH_SOURCE[1]##*/}:${FUNCNAME[1]}[${BASH_LINENO[0]}]" | tee -a ${MIGSCRIPT_LOG}
    exit
}

function logCommand {
    echo '{"device":"'"${MIGDID}"'", "stage":"'"${MIGSCRIPT_STAGE}"'", "event":"'"${MIGSCRIPT_EVENT}"'", "state":"'"CMDLOG"'", "msg":"' | \
    cat - ${MIGCOMMAND_LOG} > temp.log && mv temp.log ${MIGCOMMAND_LOG}
    echo '"}' >> ${MIGCOMMAND_LOG} && cat ${MIGCOMMAND_LOG} &>> ${MIGSCRIPT_LOG}

    curl -X POST \
    -d "@${MIGCOMMAND_LOG}" \
    "${MIGWEBLOG_URL}/${MIGWEBLOG_KEYCOMMAND}"
}

function logEvent {
    echo '{"device":"'"${MIGDID}"'", "stage":"'"${MIGSCRIPT_STAGE}"'", "event":"'"${MIGSCRIPT_EVENT}"'", "state":"'"${MIGSCRIPT_STATE}"'", "msg":"'"$1"'"}' | \
    tee -a ${MIGSCRIPT_LOG} /dev/tty | \
    curl -i -H "Accept: application/json" \
    -X POST \
    --data @- \
    "${MIGWEBLOG_URL}/${MIGWEBLOG_KEYEVENT}" &>${MIGCOMMAND_LOG} || logCommand
}

function validateOS {
    MIGSCRIPT_STAGE="Diagnostic"
    MIGSCRIPT_EVENT="Validate OS"
    MIGSCRIPT_STATE="INI"
    logEvent

    if [[ -f '/etc/os-release' ]]; then
        source '/etc/os-release'
    else
        MIGSCRIPT_STATE="FAIL"
        logEvent "/etc/os-release missing"
        >${MIGCOMMAND_LOG}
        diagExitError
    fi    

    if [[ 'raspbian' = ${ID} ]]; then
        MIGSCRIPT_STATE="OK"
        logEvent "raspbian detected: ${PRETTY_NAME}"
    else
        MIGSCRIPT_STATE="FAIL"
        logEvent "Wrong OS: ${ID} / ${PRETTY_NAME}"
        >${MIGCOMMAND_LOG}
        diagExitError
    fi

    MIGSCRIPT_STATE="END"
    logEvent
    return 0
}

# https://www.raspberrypi-spy.co.uk/2012/09/checking-your-raspberry-pi-board-version/
function validateRPI {
    MIGSCRIPT_STAGE="Diagnostic"
    MIGSCRIPT_EVENT="Validate RPI"
    MIGSCRIPT_STATE="INI"
    logEvent

    if [[ -f '/proc/device-tree/model' ]]; then
        MIG_RPI_MODEL=$(cat /proc/device-tree/model)
        MIG_RPI_NAME=$(echo ${MIG_RPI_MODEL} | awk '{print $1 $2}')
        MIG_RPI_VER=$(echo ${MIG_RPI_MODEL} | awk '{print $3}')

        if [[ 'RaspberryPi' == "${MIG_RPI_NAME}" ]] && [[ 3 -eq ${MIG_RPI_VER} ]]; then
            MIGSCRIPT_STATE="OK"
            logEvent "RaspberryPi 3 detected: ${MIG_RPI_MODEL}"
        else
            MIGSCRIPT_STATE="FAIL"
            logEvent "Wrong RPI: ${MIG_RPI_MODEL}"
            >${MIGCOMMAND_LOG}
            diagExitError
        fi

    else
        MIGSCRIPT_STATE="FAIL"
        logEvent "/proc/device-tree/model missing"
        >${MIGCOMMAND_LOG}
        diagExitError
    fi    

    MIGSCRIPT_STATE="END"
    logEvent
    return 0
}

function validateBootPartition {
    MIGSCRIPT_STAGE="Diagnostic"
    MIGSCRIPT_EVENT="Validate Boot Partition"
    MIGSCRIPT_STATE="INI"
    logEvent

    if [[ -b "${MIGBOOT_DEV}" ]]; then
        MIGSCRIPT_STATE="OK"
        logEvent "${MIGBOOT_DEV} detected"
    else
        MIGSCRIPT_STATE="FAIL"
        logEvent "${MIGBOOT_DEV} missing"
        diagExitError
    fi

    # MIGBOOT_MOUNT=$(mount | grep "${MIGBOOT_DEV}.on./boot")
    mount &> ${MIGCOMMAND_LOG} && \
    cat ${MIGCOMMAND_LOG} >> ${MIGSCRIPT_LOG} && \
    cat ${MIGCOMMAND_LOG} | grep "${MIGBOOT_DEV}.on./boot" &>>${MIGSCRIPT_LOG} || \
    {
        MIGSCRIPT_STATE="FAIL";
        logEvent "Boot device do not mounted: ${MIGBOOT_DEV}";
        logCommand;
        diagExitError;
    }
    # if [[ 0 -ne $? ]]; then
    #     MIGSCRIPT_STATE="FAIL"
    #     logEvent "Boot device do not mounted: ${MIGBOOT_DEV}"
    #     mount &> ${MIGCOMMAND_LOG} && cat ${MIGCOMMAND_LOG} >> ${MIGSCRIPT_LOG}
    #     logCommand
    #     diagExitError
    # fi
    
    # fdisk -l ${MIGMMC} 2>&1 | tee ${MIGCOMMAND_LOG}
    # fdisk -l ${MIGMMC} |& tee ${MIGCOMMAND_LOG}
    # logCommand

    fdisk -l ${MIGMMC} &> ${MIGCOMMAND_LOG} && cat ${MIGCOMMAND_LOG} >> ${MIGSCRIPT_LOG} || \
    { logCommand; diagExitError; }

    MIGBOOT_DATA=$(fdisk -l ${MIGMMC} | grep ${MIGBOOT_DEV})
    MIGBOOT_START=$(echo ${MIGBOOT_DATA} | awk '{print $2}')
    MIGBOOT_END=$(echo ${MIGBOOT_DATA} | awk '{print $3}')
    MIGBOOT_SECTORS=$(echo ${MIGBOOT_DATA} | awk '{print $4}')
    MIGBOOT_SIZE=$(echo ${MIGBOOT_DATA} | awk '{print $5}')

    case ${MIGBOOT_SIZE} in
        '40M')
            MIGSCRIPT_STATE="OK"
            logEvent "${MIGBOOT_SIZE} detected"
            if [[ 8192 -eq ${MIGBOOT_START} ]] && [[ 90111 -eq ${MIGBOOT_END} ]] && [[ 81920 -eq ${MIGBOOT_SECTORS} ]]; then
                logEvent "Logical sectors verified: ${MIGBOOT_START} : ${MIGBOOT_END} : ${MIGBOOT_SECTORS}"
                echo "MIGCONFIG_BOOTSIZE=40" >>${MIGCONFIG_FILE}
            else
                MIGSCRIPT_STATE="FAIL"
                logEvent "Logical sectors missmatch: ${MIGBOOT_START} : ${MIGBOOT_END} : ${MIGBOOT_SECTORS}"
                >${MIGCOMMAND_LOG}
                diagExitError
            fi
            ;;

        '60M')
            MIGSCRIPT_STATE="OK"
            logEvent "${MIGBOOT_SIZE} detected"
            if [[ 8192 -eq ${MIGBOOT_START} ]] && [[ 131071 -eq ${MIGBOOT_END} ]] && [[ 122880 -eq ${MIGBOOT_SECTORS} ]]; then
                logEvent "Logical sectors verified: ${MIGBOOT_START} : ${MIGBOOT_END} : ${MIGBOOT_SECTORS}"
                echo "MIGCONFIG_BOOTSIZE=60" >>${MIGCONFIG_FILE}
            else
                MIGSCRIPT_STATE="FAIL"
                logEvent "Logical sectors missmatch: ${MIGBOOT_START} : ${MIGBOOT_END} : ${MIGBOOT_SECTORS}"
                >${MIGCOMMAND_LOG}
                diagExitError
            fi
            ;;

        '256M')
            MIGSCRIPT_STATE="OK"
            logEvent "${MIGBOOT_SIZE} detected"
            if [[ 8192 -eq ${MIGBOOT_START} ]] && [[ 532479 -eq ${MIGBOOT_END} ]] && [[ 524288 -eq ${MIGBOOT_SECTORS} ]]; then
                logEvent "Logical sectors verified: ${MIGBOOT_START} : ${MIGBOOT_END} : ${MIGBOOT_SECTORS}"
                echo "MIGCONFIG_BOOTSIZE=256" >>${MIGCONFIG_FILE}
            else
                MIGSCRIPT_STATE="FAIL"
                logEvent "Logical sectors missmatch: ${MIGBOOT_START} : ${MIGBOOT_END} : ${MIGBOOT_SECTORS}"
                >${MIGCOMMAND_LOG}
                diagExitError
            fi
            ;;

        *)
            MIGSCRIPT_STATE="FAIL"
            logEvent "${MIGBOOT_SIZE} not suported"
            >${MIGCOMMAND_LOG}
            diagExitError
    esac

    MIGSCRIPT_STATE="END"
    logEvent
    return 0
}

function validationNetwork {
    MIGSCRIPT_STAGE="Diagnostic"
    MIGSCRIPT_EVENT="Validate Network conection"
    MIGSCRIPT_STATE="INI"
    logEvent

    if [[ -f '/etc/dhcpcd.conf' ]]; then
        STATIC_IP=$(cat /etc/dhcpcd.conf | grep -vE "^#" | grep -E "static.*ip_address")
        if [[ 0 -eq $? ]]; then 
            MIGNET_IPSTATIC=1
            MIGSCRIPT_STATE="OK"
            logEvent "Static IP detected: ${STATIC_IP}"
        else
            MIGSCRIPT_STATE="OK"
            logEvent "DHCP detected"
        fi
    else
        MIGSCRIPT_STATE="FAIL"
        logEvent "Missing /etc/dhcpcd.conf"
        >${MIGCOMMAND_LOG}
        diagExitError
    fi

    ip a &> ${MIGCOMMAND_LOG} && cat ${MIGCOMMAND_LOG} >> ${MIGSCRIPT_LOG} || \
    { logCommand; diagExitError; }

    ip r &> ${MIGCOMMAND_LOG} && cat ${MIGCOMMAND_LOG} >> ${MIGSCRIPT_LOG} || \
    { logCommand; diagExitError; }

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
                    MIGSCRIPT_STATE="OK"
                    logEvent "Ethernet connection detected: ${interface}"
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
                    MIGSCRIPT_STATE="FAIL"
                    logEvent "No Ethernet connection detected: ${interface}"
                fi
                ;;
            # Wireless
            'wl')
                if [[ 1 -eq $(cat /sys/class/net/${interface}/carrier) ]]; then
                    MIGSCRIPT_STATE="OK"
                    logEvent "Wireless connection detected: ${interface}"
                    echo "MIGCONFIG_WLAN_CONN='UP'" >>${MIGCONFIG_FILE}
                    
                    iwgetid ${interface} --raw &>${MIGCOMMAND_LOG} || { logCommand; diagExitError; }

                    MIGNET_WLANSSID=$(iwgetid ${interface} --raw)

                    if [[ -n ${MIGNET_WLANSSID} ]];then
                        MIGSCRIPT_STATE="OK"
                        logEvent "Wireless SSID detected: ${MIGNET_WLANSSID}"
                        echo "MIGCONFIG_WLAN_SSID='${MIGNET_WLANSSID}'" >>${MIGCONFIG_FILE}
                    else
                        MIGSCRIPT_STATE="FAIL"
                        logEvent "No Wireless SSID detected: ${MIGNET_WLANSSID}"
                    fi

                    cat '/etc/wpa_supplicant/wpa_supplicant.conf' &>${MIGCOMMAND_LOG} && \
                    grep 'psk' ${MIGCOMMAND_LOG} | cut -d '=' -f 2 &>var.tmp && \
                    MIGNET_WLANPSK=$(cat var.tmp) || \
                    { logCommand; diagExitError; }
                    
                    if [[ -n ${MIGNET_WLANPSK} ]];then
                        MIGSCRIPT_STATE="OK"
                        logEvent "Wireless PSK detected: ${MIGNET_WLANPSK//\"}"
                        echo "MIGCONFIG_WLAN_PSK='${MIGNET_WLANPSK//\"}'" >>${MIGCONFIG_FILE}
                    else
                        MIGSCRIPT_STATE="FAIL"
                        logEvent "No Wireless PSK detected: ${MIGNET_WLANPSK}"
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
                    MIGSCRIPT_STATE="FAIL"
                    logEvent "No Wireless connection detected: ${interface}"
                fi
                ;;
            *)
                MIGSCRIPT_STATE="FAIL"
                logEvent "unrecognized network interface: ${interface}"
                ;;
        esac    
    done

    MIGSCRIPT_STATE="END"
    logEvent
    return 0
}

function testIsRoot {
    # Run as root, of course.
    if [[ "$UID" -ne "$ROOT_UID" ]]
    then
        echo -e "[FAIL]\tMust be root to run this script."
        exit $LINENO
    fi
}

function testBucketConnection {
    wget -q --tries=10 --timeout=10 --spider "$MIGBUCKET_URL/$MIGBUCKET_FILETEST"

    if [[ $? -ne 0 ]]; then
        echo "[FAIL]\tNo connection to the bucket server detected"
        echo "Is necessary a connection to the bucket server to run this script."
        exit $LINENO
    fi
}

function iniDiagnostic {
    MIGSCRIPT_STAGE="Diagnostic"
    MIGSCRIPT_EVENT="migDiagnostic.sh"
    MIGSCRIPT_STATE="INI"

    testIsRoot
    testBucketConnection

    mkdir -p ${MIGSSTATE_DIR} && [[ -d ${MIGSSTATE_DIR} ]] && cd ${MIGSSTATE_DIR} || \
    {
        echo "[FAIL]\t Can't create ${MIGSSTATE_DIR}"
        exit $LINENO
    }

    echo -e "\n\n" | tee -a ${MIGSCRIPT_LOG}
    echo -e "******************" | tee -a ${MIGSCRIPT_LOG}
    echo -e "* DIAGNOSTIC INI *" | tee -a ${MIGSCRIPT_LOG}
    echo -e "******************" | tee -a ${MIGSCRIPT_LOG}
    echo -e "" | tee -a ${MIGSCRIPT_LOG}
    date | tee -a ${MIGSCRIPT_LOG}
    echo -e "" | tee -a ${MIGSCRIPT_LOG}

    logEvent

    [[ -f ${MIGSSTATE_DIR}/MIG_DIAGNOSTIC_FAIL ]] && rm ${MIGSSTATE_DIR}/MIG_DIAGNOSTIC_FAIL
    [[ -f ${MIGSSTATE_DIR}/MIG_DIAGNOSTIC_SUCCESS ]] && rm ${MIGSSTATE_DIR}/MIG_DIAGNOSTIC_SUCCESS

    >${MIGCONFIG_FILE} &>${MIGCOMMAND_LOG} && echo "MIGCONFIG_DID='${MIGDID}'" >${MIGCONFIG_FILE} || \
    { logCommand; diagExitError; }

    validateOS
    validateRPI
    validateBootPartition
    validationNetwork

    touch ${MIGSSTATE_DIR}/MIG_DIAGNOSTIC_SUCCESS

    MIGSCRIPT_STAGE="Diagnostic"
    MIGSCRIPT_EVENT="migDiagnostic.sh"
    MIGSCRIPT_STATE="END"
    logEvent

    echo -e "\n" | tee -a ${MIGSCRIPT_LOG}
    cat ${MIGCONFIG_FILE} | tee -a ${MIGSCRIPT_LOG}
    echo -e "" | tee -a ${MIGSCRIPT_LOG}
    date | tee -a ${MIGSCRIPT_LOG}
    echo -e "" | tee -a ${MIGSCRIPT_LOG}
    echo -e "**********************" | tee -a ${MIGSCRIPT_LOG}
    echo -e "* DIAGNOSTIC SUCCESS *" | tee -a ${MIGSCRIPT_LOG}
    echo -e "**********************" | tee -a ${MIGSCRIPT_LOG}
    echo -e "\n\n" | tee -a ${MIGSCRIPT_LOG}
}

iniDiagnostic

echo $LINENO
exit 0