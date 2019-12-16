#!/bin/bash

MIGSSTATEDIR_BOOT="/boot/migstate"
MIGSSTATEDIR_ROOT="/root/migstate"
MIGSSTATE_DIR="${MIGSSTATEDIR_ROOT}"
MIGCOMMAND_LOG="${MIGSSTATE_DIR}/cmd.log"
MIGSCRIPT_LOG="${MIGSSTATE_DIR}/mig2bal.log"
MIGSCRIPT_STAGE='STAGE'
MIGSCRIPT_EVENT='EVENT'
MIGSCRIPT_STATE='STATE'
MIGCONFIG_FILE="${MIGSSTATE_DIR}/mig.config"
MIGMMC="/dev/mmcblk0"
MIGBOOT_DEV='/dev/mmcblk0p1'
MIGBOOT_BKP_FILE="migboot-backup-raspbian.tgz"
MIG_RAMDISK='/mnt/migramdisk'

MIGFSM_STATE=''


# curl -s http://server/path/script.sh | bash -s arg1 arg2

{MIGBUCKET_URL}='http://10.0.0.211/balenaos'
# MIGBUCKET_URL='https://storage.googleapis.com/balenamigration'
MIGBUCKET_FILETEST='testbucketconnection.file'
MIGBUCKET_ATTEMPTNUM=0
MIGBUCKET_ATTEMPTMAX=5

MIG_FILE_RESIN_SFDISK="resin-partitions-${MIGCONFIG_BOOTSIZE}.sfdisk.gz"
MIG_FILE_RESIN_ROOTA='p2-resin-rootA.img.gz'
MIG_FILE_RESIN_ROOTB='p3-resin-rootB.img.gz'
MIG_FILE_RESIN_STATE='p5-resin-state.img.gz'
MIG_FILE_RESIN_DATA='p6-resin-data.img.gz'
MIG_FILE_RESIN_BOOT="p1-resin-boot-${MIGCONFIG_BOOTSIZE}.img.gz"
MIG_FILE_RESIN_CONFIG_JSON='testMigration.config.json'

function migExitError {
    touch ${MIGSSTATE_DIR}/MIG_BALENA_FAIL

    # cat ${MIGCOMMAND_LOG}
	
    echo -e "\n" | tee -a ${MIGSCRIPT_LOG}
    echo -e "##################" | tee -a ${MIGSCRIPT_LOG}
    echo -e "# MIGRATION FAIL #" | tee -a ${MIGSCRIPT_LOG}
    echo -e "##################" | tee -a ${MIGSCRIPT_LOG}
    echo -e "\n" | tee -a ${MIGSCRIPT_LOG}
    date | tee -a ${MIGSCRIPT_LOG}
    echo -e "\n\n" | tee -a ${MIGSCRIPT_LOG}
    echo "${BASH_SOURCE[1]##*/}:${FUNCNAME[1]}[${BASH_LINENO[0]}]" | tee -a ${MIGSCRIPT_LOG}
    exit
}

function logCommand {
    echo '{"device":"'"${MIGDID}"'", "stage":"'"${MIGSCRIPT_STAGE}"'", "event":"'"${MIGSCRIPT_EVENT}"'", "state":"'"CMDLOG"'", "msg":"['"${BASH_LINENO[0]}"'] ' | \
    cat - ${MIGCOMMAND_LOG} > temp.log && mv temp.log ${MIGCOMMAND_LOG}
    echo '"}' >> ${MIGCOMMAND_LOG} && cat ${MIGCOMMAND_LOG} &>> ${MIGSCRIPT_LOG}

    if [[ -f ${MIGSSTATE_DIR}/MIG_BALENA_NETWORK_OK ]]; then
        curl -X POST \
        -d "@${MIGCOMMAND_LOG}" \
        "${MIGWEBLOG_URL}/${MIGWEBLOG_KEYCOMMAND}"
    fi

    return 0
}

