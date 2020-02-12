#!/bin/bash
# TODO:
# - Validate Token
# - Validate UUID

# APPLICATION_ID
# FACEV2

# PROVISIONING_TOKEN
# 1ef0d7d4-d859-4bcf-aba9-42c921883522

# PROJECT_ID
# admobilize-testing

# DEVICE_ID
# mac_add 70:88:6b:87:ea:b9
# b8:27:eb:a0:a8:71 -> b827eba0a871

MIGTOKEN_BALENACLOUD="ErR56DEPe87jpjKaTg8JDPMORRD8F44A"
MIGFILE_DEVICESLIST="devlist.txt"
MIGFILE_DEVICEINFO="devinfo.txt"
MIGFILE_TOKENLIST="listProvToken.csv"

MIG_BALENA_APP_INIT="BalenaMigration"
MIG_BALENA_APP_PROD="testMigration"

MIGVAR_APPLICATION_ID="FACEV2"
MIGVAR_PROJECT_ID="admobilize-testing"

echo ">>> Detect balena version"
balena -v

if [[ 0 -ne $? ]]; then
    echo "[FAIL] BalenaCLI not found. Install it first"
    exit $LINENO
fi

echo ">>> Detect jq version"
jq --version

if [[ 0 -ne $? ]]; then
    echo "[FAIL] jq not found. Install it first"
    exit $LINENO
fi

echo ">>> Watching for new migrated devices"
while true
do
    # balena devices >${MIGFILE_DEVICESLIST}
    balena devices --application ${MIG_BALENA_APP_INIT} >${MIGFILE_DEVICESLIST} || \
    {
        # echo ">>> Try balena login"
        balena login --token ${MIGTOKEN_BALENACLOUD} || \
        { echo "[FAIL] Balena Login"; exit $LINENO; }

        balena devices --application ${MIG_BALENA_APP_INIT} >${MIGFILE_DEVICESLIST} || \
        { echo "[FAIL] GET Migrated Devices list"; exit $LINENO; }
    }

    while read LINE
    do
        MIGUUID_SHORT=$(echo "$LINE" | awk '{print $2}')
        [[ "UUID" == ${MIGUUID_SHORT} ]] && \
        {
            MIGLIST_FIRSTLINE="$LINE"
            continue
        }
        # echo ${MIGUUID_SHORT}

        balena device ${MIGUUID_SHORT} >${MIGFILE_DEVICEINFO}
        [[ 0 -ne $? ]] && { echo "[FAIL] balena device"; exit $LINENO; }
        
        MIGDEV_STATUS=$(cat ${MIGFILE_DEVICEINFO} | grep 'STATUS:' | awk '{print $2}')
        [[ 0 -ne $? ]] && { echo "[FAIL] GET device STATUS"; exit $LINENO; }
        # [[ ${MIGDEV_STATUS} == 'idle' ]] && echo "IDLE"

        MIGDEV_ONLINE=$(cat ${MIGFILE_DEVICEINFO} | grep 'IS ONLINE:' | awk '{print $3}')
        [[ 0 -ne $? ]] && { echo "[FAIL] GET device ONLINE"; exit $LINENO; }
        # [[ ${MIGDEV_ONLINE} == 'true' ]] && echo "${MIGUUID_SHORT} online" || echo "${MIGUUID_SHORT} offline" 
        [[ ${MIGDEV_ONLINE} == 'true' ]] || continue

        echo ""
        echo ""
        echo ">>> DEVICE FOUND"
        echo "${MIGLIST_FIRSTLINE}"
        echo "${LINE}"

        echo ">>> Get UUID"
        MIGDEV_UUID=$(cat ${MIGFILE_DEVICEINFO} | grep 'UUID:' | awk '{print $2}')
        [[ 0 -ne $? ]] && { echo "[FAIL] GET device UUID"; exit $LINENO; }
        
        if [[ -z ${MIGDEV_UUID} ]]; then
            echo "[FAIL] Get UUID: ${MIGDEV_UUID}"
            exit $LINENO
        else
            # TODO: validate MIGDEV_UUID
            echo "${MIGDEV_UUID}"
        fi

        echo ">>> Fetch DEVICE ID"
        MIGDEV_DEVICEID=$(curl -sS -X POST --header "Content-Type:application/json" \
                        --header "Authorization: Bearer ${MIGTOKEN_BALENACLOUD}" \
                        --data '{"uuid":"'"${MIGDEV_UUID}"'", "method": "GET"}' \
                        "https://api.balena-cloud.com/supervisor/v1/device/host-config" | \
                        jq '.network.hostname' | tr -d '"')
        [[ 0 -ne $? ]] && { echo "[FAIL] fetch DEVICE ID"; exit $LINENO; }

        if [[ -z ${MIGDEV_DEVICEID} ]] || [[ "null" == ${MIGDEV_DEVICEID} ]]; then
            echo "[FAIL] Null DEVICE ID: ${MIGDEV_DEVICEID}"
            exit $LINENO
        fi

        if [[ ${MIGDEV_DEVICEID:0:6} == "b827eb" ]]; then
            MIGDEV_DEVICEID=${MIGDEV_DEVICEID:0:12}
            echo "${MIGDEV_DEVICEID}"
        else
            echo "[FAIL] Invalid DEVICE ID: ${MIGDEV_DEVICEID}"
            exit $LINENO
        fi

        echo ">>> Fetch PROVISIONING TOKEN"
        MIGDEV_PROVISIONING_TOKEN=$(cat ${MIGFILE_TOKENLIST} | grep ${MIGDEV_DEVICEID} | awk '{print $2}')
        [[ 0 -ne $? ]] && { echo "[FAIL] Fetch PROVISIONING TOKEN"; exit $LINENO; }

        if [[ -z ${MIGDEV_PROVISIONING_TOKEN} ]]; then
            echo "[FAIL] Null PROVISIONING_TOKEN"
            exit $LINENO
        fi
        # TODO: validate MIGDEV_PROVISIONING_TOKEN
        echo "${MIGDEV_PROVISIONING_TOKEN}"

        echo ">>> Set var in device"
        balena env add APPLICATION_ID ${MIGVAR_APPLICATION_ID} --device ${MIGDEV_UUID} && \
        balena env add PROJECT_ID ${MIGVAR_PROJECT_ID} --device ${MIGDEV_UUID} && \
        balena env add DEVICE_ID ${MIGDEV_DEVICEID} --device ${MIGDEV_UUID} && \
        balena env add PROVISIONING_TOKEN ${MIGDEV_PROVISIONING_TOKEN} --device ${MIGDEV_UUID} && \
        echo "OK" || { echo "[FAIL] ADD device var"; exit $LINENO; }

        sleep 3

        echo ">>> Moving device to ${MIG_BALENA_APP_PROD}..."
        balena device move ${MIGDEV_UUID} --application ${MIG_BALENA_APP_PROD} && \
        echo "OK" || { echo "[FAIL] move device to ${MIG_BALENA_APP_PROD}"; exit $LINENO; }
        echo "DEVID: ${MIGDEV_DEVICEID} successfully provisioning"
        echo ""
        echo ">>> Watching for new migrated devices"
    done < ${MIGFILE_DEVICESLIST}

    sleep 15
