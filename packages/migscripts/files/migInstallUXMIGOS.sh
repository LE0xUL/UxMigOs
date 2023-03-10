#!/bin/bash

MIGTIME_INI="$(cat /proc/uptime | grep -o '^[0-9]\+')"
MIGDID="$(hostname)"

[[ 0 -ne $? ]] && { echo "[FAIL] Can't set MIGDID"; exit $LINENO; }

: ${FILE_UXMIGOS_BOOT:=migboot-uxmigos-balena.tgz}
: ${MIGURL_BUCKET:=https://storage.googleapis.com/balenamigration/32b/}

MIGLOG_SCRIPTNAME="migInstallUXMIGOS.sh"
MIGSSTATEDIR_BOOT="/boot/migstate"
MIGSSTATEDIR_ROOT="/root/migstate"
MIGSSTATE_DIR="${MIGSSTATEDIR_ROOT}"
MIGDOWN_DIR="/root/migdownloads"

MIGCOMMAND_LOG="${MIGSSTATE_DIR}/cmd.log"
MIGSCRIPT_LOG="${MIGSSTATE_DIR}/migInstallUXMIGOS.log"
MIGCONFIG_FILE="${MIGSSTATE_DIR}/mig.config"
MIGMMC="/dev/mmcblk0"
MIGBOOT_DEV='/dev/mmcblk0p1'
MIGBOOT_DIR='/boot'
FILE_BACKUP_BOOT="mig-backup-boot.tgz"

UXMIGOS_RASPBIAN_BOOT_FILE="/boot/UXMIGOS_RASPBIAN_BOOT_${MIGDID}"
UXMIGOS_INSTALLED_BOOT_FILE="/boot/UXMIGOS_BOOT_INSTALLED"

MIGNET_SYSTEMD_EN_FILE="${MIGSSTATE_DIR}/en.network"
MIGNET_SYSTEMD_WLAN0_FILE="${MIGSSTATE_DIR}/wlan0.network"
MIGNET_RESIN_WLAN_FILE="${MIGSSTATE_DIR}/resin-wlan"
MIGNET_RESIN_ETH_FILE="${MIGSSTATE_DIR}/resin-ethernet"
MIGNET_RESIN_3G_FILE="${MIGSSTATE_DIR}/resin-3g"

MIGFILE_BALENAWF_CONFIG_JSON="appBalena.config.json"
MIGFILE_BALENA3G_CONFIG_JSON="appBalena3G.config.json"
MIGFILE_JQ_PACKAGE="jq_1.4-2.1+deb8u1_armhf.deb"

MIGWEBLOG_URL='https://eu.webhook.logs.insight.rapid7.com/v1/noformat'
MIGWEBLOG_KEYEVENT='f79248d1-bbe0-427b-934b-02a2dee5f24f'
MIGWEBLOG_KEYCOMMAND='642de669-cf83-4e19-a6bf-9548eb7f5210'

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
    MIGLOG_FILEPUSH_URLLOG=$(curl -k --upload-file "${MIGSCRIPT_LOG}" https://filepush.co/upload/)
    logEvent "INFO" "${MIGLOG_FILEPUSH_URLLOG}"
    echo "${MIGLOG_FILEPUSH_URLLOG}"
}

function restoreRaspbianBoot {
    logEvent "INI"

    if [[ -f ${MIGSSTATE_DIR}/MIG_UXMIGOS_IN_BOOT_OK ]] || [[ -f ${UXMIGOS_INSTALLED_BOOT_FILE} ]]; then
        if [[ -f /root/${FILE_BACKUP_BOOT} ]];then
            execCmmd "rm -vrf ${MIGBOOT_DIR}/*" logSuccess && \
            execCmmd "tar -xzvf /root/${FILE_BACKUP_BOOT} -C ${MIGBOOT_DIR}" logSuccess && \
            execCmmd "rm -vf ${MIGSSTATE_DIR}/MIG_INSTALL_UXMIGOS_SUCCESS" logSuccess && \
            execCmmd "rm -vf ${MIGSSTATE_DIR}/MIG_UXMIGOS_IN_BOOT_OK"  logSuccess && \
            logEvent "OK" "Restaured Raspbian Backup in boot partition" || \
            logEvent "FAIL" "Can't restore Raspbian Backup in boot partition"
        else
            logEvent "FAIL" "Missing Raspbian BackUp File: /root/${FILE_BACKUP_BOOT}"
        fi
    fi

    logEvent "END"
}

# USE: exitError MESSAGE
function exitError {
    touch ${MIGSSTATE_DIR}/MIG_INSTALL_UXMIGOS_FAIL
    MIGEXIT_LOGMSG="${1:-INSTALL_UXMIGOS_FAIL}"
    MIGEXIT_PARAM2=$2
    MIGEXIT_PARAM3=$3

    [[ "logCommand" == "${MIGEXIT_PARAM2}" ]] && logCommand "${MIGEXIT_LOGMSG}" "${FUNCNAME[1]}" "${BASH_LINENO[0]}"
    [[ "restoreRaspbianBoot" == "${MIGEXIT_PARAM2}" ]] && restoreRaspbianBoot
    [[ "restoreRaspbianBoot" == "${MIGEXIT_PARAM3}" ]] && restoreRaspbianBoot


    logEvent "EXIT" "${MIGEXIT_LOGMSG}" "${FUNCNAME[1]}" "${BASH_LINENO[0]}"
    
    echo "" &>>${MIGSCRIPT_LOG}
    date |& tee -a ${MIGSCRIPT_LOG}
    echo "[ ####    INSTALL UXMIGOS FAIL    #### ]" |& tee -a ${MIGSCRIPT_LOG}
    echo "" &>>${MIGSCRIPT_LOG}
    echo "${MIGLOG_SCRIPTNAME}:${FUNCNAME[1]}[${BASH_LINENO[0]}] ${MIGEXIT_LOGMSG}" |& tee -a ${MIGSCRIPT_LOG}

    logFilePush
    rm -vf ${MIGSSTATE_DIR}/MIG_INSTALL_UXMIGOS_IS_RUNING
    exit $LINENO
}

function backupBootPartition {
    logEvent "INI"

    [[ -f ${UXMIGOS_RASPBIAN_BOOT_FILE} ]] && \
    logEvent "OK" "Validated Raspbian boot partition" || \
    exitError "Missing validation Raspbian boot file: ${UXMIGOS_RASPBIAN_BOOT_FILE}"

    if [[ -f /root/${FILE_BACKUP_BOOT} ]]; then
        logEvent "INFO" "Raspbian boot backup file was detected in the system: ${FILE_BACKUP_BOOT}"
    else
        execCmmd "cd ${MIGBOOT_DIR} && tar -czvf /root/${FILE_BACKUP_BOOT} ." logSuccess && \
        logEvent "OK" "Created boot backup file: /root/${FILE_BACKUP_BOOT}" || \
        exitError "FAIL at make raspbian boot backup file: /root/${FILE_BACKUP_BOOT}"
    fi
    
    logEvent "END"
}

function uxmigos2Boot {
    logEvent "INI"

    execCmmd "rm -vfr ${MIGBOOT_DIR}/*" logSuccess || \
    exitError "Fail at exec: rm -vfr ${MIGBOOT_DIR}/*" restoreRaspbianBoot

    execCmmd "tar -xzvf ${MIGDOWN_DIR}/${FILE_UXMIGOS_BOOT} -C ${MIGBOOT_DIR}" logSuccess || \
    exitError "tar -xzvf ${MIGDOWN_DIR}/${FILE_UXMIGOS_BOOT} -C ${MIGBOOT_DIR}" restoreRaspbianBoot

    execCmmd "touch ${MIGSSTATE_DIR}/MIG_UXMIGOS_IN_BOOT_OK" logSuccess || \
    exitError "touch ${MIGSSTATE_DIR}/MIG_UXMIGOS_IN_BOOT_OK" restoreRaspbianBoot
    
    logEvent "OK" "Installed UXMIGOS in boot partition"
    
    execCmmd "ls -alh ${MIGBOOT_DIR}" logCommand

    logEvent "END"
}

function makeNetFilesSystemd {
    logEvent "INI"

    if [[ 'NO' == "${MIGCONFIG_ETH_DHCP}" ]];then
        execCmmd "echo [match] >${MIGNET_SYSTEMD_EN_FILE}" && \
        execCmmd "echo Name=en* >>${MIGNET_SYSTEMD_EN_FILE}" && \
        execCmmd "echo [Network] >>${MIGNET_SYSTEMD_EN_FILE}" || \
        exitError "Can't create ${MIGNET_SYSTEMD_EN_FILE}"
        
        if [[ -n ${MIGCONFIG_ETH_IPMASK} ]];then
            execCmmd "echo 'Address=${MIGCONFIG_ETH_IPMASK}' >>${MIGNET_SYSTEMD_EN_FILE}" || \
            exitError "Can't append to ${MIGNET_SYSTEMD_EN_FILE}"
        else
            exitError "Missing MIGCONFIG_ETH_IPMASK"
        fi

        if [[ -n ${MIGCONFIG_ETH_GWIP} ]];then
            execCmmd "echo 'Gateway=${MIGCONFIG_ETH_GWIP}' >>${MIGNET_SYSTEMD_EN_FILE}" || \
            exitError "Can't append to ${MIGNET_SYSTEMD_EN_FILE}"
        else
            exitError "Missing MIGCONFIG_ETH_GWIP"
        fi

        if [[ -n ${MIGCONFIG_ETH_DNSIP} ]];then
            execCmmd "echo 'DNS=${MIGCONFIG_ETH_DNSIP}' >>${MIGNET_SYSTEMD_EN_FILE}" || \
            exitError "Can't append to ${MIGNET_SYSTEMD_EN_FILE}"
        else
            exitError "Missing MIGCONFIG_ETH_DNSIP"
        fi

        logEvent "OK" "Created ethernet static IP config file: ${MIGNET_SYSTEMD_EN_FILE}"

        execCmmd "cat ${MIGNET_SYSTEMD_EN_FILE}" logCommand
    fi

    if [[ 'NO' == "${MIGCONFIG_WLAN_DHCP}" ]];then
        execCmmd "echo '[match]' >${MIGNET_SYSTEMD_WLAN0_FILE}" && \
        execCmmd "echo 'Name=en*' >>${MIGNET_SYSTEMD_WLAN0_FILE}" && \
        execCmmd "echo '[Network]' >>${MIGNET_SYSTEMD_WLAN0_FILE}" || \
        exitError "Can't append to ${MIGNET_SYSTEMD_WLAN0_FILE}"
        
        if [[ -n ${MIGCONFIG_WLAN_IPMASK} ]];then
            execCmmd "echo 'Address=${MIGCONFIG_WLAN_IPMASK}' >>${MIGNET_SYSTEMD_WLAN0_FILE}" || \
            exitError "Can't append to ${MIGNET_SYSTEMD_WLAN0_FILE}"
        else
            exitError "Missing MIGCONFIG_WLAN_IPMASK"
        fi

        if [[ -n ${MIGCONFIG_WLAN_GWIP} ]];then
            execCmmd "echo 'Gateway=${MIGCONFIG_WLAN_GWIP}' >>${MIGNET_SYSTEMD_WLAN0_FILE}" || \
            exitError "Can't append to ${MIGNET_SYSTEMD_WLAN0_FILE}"
        else
            exitError "Missing MIGCONFIG_WLAN_GWIP"
        fi

        if [[ -n ${MIGCONFIG_WLAN_DNSIP} ]];then
            execCmmd "echo 'DNS=${MIGCONFIG_WLAN_DNSIP}' >>${MIGNET_SYSTEMD_WLAN0_FILE}" || \
            exitError "Can't append to ${MIGNET_SYSTEMD_WLAN0_FILE}"
        else
            exitError "Missing MIGCONFIG_WLAN_DNSIP"
        fi

        logEvent "OK" "Created wireless static IP config file: ${MIGNET_SYSTEMD_WLAN0_FILE}"

        execCmmd "cat ${MIGNET_SYSTEMD_WLAN0_FILE}" logCommand
    fi

    logEvent "END"
}

# https://www.balena.io/docs/reference/OS/network/2.x/
# https://developer.gnome.org/NetworkManager/stable/nm-settings-keyfile.html
# https://developer.gnome.org/NetworkManager/stable/nm-settings.html
function makeNetFilesResin {
    logEvent "INI"

    if [[ 'NO' == "${MIGCONFIG_ETH_DHCP}" ]];then
        [[ -n ${MIGCONFIG_ETH_IPMASK} ]] && \
        [[ -n ${MIGCONFIG_ETH_GWIP} ]] && \
        [[ -n ${MIGCONFIG_ETH_DNSIP} ]] && \
        execCmmd "echo '[connection]' >${MIGNET_RESIN_ETH_FILE}" && \
        execCmmd "echo 'id=resin-ethernet' >>${MIGNET_RESIN_ETH_FILE}" && \
        execCmmd "echo 'type=ethernet' >>${MIGNET_RESIN_ETH_FILE}" && \
        execCmmd "echo 'interface-name=eth0' >>${MIGNET_RESIN_ETH_FILE}" && \
        execCmmd "echo 'permissions=' >>${MIGNET_RESIN_ETH_FILE}" && \
        execCmmd "echo 'secondaries=' >>${MIGNET_RESIN_ETH_FILE}" && \
        execCmmd "echo '' >>${MIGNET_RESIN_ETH_FILE}" && \
        execCmmd "echo '[ethernet]' >>${MIGNET_RESIN_ETH_FILE}" && \
        execCmmd "echo 'mac-address-blacklist=' >>${MIGNET_RESIN_ETH_FILE}" && \
        execCmmd "echo '' >>${MIGNET_RESIN_ETH_FILE}" && \
        execCmmd "echo '[ipv4]' >>${MIGNET_RESIN_ETH_FILE}" && \
        execCmmd "echo 'address1=${MIGCONFIG_ETH_IPMASK},${MIGCONFIG_ETH_GWIP}' >>${MIGNET_RESIN_ETH_FILE}" && \
        execCmmd "echo 'dns=${MIGCONFIG_ETH_DNSIP};' >>${MIGNET_RESIN_ETH_FILE}" && \
        execCmmd "echo 'dns-search=' >>${MIGNET_RESIN_ETH_FILE}" && \
        execCmmd "echo 'method=manual' >>${MIGNET_RESIN_ETH_FILE}" && \
        execCmmd "echo '' >>${MIGNET_RESIN_ETH_FILE}" && \
        execCmmd "echo '[ipv6]' >>${MIGNET_RESIN_ETH_FILE}" && \
        execCmmd "echo 'addr-gen-mode=stable-privacy' >>${MIGNET_RESIN_ETH_FILE}" && \
        execCmmd "echo 'dns-search=' >>${MIGNET_RESIN_ETH_FILE}" && \
        execCmmd "echo 'method=auto' >>${MIGNET_RESIN_ETH_FILE}" && \
        execCmmd "cat ${MIGNET_RESIN_ETH_FILE}" logCommand && \
        logEvent "OK" "Created resin ethernet file: ${MIGNET_RESIN_ETH_FILE}" || \
        exitError "FAIL at create resin ethernet file: ${MIGNET_RESIN_ETH_FILE}"
    fi

    if [[ 'UP' == "${MIGCONFIG_WLAN_CONN}" ]] && [[ 'YES' == "${MIGCONFIG_WLAN_DHCP}" ]]; then
        [[ -n ${MIGCONFIG_WLAN_SSID} ]] && \
        [[ -n ${MIGCONFIG_WLAN_PSK} ]] && \
        execCmmd "echo '[connection]' >${MIGNET_RESIN_WLAN_FILE}" && \
        execCmmd "echo 'id=resin-wlan' >>${MIGNET_RESIN_WLAN_FILE}" && \
        execCmmd "echo 'type=wifi' >>${MIGNET_RESIN_WLAN_FILE}" && \
        execCmmd "echo '' >>${MIGNET_RESIN_WLAN_FILE}" && \
        execCmmd "echo '[wifi]' >>${MIGNET_RESIN_WLAN_FILE}" && \
        execCmmd "echo 'hidden=true' >>${MIGNET_RESIN_WLAN_FILE}" && \
        execCmmd "echo 'mode=infrastructure' >>${MIGNET_RESIN_WLAN_FILE}" && \
        execCmmd "echo 'ssid=${MIGCONFIG_WLAN_SSID}' >>${MIGNET_RESIN_WLAN_FILE}" && \
        execCmmd "echo '' >>${MIGNET_RESIN_WLAN_FILE}" && \
        execCmmd "echo '[ipv4]' >>${MIGNET_RESIN_WLAN_FILE}" && \
        execCmmd "echo 'method=auto' >>${MIGNET_RESIN_WLAN_FILE}" && \
        execCmmd "echo '' >>${MIGNET_RESIN_WLAN_FILE}" && \
        execCmmd "echo '[ipv6]' >>${MIGNET_RESIN_WLAN_FILE}" && \
        execCmmd "echo 'addr-gen-mode=stable-privacy' >>${MIGNET_RESIN_WLAN_FILE}" && \
        execCmmd "echo 'method=auto' >>${MIGNET_RESIN_WLAN_FILE}" && \
        execCmmd "echo '' >>${MIGNET_RESIN_WLAN_FILE}" && \
        execCmmd "echo '[wifi-security]' >>${MIGNET_RESIN_WLAN_FILE}" && \
        execCmmd "echo 'auth-alg=open' >>${MIGNET_RESIN_WLAN_FILE}" && \
        execCmmd "echo 'key-mgmt=wpa-psk' >>${MIGNET_RESIN_WLAN_FILE}" && \
        execCmmd "echo 'psk=${MIGCONFIG_WLAN_PSK}' >>${MIGNET_RESIN_WLAN_FILE}" && \
        execCmmd "cat ${MIGNET_RESIN_WLAN_FILE}" logCommand && \
        logEvent "OK" "Created resin wlan file: ${MIGNET_RESIN_WLAN_FILE}" || \
        exitError "FAIL at create resin wlan file: ${MIGNET_RESIN_WLAN_FILE}"
    elif [[ 'UP' == "${MIGCONFIG_WLAN_CONN}" ]] && [[ 'NO' == "${MIGCONFIG_WLAN_DHCP}" ]];then
        [[ -n ${MIGCONFIG_WLAN_SSID} ]] && \
        [[ -n ${MIGCONFIG_WLAN_PSK} ]] && \
        [[ -n ${MIGCONFIG_WLAN_IPMASK} ]] && \
        [[ -n ${MIGCONFIG_WLAN_GWIP} ]] && \
        [[ -n ${MIGCONFIG_WLAN_DNSIP} ]] && \
        execCmmd "echo '[connection]' >${MIGNET_RESIN_WLAN_FILE}" && \
        execCmmd "echo 'id=resin-wlan' >>${MIGNET_RESIN_WLAN_FILE}" && \
        execCmmd "echo 'type=wifi' >>${MIGNET_RESIN_WLAN_FILE}" && \
        execCmmd "echo '' >>${MIGNET_RESIN_WLAN_FILE}" && \
        execCmmd "echo '[wifi]' >>${MIGNET_RESIN_WLAN_FILE}" && \
        execCmmd "echo 'hidden=true' >>${MIGNET_RESIN_WLAN_FILE}" && \
        execCmmd "echo 'mode=infrastructure' >>${MIGNET_RESIN_WLAN_FILE}" && \
        execCmmd "echo 'ssid=${MIGCONFIG_WLAN_SSID}' >>${MIGNET_RESIN_WLAN_FILE}" && \
        execCmmd "echo '' >>${MIGNET_RESIN_WLAN_FILE}" && \
        execCmmd "echo '[ipv4]' >>${MIGNET_RESIN_WLAN_FILE}" && \
        execCmmd "echo 'address1=${MIGCONFIG_WLAN_IPMASK},${MIGCONFIG_WLAN_GWIP}' >>${MIGNET_RESIN_WLAN_FILE}" && \
        execCmmd "echo 'dns=${MIGCONFIG_WLAN_DNSIP};' >>${MIGNET_RESIN_WLAN_FILE}" && \
        execCmmd "echo 'dns-search=' >>${MIGNET_RESIN_WLAN_FILE}" && \
        execCmmd "echo 'method=manual' >>${MIGNET_RESIN_WLAN_FILE}" && \
        execCmmd "echo '' >>${MIGNET_RESIN_WLAN_FILE}" && \
        execCmmd "echo '[ipv6]' >>${MIGNET_RESIN_WLAN_FILE}" && \
        execCmmd "echo 'addr-gen-mode=stable-privacy' >>${MIGNET_RESIN_WLAN_FILE}" && \
        execCmmd "echo 'method=auto' >>${MIGNET_RESIN_WLAN_FILE}" && \
        execCmmd "echo '' >>${MIGNET_RESIN_WLAN_FILE}" && \
        execCmmd "echo '[wifi-security]' >>${MIGNET_RESIN_WLAN_FILE}" && \
        execCmmd "echo 'auth-alg=open' >>${MIGNET_RESIN_WLAN_FILE}" && \
        execCmmd "echo 'key-mgmt=wpa-psk' >>${MIGNET_RESIN_WLAN_FILE}" && \
        execCmmd "echo 'psk=${MIGCONFIG_WLAN_PSK}' >>${MIGNET_RESIN_WLAN_FILE}" && \
        execCmmd "cat ${MIGNET_RESIN_WLAN_FILE}" logCommand && \
        logEvent "OK" "Created resin wlan file: ${MIGNET_RESIN_WLAN_FILE}" || \
        exitError "FAIL at create resin wlan file: ${MIGNET_RESIN_WLAN_FILE}"
    fi

    MODEM3G_STATUSFILE='/usr/local/share/admobilize-adbeacon-software/public/files/status'

    execCmmd "MODEM3G_ENABLED=$(jq '.modem.value.enabled' ${MODEM3G_STATUSFILE})"

    if [[ 'UP' == "${MIGCONFIG_3G_CONN}" ]] && [[ "true" == "${MODEM3G_ENABLED}" ]]; then
        logEvent "OK" "3G modem Detected"

        execCmmd "MODEM3G_CARRIER_NAME=$(jq '.modem.value.carrier.name' ${MODEM3G_STATUSFILE})"
        execCmmd "MODEM3G_CARRIER_APN=$(jq '.modem.value.carrier.apn.value' ${MODEM3G_STATUSFILE})"
        
        [[ -n ${MODEM3G_CARRIER_NAME} ]] && \
        [[ -n ${MODEM3G_CARRIER_APN} ]] && \
        execCmmd "echo '[connection]' >${MIGNET_RESIN_3G_FILE}" && \
        execCmmd "echo 'id=${MODEM3G_CARRIER_NAME}' >>${MIGNET_RESIN_3G_FILE}" && \
        execCmmd "echo 'type=gsm' >>${MIGNET_RESIN_3G_FILE}" && \
        execCmmd "echo '' >>${MIGNET_RESIN_3G_FILE}" && \
        execCmmd "echo '[gsm]' >>${MIGNET_RESIN_3G_FILE}" && \
        execCmmd "echo 'apn=${MODEM3G_CARRIER_APN}' >>${MIGNET_RESIN_3G_FILE}" && \
        execCmmd "echo '' >>${MIGNET_RESIN_3G_FILE}" && \
        execCmmd "echo '[ipv4]' >>${MIGNET_RESIN_3G_FILE}" && \
        execCmmd "echo 'method=auto' >>${MIGNET_RESIN_3G_FILE}" && \
        execCmmd "echo '' >>${MIGNET_RESIN_3G_FILE}" && \
        execCmmd "echo '[ipv6]' >>${MIGNET_RESIN_3G_FILE}" && \
        execCmmd "echo 'addr-gen-mode=stable-privacy' >>${MIGNET_RESIN_3G_FILE}" && \
        execCmmd "echo 'method=auto' >>${MIGNET_RESIN_3G_FILE}" && \
        execCmmd "cat ${MIGNET_RESIN_3G_FILE}" logCommand && \
        logEvent "OK" "Created resin 3G file: ${MIGNET_RESIN_3G_FILE}" || \
        exitError "FAIL at create resin 3G file: ${MIGNET_RESIN_3G_FILE}"
    
    elif [[ 'UP' == "${MIGCONFIG_3G_CONN}" ]] && [[ "true" != "${MODEM3G_ENABLED}" ]]; then
        exitError "3G config not detected"
    fi

    logEvent "END"
}

function backupFile {
    MIGBKP_FILENAME=$(echo "$1" | awk '{n=split($1,A,"/"); print A[n]}')
    
    if [[ -f "$1" ]]; then
        cp -v "$1" "${MIGSSTATE_DIR}/${MIGBKP_FILENAME}.bkp" &>${MIGCOMMAND_LOG} && \
        cat ${MIGCOMMAND_LOG} >> ${MIGSCRIPT_LOG} && \
        logEvent "OK" "Backup of ${MIGBKP_FILENAME}" || \
        exitError "ERROR to backup ${MIGBKP_FILENAME}" logCommand
    else
        exitError "Missing file $1"
    fi
}

function backupSystemFiles {
    logEvent "INI"

    backupFile '/etc/network/interfaces'
    backupFile '/etc/hostname'
    backupFile '/usr/local/share/admobilize-adbeacon-software/config/json/device.json'
    backupFile '/usr/local/share/admobilize-adbeacon-software/public/files/status'

    if [[ 'UP' == "${MIGCONFIG_3G_CONN}" ]]; then
        backupFile '/usr/local/share/admobilize-adbeacon-software/public/files/carrierFile'
    fi

    [[ 'UP' == "${MIGCONFIG_WLAN_CONN}" ]] && \
    backupFile '/etc/wpa_supplicant/wpa_supplicant.conf'
    
    if [[ 'NO' == "${MIGCONFIG_ETH_DHCP}" ]] || [[ 'NO' == "${MIGCONFIG_WLAN_DHCP}" ]];then
        backupFile '/etc/dhcpcd.conf'
    fi

    logEvent "END"
}

# USE: migDownFile URL FILENAME DESTINATION
function migDownFile {
    MIGDOWN_URL=$1
    MIGDOWN_FILENAME=$2
    MIGDOWN_DIRECTORY=$3
    MIGDOWN_ATTEMPTNUM=0
    MIGDOWN_ATTEMPTMAX=2

    logEvent "INFO" "Downloading ${MIGDOWN_FILENAME}"
    
    until $(wget "${MIGDOWN_URL}${MIGDOWN_FILENAME}" -O ${MIGDOWN_DIRECTORY}/${MIGDOWN_FILENAME} &>${MIGCOMMAND_LOG}); do
        if [ ${MIGDOWN_ATTEMPTNUM} -eq ${MIGDOWN_ATTEMPTMAX} ];then
            logCommand "Can't download ${MIGDOWN_FILENAME}"
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
        "${MIGFILE_BALENAWF_CONFIG_JSON}" \
        "${MIGFILE_BALENA3G_CONFIG_JSON}" \
        "${FILE_UXMIGOS_BOOT}" \
        "${MIGFILE_JQ_PACKAGE}" \
        "${MIGCONFIG_IMG2FLASH}" \
        'config3G.txt' \
        'cmdline3G.txt' \        
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
                migDownFile ${MIGURL_BUCKET} ${fileName} ${MIGDOWN_DIR} || \
                exitError "Can't download ${fileName}" logCommand
            else
                logEvent "INFO" "Found ${fileName} in ${MIGDOWN_DIR}";
            fi

            migDownFile ${MIGURL_BUCKET} ${fileName}.md5 ${MIGDOWN_DIR} || \
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
    done

    logEvent "END"
}

# https://stedolan.github.io/jq/manual/
# https://stedolan.github.io/jq/tutorial/
# https://stedolan.github.io/jq/
# https://github.com/balena-io/balenaos-masterclass
# https://www.balena.io/docs/reference/OS/configuration/
function makeBalenaConfigJson {
    logEvent "INI"

    DEVICE_ID="$(cat /sys/class/net/eth0/address | tr -d ':')"
    [[ 0 -ne $? ]] && exitError "Can't set DEVICE_ID"

    if [[ 'UP' == "${MIGCONFIG_3G_CONN}" ]];then
        MIGFILE_BALENA_CONFIG_JSON=${MIGFILE_BALENA3G_CONFIG_JSON}
        logEvent "OK" "Base config.json is ${MIGFILE_BALENA_CONFIG_JSON}"
    else
        MIGFILE_BALENA_CONFIG_JSON=${MIGFILE_BALENAWF_CONFIG_JSON}
        logEvent "OK" "Base config.json is ${MIGFILE_BALENA_CONFIG_JSON}"
    fi

    if [[ -f ${MIGDOWN_DIR}/${MIGFILE_BALENA_CONFIG_JSON} ]]; then
        execCmmd "jq '.+ {\"hostname\": \"${DEVICE_ID}\"}' ${MIGDOWN_DIR}/${MIGFILE_BALENA_CONFIG_JSON} > ${MIGSSTATE_DIR}/appBalena.config.json" && \
        logEvent "OK" "Created ${MIGSSTATE_DIR}/appBalena.config.json" || \
        exitError "Can't create ${MIGSSTATE_DIR}/appBalena.config.json"
    else
        exitError "Missing ${MIGDOWN_DIR}/${MIGFILE_BALENA_CONFIG_JSON}"
    fi

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

    [[ ${MIGTIMESTAMP_DIFFERENCE} -gt 1200 ]] && \
    exitError "'Diagnostic' is too old. Please, run it again."

    logEvent "OK" "Valid MIG_DIAGNOSTIC_SUCCESS"
    logEvent "END"
}

function testJQ {
    logEvent "INI"

    execCmmd "jq --version" logSuccess && \
    logEvent "OK" "jq is installed" || \
    {
        logEvent "INFO" "jq not detected. Try to install it" 
        execCmmd "dpkg -i ${MIGDOWN_DIR}/${MIGFILE_JQ_PACKAGE}" logSuccess && \
        logEvent "OK" "jq was installed" || \
        exitError "Fail at install jq"
    }

    logEvent "END"
}

function testMigState {
    logEvent "INI"
    
    if [[ ! -f ${MIGSSTATE_DIR}/MIG_DIAGNOSTIC_SUCCESS ]]; then
        exitError "[FAIL] Is necessary run first the Diagnostic script with success result."
    elif [[ -f ${MIGSSTATE_DIR}/MIG_INSTALL_UXMIGOS_SUCCESS ]] && [[ -f ${UXMIGOS_INSTALLED_BOOT_FILE} ]]; then
        exitError "UXMIGOS is already installed in the system. Reboot the system to initiate the migration process"
    elif [[ -f ${UXMIGOS_INSTALLED_BOOT_FILE} ]]; then
        exitError "[FAIL] UXMIGOS_BOOT is present in the system"
    elif [[ -f ${MIGSSTATE_DIR}/MIG_INSTALL_UXMIGOS_SUCCESS ]]; then
        exitError "[FAIL] INSTALL UXMIGOS was SUCCESS but UXMIGOS_BOOT is not present in the system"
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
    wget -q --tries=10 --timeout=10 --spider "${MIGURL_BUCKET}$MIGBUCKET_FILETEST"

    if [[ $? -ne 0 ]]; then
        echo "[FAIL] No connection to the bucket server detected"
        echo "Is necessary a connection to the bucket server to run this script."
        exit $LINENO
    else
        echo "[OK] Network"
    fi
}

function testInstallUxMigOsRunning {
    sleep 0.$[ ( $RANDOM % 10 ) ]s
    
    if [[ -f ${MIGSSTATE_DIR}/MIG_INSTALL_UXMIGOS_IS_RUNING ]]
    then
        echo "[FAIL] Another Install UXMIGOS script is running"
        exit $LINENO
    fi
}

function iniUxMigOsInstall {
    testIsRoot
    testBucketConnection
    testInstallUxMigOsRunning

    mkdir -vp ${MIGSSTATE_DIR}
    touch ${MIGSSTATE_DIR}/MIG_INSTALL_UXMIGOS_IS_RUNING

    echo "" &>>${MIGSCRIPT_LOG}
    echo "" &>>${MIGSCRIPT_LOG}
    echo "[ ####    INSTALL UXMIGOS INI    #### ]" |& tee -a ${MIGSCRIPT_LOG}
    date |& tee -a ${MIGSCRIPT_LOG}
    logEvent "INI"

    rm -vf  ${MIGSSTATE_DIR}/MIG_INSTALL_UXMIGOS_FAIL &>>${MIGSCRIPT_LOG} || exitError

    testMigState
    validateDiagnostic
    backupBootPartition

    source ${MIGCONFIG_FILE} &>${MIGCOMMAND_LOG} || \
    exitError "FAIL at exec: source ${MIGCONFIG_FILE}" logCommand

    downFilesFromBucket
    testJQ
    backupSystemFiles
    makeNetFilesSystemd
    makeNetFilesResin

    makeBalenaConfigJson
    uxmigos2Boot
    migState2Boot

    touch ${MIGSSTATE_DIR}/MIG_INSTALL_UXMIGOS_SUCCESS

    logEvent "SUCCESS" "TOTAL TIME: $(( $(cat /proc/uptime | grep -o '^[0-9]\+') - ${MIGTIME_INI} )) seconds"

    echo "" &>>${MIGSCRIPT_LOG}
    date | tee -a ${MIGSCRIPT_LOG}
    echo "[ ####    INSTALL UXMIGOS SUCCESS    #### ]" |& tee -a ${MIGSCRIPT_LOG}
    
    cp ${MIGSCRIPT_LOG} ${MIGBOOT_DIR} |& tee -a ${MIGSCRIPT_LOG}
    logFilePush
    rm -vf ${MIGSSTATE_DIR}/MIG_INSTALL_UXMIGOS_IS_RUNING
    echo "reboot"
    # shutdown -r now
    # shutdown -r +1
}

iniUxMigOsInstall

echo $LINENO
exit 0