function logEvent {
    echo -e "${MIGSCRIPT_STAGE}[${BASH_LINENO[0]}] : ${MIGSCRIPT_EVENT} | {$MIGSCRIPT_STATE} | $1" $> /dev/kmsg
    
    if [[ -f ${MIGSSTATE_DIR}/MIG_BALENA_NETWORK_OK ]]; then
        echo '{"device":"'"${MIGDID}"'", "stage":"'"${MIGSCRIPT_STAGE}"'", "event":"'"${MIGSCRIPT_EVENT}"'", "state":"'"${MIGSCRIPT_STATE}"'", "msg":"'"[${BASH_LINENO[0]}] $1"'"}' | \
        tee -a ${MIGSCRIPT_LOG} /dev/tty | \
        curl -i -H "Accept: application/json" \
        -X POST \
        --data @- \
        "${MIGWEBLOG_URL}/${MIGWEBLOG_KEYEVENT}" &>${MIGCOMMAND_LOG} || logCommand
    else
        echo -e "${MIGSCRIPT_STAGE}[${BASH_LINENO[0]}] : ${MIGSCRIPT_EVENT} | {$MIGSCRIPT_STATE} | $1" &>>${MIGSCRIPT_LOG}
    fi

    return 0
}

function updateBootMigState {
    MIGSCRIPT_STAGE="mig2Balena"
    MIGSCRIPT_EVENT="Update BootMigState"
    MIGSCRIPT_STATE="INI"

    logEvent

    MIGSCRIPT_STATE="OK"

    umount ${MIGBOOT_DEV} &>/dev/null

    mount ${MIGBOOT_DEV} /boot &>${MIGCOMMAND_LOG} && \
    logEvent "BOOT mounted"  || \
    {
        MIGSCRIPT_STATE="FAIL";
        logEvent;
        logCommand;
        return 1;
    }

    if [[ -d  ${MIGSSTATEDIR_BOOT} ]]; then
        cp -rv ${MIGSSTATEDIR_ROOT} ${MIGSSTATEDIR_BOOT} &>${MIGCOMMAND_LOG} && \
        logEvent "MIGSTATE_ROOT DIR UPDATED" && \
        umount ${MIGBOOT_DEV} &>>${MIGCOMMAND_LOG} && \
        logEvent "BOOT unmounted"  && \
        touch ${MIGSSTATEDIR_ROOT}/MIG_INIT_MIGSTATE_OK || \
        {
            MIGSCRIPT_STATE="FAIL";
            logEvent;
            logCommand;
            return 1;
        }
    else
        MIGSCRIPT_STATE="FAIL";
        logEvent "Missing ${MIGSSTATEDIR_BOOT}";
        return 1;
    fi

    MIGSCRIPT_STATE="END"
    logEvent
    return 0
}

