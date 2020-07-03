#!/bin/bash

MIGLOG_SCRIPTNAME=$(basename "$0")
MIGSCRIPT_LOG="provider.log"
MIGCOMMAND_LOG="cmdprovider.log"
MIGDID=""

MIGTOKEN_BALENACLOUD="ErR56DEPe87jpjKaTg8JDPMORRD8F44A"
MIGFILE_DEVICESLIST="devlist.txt"
MIGFILE_DEVICEINFO="devinfo.txt"
MIGFILE_TOKENLIST="devices_migrated.csv"

MIG_BALENA_APP_INIT="BalenaMigration"
MIG_BALENA_APP_PROD="${1:-admobilize-vision-rpi3}"

MIGVAR_APPLICATION_ID="FACEV2"
MIGVAR_PROJECT_ID="${2:-admobilize-production}"

MIGWEBLOG_URL='https://eu.webhook.logs.insight.rapid7.com/v1/noformat'
MIGTOKEN_PROVIDERLOG="859e69f9-0700-450f-b673-bbbba059bb64"

# USE: logevent STATE 
# USE: logevent STATE MESSAGE
# USE: logevent STATE MESSAGE BASH_LINENO
function logEvent {
    MIGLOG_STATE="${1:-INFO}"
    MIGLOG_MSG="${2:----}"
    MIGLOG_LINENO="${3:-${BASH_LINENO[0]}}"
    MIGLOG_UPTIME="$(cat /proc/uptime | awk '{print $1}')"

    [[ -s ${MIGCOMMAND_LOG} ]] && \
    MIGLOG_CMDLOG="$(cat ${MIGCOMMAND_LOG})" || \
    MIGLOG_CMDLOG=""
    
    echo -e "[${MIGLOG_STATE}](${MIGLOG_LINENO})\t${MIGLOG_MSG}"

    echo '{ "device":"'"${MIGDID}"'", '\
    '"script":"'"${MIGLOG_SCRIPTNAME}"'", '\
    '"line":"'"${MIGLOG_LINENO}"'", '\
    '"uptime":"'"${MIGLOG_UPTIME}"'", '\
    '"state":"'"${MIGLOG_STATE}"'", '\
    '"msg":"'"${MIGLOG_MSG}"'", '\
    '"cmdlog":"'"${MIGLOG_CMDLOG}"'"}' |& \
    curl -ki -H "Accept: application/json" \
    -X POST \
    --data @- \
    "${MIGWEBLOG_URL}/${MIGTOKEN_PROVIDERLOG}" &>${MIGCOMMAND_LOG} || \
    { echo -e "[FAIL]($LINENO)\tat send logEvent"; cat ${MIGCOMMAND_LOG}; }
    >${MIGCOMMAND_LOG}
}

logEvent "INI" "$(date)"
echo ""

logEvent "INFO" ">>> Detect balena version"
balena -v &>${MIGCOMMAND_LOG}

if [[ 0 -ne $? ]]; then
    logEvent "FAIL" "BalenaCLI not found. Install it first"
    exit $LINENO
else
    logEvent "OK"
fi
echo ""

logEvent "INFO" ">>> Detect jq version"
jq --version &>${MIGCOMMAND_LOG}

if [[ 0 -ne $? ]]; then
    logEvent "FAIL" "jq not found. Install it first"
    exit $LINENO
else
    logEvent "OK"
fi
echo ""