done






# balena devices -> list all devices
# balena env add APPLICATION_ID FACEV2 --device b5657f54c3db44c393e615be9fbd53cf --service admprovider
# balena device move b5657f54c3db44c393e615be9fbd53cf --application admobilize-vision-rpi3-nettest
# cat /home/trecetp/Downloads/BalenaMigration.config.json | jq '.+ {"hostname": "adb145432"}'
 
# curl -X POST --header "Content-Type:application/json" \
# --header "Authorization: Bearer ErR56DEPe87jpjKaTg8JDPMORRD8F44A" \
# --data '{"uuid":"7132052890c52f837ed69f24069ab8db", "method": "GET"}' \
# "https://api.balena-cloud.com/supervisor/v1/device/host-config"
# | jq '.hostame'

# curl -X POST --header "Content-Type:application/json" --header "Authorization: Bearer ErR56DEPe87jpjKaTg8JDPMORRD8F44A" --data '{"uuid":"b5657f54c3db44c393e615be9fbd53cf", "method": "GET"}' "https://api.balena-cloud.com/supervisor/v1/device/host-config" | jq '.network.hostname' | tr -d '"'

# curl -X POST --header "Content-Type:application/json" \
# --header "Authorization: Bearer ErR56DEPe87jpjKaTg8JDPMORRD8F44A" \
# --data '{"uuid":"b5657f54c3db44c393e615be9fbd53cf", "method": "GET"}' \
# "https://api.balena-cloud.com/supervisor/v1/device/host-config"

# curl -X POST --header "Content-Type:application/json" \
# --header "Authorization: Bearer ErR56DEPe87jpjKaTg8JDPMORRD8F44A" \
# --data '{"uuid":"b5657f54c3db44c393e615be9fbd53cf", "method": "GET"}' \
# "https://api.balena-cloud.com/supervisor/v1/device/host-config" | \
# jq '.network.hostname' | tr -d '"'

# balena env add APPLICATION_ID FACEV2 --device b5657f54c3db44c393e615be9fbd53cf --service admprovider
# balena env add PROJECT_ID admobilize-testing --device b5657f54c3db44c393e615be9fbd53cf --service admprovider
# balena env add DEVICE_ID admobilize-testing --device b5657f54c3db44c393e615be9fbd53cf --service admprovider

# balena env add APPLICATION_ID FACEV2 --device b5657f54c3db44c393e615be9fbd53cf
# balena env add PROJECT_ID admobilize-testing --device b5657f54c3db44c393e615be9fbd53cf
# balena env add DEVICE_ID b827eba0a871 --device b5657f54c3db44c393e615be9fbd53cf
# balena env add PROVISIONING_TOKEN c76f8c9f12504f22814f479c9a77442c --device b5657f54c3db44c393e615be9fbd53cf
# balena device move b5657f54c3db44c393e615be9fbd53cf --application testMigration
# b5657f54c3db44c393e615be9fbd53cf


# curl -i \
# -H "Accept: application/json" \
# -X POST -d '{"message":"sending logs to InsightOps", "success":true}' \
# https://eu.webhook.logs.insight.rapid7.com/v1/noformat/859e69f9-0700-450f-b673-bbbba059bb64