function migRestoreNetworkConfig {
    MIGSCRIPT_STAGE="mig2Balena"
    MIGSCRIPT_EVENT="Network Config"
    MIGSCRIPT_STATE="INI"

    logEvent

    MIGSCRIPT_STATE="OK"

    if [[ -f ${MIGSSTATE_DIR}/en.network ]]; then
        cp ${MIGSSTATE_DIR}/en.network /etc/systemd/network/en.network &>>${MIGSCRIPT_LOG} && \
        { 
            MIGSCRIPT_STATE="OK";
            touch ${MIGSSTATE_DIR}/MIG_INIT_NETWORK_ETH_CONFIG_OK;
            logEvent "ETH CONFIG" &>>${MIGSCRIPT_LOG};
        } || \
        { 
            MIGSCRIPT_STATE="ERROR";
            touch ${MIGSSTATE_DIR}/MIG_INIT_NETWORK_ETH_CONFIG_FAIL;
            logEvent "ETH CONFIG" &>>${MIGSCRIPT_LOG};
        }
    else
        MIGSCRIPT_STATE="FAIL";
        touch ${MIGSSTATE_DIR}/MIG_INIT_NETWORK_ETH_CONFIG_NOT_FOUND
        logEvent "ETH CONFIG NOT FOUND" &>>${MIGSCRIPT_LOG}
    fi

    if [[ -f ${MIGSSTATE_DIR}/wlan0.network ]]; then
        cp ${MIGSSTATE_DIR}/wlan0.network /etc/systemd/network/wlan0.network &>>${MIGSCRIPT_LOG} && \
        { 
            MIGSCRIPT_STATE="OK";
            touch ${MIGSSTATE_DIR}/MIG_INIT_NETWORK_WLAN_CONFIG_OK; 
            logEvent "WLAN CONFIG" &>>${MIGSCRIPT_LOG}; 
        } || \
        { 
            MIGSCRIPT_STATE="ERROR";
            touch ${MIGSSTATE_DIR}/MIG_INIT_NETWORK_WLAN_CONFIG_FAIL; 
            logEvent "WLAN CONFIG" &>>${MIGSCRIPT_LOG}; 
        }
    else
        MIGSCRIPT_STATE="FAIL";
        touch ${MIGSSTATE_DIR}/MIG_INIT_WLAN_CONFIG_NOT_FOUND
        logEvent "WLAN CONFIG NOT FOUND" &>>${MIGSCRIPT_LOG}
    fi

    if [[ -f ${MIGSSTATE_DIR}/wpa_supplicant.conf.bkp ]]; then
        mkdir -p /etc/wpa_supplicant/ &>>${MIGSCRIPT_LOG} && \
        cp ${MIGSSTATE_DIR}/wpa_supplicant.conf.bkp /etc/wpa_supplicant/wpa_supplicant.conf &>>${MIGSCRIPT_LOG} && \
        { 
            MIGSCRIPT_STATE="OK";
            touch ${MIGSSTATE_DIR}/MIG_INIT_WPA_CONFIG_OK; 
            logEvent "WPA CONFIG" &>>${MIGSCRIPT_LOG};
            /sbin/wpa_supplicant -c/etc/wpa_supplicant/wpa_supplicant.conf -Dnl80211,wext -iwlan0 &>>${MIGSCRIPT_LOG};
        } || \
        { 
            MIGSCRIPT_STATE="ERROR";
            touch ${MIGSSTATE_DIR}/MIG_INIT_WPA_CONFIG_FAIL; 
            logEvent "WPA CONFIG" &>>${MIGSCRIPT_LOG};
        }
    else
        MIGSCRIPT_STATE="FAIL";
        touch ${MIGSSTATE_DIR}/MIG_INIT_WPA_CONFIG_NOT_FOUND
        logEvent "WPA CONFIG NOT FOUND" &>>${MIGSCRIPT_LOG}
    fi

    MIGSCRIPT_STATE="END"
    logEvent
    return 0
}

# try to restore migstate
function migStateInit {
    MIGSCRIPT_STAGE="mig2Balena"
    MIGSCRIPT_EVENT="migState"
    MIGSCRIPT_STATE="INI"

    logEvent

    MIGSCRIPT_STATE="OK"

    umount ${MIGBOOT_DEV} &>/dev/null

    mount ${MIGBOOT_DEV} /boot &>${MIGCOMMAND_LOG} && \
    logEvent "BOOT mounted"  && \
    cp -rv ${MIGSSTATEDIR_ROOT} ${MIGSSTATEDIR_BOOT} &>>${MIGCOMMAND_LOG} && \
    logEvent "ROOT -> BOOT" && \
    cp -rv ${MIGSSTATEDIR_BOOT} ${MIGSSTATEDIR_ROOT} &>>${MIGCOMMAND_LOG} && \
    logEvent "BOOT -> ROOT" && \
    logEvent "MIGSTATE_ROOT DIR UPDATED" && \
    migRestoreNetworkConfig && \
    MIGSCRIPT_EVENT="migState" && \
    MIGSCRIPT_STATE="OK" && \
    cp -rv ${MIGSSTATEDIR_ROOT} ${MIGSSTATEDIR_BOOT} &>>${MIGSCRIPT_LOG} && \
    logEvent "MIGSTATE_BOOT DIR UPDATED" && \
    umount ${MIGBOOT_DEV} &>>${MIGCOMMAND_LOG} && \
    logEvent "BOOT unmounted"  && \
    touch ${MIGSSTATEDIR_ROOT}/MIG_INIT_MIGSTATE_OK || \
    {
        MIGSCRIPT_STATE="FAIL";
        logEvent;
        logCommand;
        migExitError;
    }

    MIGSCRIPT_STATE="END"
    logEvent
    return 0
}