logEvent "INFO" "Watching for new migrated devices"
echo ""
while true
do
    balena devices --application ${MIG_BALENA_APP_INIT} &>${MIGFILE_DEVICESLIST} || \
    {
        logEvent "INFO" "Try balena login first"
        balena login --token ${MIGTOKEN_BALENACLOUD} &> ${MIGCOMMAND_LOG} && \
        logEvent "OK" "Balena Login" || \
        { logEvent "FAIL" "Balena Login"; exit $LINENO; }

        balena devices --application ${MIG_BALENA_APP_INIT} &>${MIGFILE_DEVICESLIST} || \
        { 
            cat ${MIGFILE_DEVICESLIST} &>${MIGCOMMAND_LOG}
            logEvent "FAIL" "GET Migrated Devices list"; 
            exit $LINENO; 
        }
    }

    while read LINE
    do
        MIGDID=""
        MIGUUID_SHORT=$(echo "$LINE" | awk '{print $2}')
        [[ "UUID" == ${MIGUUID_SHORT} ]] && \
        {
            MIGLIST_FIRSTLINE="$LINE"
            continue
        }

        MIGDID="${MIGUUID_SHORT}"

        balena device ${MIGUUID_SHORT} &>${MIGFILE_DEVICEINFO} || \
        { 
            cat ${MIGFILE_DEVICEINFO} &>${MIGCOMMAND_LOG}
            logEvent "FAIL" "At exec: balena device ${MIGUUID_SHORT}"; 
            exit $LINENO; 
        }
        
        
        >${MIGCOMMAND_LOG}
        MIGDEV_STATUS=$(cat ${MIGFILE_DEVICEINFO} | grep 'STATUS:' | awk '{print $2}')
        [[ 0 -ne $? ]] && { logEvent "FAIL" "GET device STATUS"; exit $LINENO; }

        MIGDEV_ONLINE=$(cat ${MIGFILE_DEVICEINFO} | grep 'IS ONLINE:' | awk '{print $3}')
        [[ 0 -ne $? ]] && { logEvent "FAIL" "GET device ONLINE"; exit $LINENO; }
        [[ ${MIGDEV_ONLINE} == 'true' ]] || continue

        echo ""
        echo ""
        logEvent "INFO" ">>> DEVICE FOUND"
        logEvent "INFO" "${MIGLIST_FIRSTLINE}"
        logEvent "INFO" "${LINE}"
        echo ""

        logEvent "INFO" ">>> Get UUID"
        MIGDEV_UUID=$(cat ${MIGFILE_DEVICEINFO} | grep 'UUID:' | awk '{print $2}')
        [[ 0 -ne $? ]] && { logEvent "FAIL" "GET device UUID: ${MIGDEV_UUID}"; exit $LINENO; }
        
        if [[ -z ${MIGDEV_UUID} ]]; then
            logEvent "FAIL" "Null UUID"
            exit $LINENO
        else
            # TODO: validate MIGDEV_UUID
            logEvent "OK" "${MIGDEV_UUID}"
        fi
        echo ""

        # https://www.balena.io/docs/reference/supervisor/supervisor-api/#patch-v1devicehost-config
        # https://www.balena.io/docs/reference/api/resources/device/
        logEvent "INFO" ">>> Fetch DEVICE ID"
        MIGDEV_DEVICEID=$(curl -sS -X POST --header "Content-Type:application/json" \
                        --header "Authorization: Bearer ${MIGTOKEN_BALENACLOUD}" \
                        --data '{"uuid":"'"${MIGDEV_UUID}"'", "method": "GET"}' \
                        "https://api.balena-cloud.com/supervisor/v1/device/host-config" | \
                        jq '.network.hostname' | tr -d '"')
        [[ 0 -ne $? ]] && { logEvent "FAIL" "fetch DEVICE ID: ${MIGDEV_DEVICEID}"; exit $LINENO; }

        if [[ -z ${MIGDEV_DEVICEID} ]] || [[ "null" == ${MIGDEV_DEVICEID} ]]; then
            logEvent "FAIL" "Null DEVICE ID"
            exit $LINENO
        fi

        if [[ ${MIGDEV_DEVICEID:0:6} == "b827eb" ]]; then
            MIGDEV_DEVICEID=${MIGDEV_DEVICEID:0:12}
            MIGDID="${MIGUUID_SHORT}:${MIGDEV_DEVICEID}"
            logEvent "OK" "${MIGDEV_DEVICEID}"
        else
            logEvent "FAIL" "Invalid DEVICE ID: ${MIGDEV_DEVICEID}"
            exit $LINENO
        fi
        echo ""

        logEvent "INFO" ">>> Fetch PROVISIONING TOKEN"
        MIGDEV_PROVISIONING_TOKEN=$(cat ${MIGFILE_TOKENLIST} | grep ${MIGDEV_DEVICEID} | awk '{print $2}')
        # MIGDEV_PROVISIONING_TOKEN=$(cat devices_migrated.csv | grep b827eb0d53a3 | awk '{split($0,a,","); print a[6]}')
        [[ 0 -ne $? ]] && { logEvent "FAIL" "Fetch PROVISIONING TOKEN: ${MIGDEV_PROVISIONING_TOKEN}"; exit $LINENO; }

        if [[ -z ${MIGDEV_PROVISIONING_TOKEN} ]]; then
            logEvent "FAIL" "Null PROVISIONING_TOKEN"
            exit $LINENO
        fi
        # TODO: validate MIGDEV_PROVISIONING_TOKEN
        logEvent "OK" "${MIGDEV_PROVISIONING_TOKEN}"
        echo ""

        # TODO: https://www.balena.io/docs/reference/api/resources/device/#rename-device

        # https://www.balena.io/docs/reference/balena-cli/#envs
        # https://www.balena.io/docs/reference/api/resources/device_environment_variable/
        logEvent "INFO" ">>> Set var in device"
        balena env add APPLICATION_ID ${MIGVAR_APPLICATION_ID} --device ${MIGDEV_UUID} &>${MIGCOMMAND_LOG} && \
        balena env add PROJECT_ID ${MIGVAR_PROJECT_ID} --device ${MIGDEV_UUID} &>${MIGCOMMAND_LOG} && \
        balena env add DEVICE_ID ${MIGDEV_DEVICEID} --device ${MIGDEV_UUID} &>${MIGCOMMAND_LOG} && \
        balena env add PROVISIONING_TOKEN ${MIGDEV_PROVISIONING_TOKEN} --device ${MIGDEV_UUID} &>${MIGCOMMAND_LOG} && \
        logEvent "OK" || { logEvent "FAIL" "ADD device var"; exit $LINENO; }
        echo ""

        sleep 3

        logEvent "INFO" ">>> Moving device to ${MIG_BALENA_APP_PROD}..."
        balena device move ${MIGDEV_UUID} --application ${MIG_BALENA_APP_PROD} &>${MIGCOMMAND_LOG} && \
        logEvent "OK" || { logEvent "FAIL" "move device to ${MIG_BALENA_APP_PROD}"; exit $LINENO; }
        logEvent "INFO" "DEVID: ${MIGDEV_DEVICEID} successfully provisioning"
        echo ""
        logEvent "INFO" ">>> Watching for new migrated devices"
        echo ""
    done < ${MIGFILE_DEVICESLIST}

    sleep 15
done