function migCreateRamdisk {
    MIGSCRIPT_STAGE="mig2Balena"
    MIGSCRIPT_EVENT="Create Ramdisk"
    MIGSCRIPT_STATE="INI"
    
    logEvent

    umount ${MIG_RAMDISK} &>/dev/null

    mkdir -p ${MIG_RAMDISK} &>${MIGSCRIPT_LOG} && \
    rm -rf ${MIG_RAMDISK}/* &>>${MIGSCRIPT_LOG} && \
    mount -t tmpfs -o size=400M tmpramdisk ${MIG_RAMDISK} &>>${MIGSCRIPT_LOG} && \
    {
        touch ${MIG_RAMDISK}/MIG_INIT_RAMDISK_OK ;
        MIGSCRIPT_STATE="OK";
        logEvent "RAMDISK" &>>${MIGSCRIPT_LOG};
    } || \
    { 
        touch ${MIG_RAMDISK}/MIG_INIT_RAMDISK_FAIL;
        MIGSCRIPT_STATE="ERROR";
        logEvent;
        logCommand;
        migExitError;
    }

    MIGSCRIPT_STATE="END"
    logEvent
    return 0
}

function backupRaspbianBoot {
    MIGSCRIPT_STAGE="mig2Balena"
    MIGSCRIPT_EVENT="Backup Raspbian BOOT"
    MIGSCRIPT_STATE="INI"
    
    umount /dev/mmcblk0p2 &>/dev/null

    mkdir -p /mnt/rootfs &> ${MIGCOMMAND_LOG} && \
    mount /dev/mmcblk0p2 /mnt/rootfs &>>${MIGCOMMAND_LOG} && \
    logEvent "ROOTFS mounted" && \
    [[ -f /mnt/rootfs/${MIGBOOT_BKP_FILE} ]] && \
    cp /mnt/rootfs/${MIGBOOT_BKP_FILE} /root &>>${MIGCOMMAND_LOG} && \
    logEvent "Copyed ${MIGBOOT_BKP_FILE}" && \
    umount /dev/mmcblk0p2 &>>${MIGCOMMAND_LOG} && \
    logEvent "ROOTFS unmounted"  && \
    touch ${MIGSSTATEDIR_ROOT}/MIG_BALENA_BACKUP_RASPBIAN_BOOT_OK || \
    {
        touch ${MIGSSTATEDIR_ROOT}/MIG_BALENA_BACKUP_RASPBIAN_BOOT_ERROR;
        MIGSCRIPT_STATE="ERROR";
        logEvent;
        logCommand;
        migExitError;
    }

    MIGSCRIPT_STATE="END"
    logEvent
    return 0
}

function testBucketConnection {
    MIGSCRIPT_STAGE="mig2Balena"
    MIGSCRIPT_EVENT="Test Network"
    MIGSCRIPT_STATE="INI"

    [[ -f ${MIGSSTATE_DIR}/MIG_BALENA_NETWORK_ERROR ]] && rm ${MIGSSTATE_DIR}/MIG_BALENA_NETWORK_ERROR
    [[ -f ${MIGSSTATE_DIR}/MIG_BALENA_NETWORK_OK ]] && rm ${MIGSSTATE_DIR}/MIG_BALENA_NETWORK_OK

	until $(wget -q --tries=10 --timeout=10 --spider "${MIGBUCKET_URL}/${MIGBUCKET_FILETEST}"); do
		if [ ${MIGBUCKET_ATTEMPTNUM} -eq ${MIGBUCKET_ATTEMPTMAX} ];then
            MIGSCRIPT_STATE="ERROR"
			logEvent "No Network Connection"
			touch ${MIGSSTATE_DIR}/MIG_BALENA_NETWORK_ERROR
			migExitError
	    fi

	    MIGBUCKET_ATTEMPTNUM=$(($MIGBUCKET_ATTEMPTNUM+1))
        MIGSCRIPT_STATE="FAIL"
		logEvent "Network attempt ${MIGBUCKET_ATTEMPTNUM}"
	    sleep 10
	done
    
    touch ${MIGSSTATE_DIR}/MIG_BALENA_NETWORK_OK
    
    MIGSCRIPT_STATE="END"
    logEvent
    return 0
}

function updateStateFSM {
    MIGSCRIPT_STAGE="mig2Balena"
    MIGSCRIPT_EVENT="Update FSM"
    MIGSCRIPT_STATE="INI"
    logEvent

    if [[ ! -f ${MIGSSTATE_DIR}/MIG_FSM_SFDISK_OK ]]; then
        MIGFSM_STATE='SFDISK'
        logEvent "Set FSM State SFDISK"
    elif [[ ! -f ${MIGSSTATE_DIR}/MIG_FSM_ROOTA_OK ]]; then
        MIGFSM_STATE='ROOTA'
        logEvent "Set FSM State ROOTA"
    elif [[ ! -f ${MIGSSTATE_DIR}/MIG_FSM_ROOTB_OK ]]; then
        MIGFSM_STATE='ROOTB'
        logEvent "Set FSM State ROOTB"
    elif [[ ! -f ${MIGSSTATE_DIR}/MIG_FSM_STATE_OK ]]; then
        MIGFSM_STATE='STATE'
        logEvent "Set FSM State STATE"
    elif [[ ! -f ${MIGSSTATE_DIR}/MIG_FSM_DATA_OK ]]; then
        MIGFSM_STATE='DATA'
        logEvent "Set FSM State DATA"
    elif [[ ! -f ${MIGSSTATE_DIR}/MIG_FSM_BOOT_OK ]]; then
        MIGFSM_STATE='BOOT'
        logEvent "Set FSM State BOOT"
    elif [[ ! -f ${MIGSSTATE_DIR}/MIG_FSM_CONFIG_OK ]]; then
        MIGFSM_STATE='CONFIG'
        logEvent "Set FSM State CONFIG"
    else
        MIGFSM_STATE='SUCCESS'
        logEvent "Set FSM State SUCCESS"
    fi

    MIGSCRIPT_STATE="END"
    logEvent
    return 0
}

function migrationFSM {
    MIGSCRIPT_STAGE="mig2Balena"
    MIGSCRIPT_EVENT="Migration FSM"
    MIGSCRIPT_STATE="INI"
    logEvent
    
    MIGSCRIPT_STATE="OK"

    case ${MIGFSM_STATE} in
        'SFDISK')
            logEvent "SFDISK - wget"
            wget "${MIGBUCKET_URL}/${MIG_FILE_RESIN_SFDISK}" &>${MIGCOMMAND_LOG} || { logCommand; migExitError; }
            logEvent "SFDISK - gunzip | sfdisk"
            gunzip -c ${MIG_FILE_RESIN_SFDISK} | sfdisk ${MIGMMC} &>${MIGCOMMAND_LOG} || { logCommand; migExitError; }
            logEvent "SFDISK - rm"
            rm ${MIG_FILE_RESIN_SFDISK} &>${MIGCOMMAND_LOG} || { logCommand; migExitError; }
            touch ${MIGSSTATE_DIR}/MIG_FSM_SFDISK_OK 
            logEvent "SFDISK - [OK]"
            ;;

        'ROOTA')
            logEvent "ROOTA - wget"
            wget "${MIGBUCKET_URL}/${MIG_FILE_RESIN_ROOTA}" &>${MIGCOMMAND_LOG} || { logCommand; migExitError; }
            logEvent "ROOTA - gunzip | dd"
            gunzip -c ${MIG_FILE_RESIN_ROOTA} | dd of=${MIGMMC}p2 bs=4M &>${MIGCOMMAND_LOG} || { logCommand; migExitError; }
            logEvent "ROOTA - rm"
            rm ${MIG_FILE_RESIN_ROOTA} &>${MIGCOMMAND_LOG} || { logCommand; migExitError; }
            touch ${MIGSSTATE_DIR}/MIG_FSM_ROOTA_OK 
            logEvent "ROOTA - [OK]"
            ;;

        'ROOTB')
            logEvent "ROOTB - wget"
            wget "${MIGBUCKET_URL}/${MIG_FILE_RESIN_ROOTB}" &>${MIGCOMMAND_LOG} || { logCommand; migExitError; }
            logEvent "ROOTB - gunzip | dd"
            gunzip -c ${MIG_FILE_RESIN_ROOTB} | dd of=${MIGMMC}p3 bs=4M &>${MIGCOMMAND_LOG} || { logCommand; migExitError; }
            logEvent "ROOTB - rm"
            rm ${MIG_FILE_RESIN_ROOTB} &>${MIGCOMMAND_LOG} || { logCommand; migExitError; }
            touch ${MIGSSTATE_DIR}/MIG_FSM_ROOTB_OK 
            logEvent "ROOTB - [OK]"
            ;;
            
        'STATE')
            logEvent "STATE - wget"
            wget "${MIGBUCKET_URL}/${MIG_FILE_RESIN_STATE}" &>${MIGCOMMAND_LOG} || { logCommand; migExitError; }
            logEvent "STATE - gunzip | dd"
            gunzip -c ${MIG_FILE_RESIN_STATE} | dd of=${MIGMMC}p5 bs=4M &>${MIGCOMMAND_LOG} || { logCommand; migExitError; }
            logEvent "STATE - rm"
            rm ${MIG_FILE_RESIN_STATE} &>${MIGCOMMAND_LOG} || { logCommand; migExitError; }
            touch ${MIGSSTATE_DIR}/MIG_FSM_STATE_OK 
            logEvent "STATE - [OK]"
            ;;
            
        'DATA')
            logEvent "DATA - wget"
            wget "${MIGBUCKET_URL}/${MIG_FILE_RESIN_DATA}" &>${MIGCOMMAND_LOG} || { logCommand; migExitError; }
            logEvent "DATA - gunzip | dd"
            gunzip -c ${MIG_FILE_RESIN_DATA} | dd of=${MIGMMC}p6 bs=4M &>${MIGCOMMAND_LOG} || { logCommand; migExitError; }
            logEvent "DATA - rm"
            rm ${MIG_FILE_RESIN_DATA} &>${MIGCOMMAND_LOG} || { logCommand; migExitError; }
            touch ${MIGSSTATE_DIR}/MIG_FSM_DATA_OK 
            logEvent "DATA - [OK]"
            ;;
            
        'BOOT')
            logEvent "BOOT - wget"
            wget "${MIGBUCKET_URL}/${MIG_FILE_RESIN_BOOT}" &>${MIGCOMMAND_LOG} || { logCommand; migExitError; }
            logEvent "BOOT - gunzip | dd"
            gunzip -c ${MIG_FILE_RESIN_BOOT} | dd of=${MIGMMC}p1 bs=4M &>${MIGCOMMAND_LOG} || { logCommand; migExitError; }
            logEvent "BOOT - rm"
            rm ${MIG_FILE_RESIN_BOOT} &>${MIGCOMMAND_LOG} || { logCommand; migExitError; }
            touch ${MIGSSTATE_DIR}/MIG_FSM_BOOT_OK 
            logEvent "BOOT - [OK]"
            ;;
            
        'CONFIG')
            logEvent "CONFIG - Mount Boot"
            mkdir -p /mnt/boot && mount ${MIGMMC}p1 /mnt/boot/ &>${MIGCOMMAND_LOG} || { logCommand; migExitError; }
            logEvent "CONFIG - wget json"
            wget "${MIGBUCKET_URL}/$file_config_json" &>${MIGCOMMAND_LOG} || { logCommand; migExitError; }
            logEvent "CONFIG - cp json"
            cp $file_config_json /mnt/boot/config.json &>${MIGCOMMAND_LOG} || { logCommand; migExitError; }
            logEvent "CONFIG - cp json"
            wget "${MIGBUCKET_URL}/${MIG_FILE_RESIN_CONFIG}" &>${MIGCOMMAND_LOG} || { logCommand; migExitError; }
            logEvent "CONFIG - gunzip | dd"
            gunzip -c ${MIG_FILE_RESIN_CONFIG} | dd of=${MIGMMC}p2 bs=4M &>${MIGCOMMAND_LOG} || { logCommand; migExitError; }
            logEvent "CONFIG - rm"
            rm ${MIG_FILE_RESIN_CONFIG} &>${MIGCOMMAND_LOG} || { logCommand; migExitError; }
            touch ${MIGSSTATE_DIR}/MIG_FSM_CONFIG_OK 
            logEvent "CONFIG - [OK]"
            touch ${MIGSSTATE_DIR}/MIG_FSM_SUCCESS 
            logEvent "SUCCESS -- Reboot NOW!!!"
            ;;
        
        'SUCCESS')
            touch ${MIGSSTATE_DIR}/MIG_FSM_SUCCESS
            logEvent "SUCCESS -- Reboot NOW!!!"
            ;;
        *)
            MIGSCRIPT_STATE="ERROR";
            logEvent "Missing STATE ${MIGFSM_STATE}"
            migExitError
    esac

    MIGSCRIPT_STATE="END"
    logEvent
    return 0
}

function mig2Balena {
	MIGSCRIPT_STAGE="mig2Balena"
    MIGSCRIPT_EVENT="mig2Balena.sh"
    MIGSCRIPT_STATE="INI"

	[[ ! -d ${MIGSSTATE_DIR} ]] && mkdir -p ${MIGSSTATE_DIR} && \
    logEvent "Missing ${MIGSSTATE_DIR} ... Created." || \
    logEvent
    
    [[ -f ${MIGSSTATE_DIR}/MIG_BALENA_FAIL ]] && rm ${MIGSSTATE_DIR}/MIG_BALENA_FAIL
    [[ -f ${MIGSSTATE_DIR}/MIG_BALENA_SUCCESS ]] && rm ${MIGSSTATE_DIR}/MIG_BALENA_SUCCESS

    echo -e "\n\n" | tee -a ${MIGSCRIPT_LOG}
    echo -e "*****************" | tee -a ${MIGSCRIPT_LOG}
    echo -e "* MIGRATION INI *" | tee -a ${MIGSCRIPT_LOG}
    echo -e "*****************" | tee -a ${MIGSCRIPT_LOG}
    echo -e "" | tee -a ${MIGSCRIPT_LOG}
    date | tee -a ${MIGSCRIPT_LOG}
    echo -e "" | tee -a ${MIGSCRIPT_LOG}

    # try to restore migstate and network config
    [[ ! -f ${MIGSSTATE_DIR}/MIG_INIT_MIGSTATE_OK ]] && migStateInit || \
    {
        MIGSCRIPT_STATE="OK";
        logEvent "/init was successfully completed"
    }
	
    testBucketConnection

    if [[ ! -f ${MIGCONFIG_FILE} ]]; then
        MIGSCRIPT_STATE="FAIL"
        logEvent "Missing ${MIGCONFIG_FILE}"
        ls -alh ${MIGSSTATE_DIR} &>${MIGCOMMAND_LOG}
        logCommand
        migExitError
    else 
        source ${MIGCONFIG_FILE} || \
        { logCommand; migExitError; }
    fi
    
    [[ ! -f ${MIG_RAMDISK}/MIG_INIT_RAMDISK_OK ]] && migCreateRamdisk || \
    {
        rm -rf ${MIG_RAMDISK}/* || { logCommand; migExitError; }
        MIGSCRIPT_STATE="OK";
        logEvent "${MIG_RAMDISK} was successfully mounted";
    }

    [[ ! -f /root/${MIGBOOT_BKP_FILE} ]] && backupRaspbianBoot

    while [[ ! -f ${MIGSSTATE_DIR}/MIG_FSM_SUCCESS ]]; do
        updateStateFSM
        migrationFSM
        updateBootMigState
    done

    MIGSCRIPT_STAGE="mig2Balena"
    MIGSCRIPT_EVENT="mig2Balena.sh"
    MIGSCRIPT_STATE="END"
}


mig2Balena

#exec /sbin/reboot
# wget 10.0.0.211/balenaos/scripts/mig2balena.sh
# scp trecetp@fermi:~/RPI3/balena-migration-ramdisk/packages/mig2balena.service/mig2balena.sh /srv/http/balenaos/scripts/
