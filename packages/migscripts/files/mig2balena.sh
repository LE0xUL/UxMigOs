#!/bin/bash

# wget -O - 'http://10.0.0.211/balenaos/scripts/mig2balena.sh' | bash
# wget http://10.0.0.211/balenaos/scripts/mig2balena.sh

MIGSSTATEDIR_BOOT="/boot/migstate"
MIGSSTATEDIR_ROOT="/root/migstate"
MIGSSTATE_DIR="${MIGSSTATEDIR_ROOT}"
MIGCOMMAND_LOG="${MIGSSTATE_DIR}/cmd.log"
MIGSCRIPT_LOG="${MIGSSTATE_DIR}/mig2balena.log"
MIGSCRIPT_STATE='STATE'
MIGCONFIG_FILE="mig.config"
MIGMMC="/dev/mmcblk0"
MIGBOOT_MOUNTDIR='/boot'
MIGBOOT_DEVICE='/dev/mmcblk0p1'
MIGROOTFS_DEVICE='/dev/mmcblk0p2'
MIGROOTFS_MOUNTDIR='/mnt/rootfs'
MIGBKP_RASPBIANBOOT="migboot-backup-raspbian.tgz"
MIG_RAMDISK='/mnt/migramdisk'

MIGFSM_STATE=''

MIGBUCKET_URL='http://10.0.0.211/balenaos'
# MIGBUCKET_URL='https://storage.googleapis.com/balenamigration'
MIGBUCKET_FILETEST='testbucketconnection.file'
MIGBUCKET_ATTEMPTNUM=0
MIGBUCKET_ATTEMPTMAX=5

MIGWEBLOG_URL='https://eu.webhook.logs.insight.rapid7.com/v1/noformat'
MIGWEBLOG_KEYEVENT='f79248d1-bbe0-427b-934b-02a2dee5f24f'
MIGWEBLOG_KEYCOMMAND='642de669-cf83-4e19-a6bf-9548eb7f5210'

MIG_FILE_RESIN_SFDISK="resin-partitions-${MIGCONFIG_BOOTSIZE}.sfdisk.gz"
MIG_FILE_RESIN_ROOTA='p2-resin-rootA.img.gz'
MIG_FILE_RESIN_ROOTB='p3-resin-rootB.img.gz'
MIG_FILE_RESIN_STATE='p5-resin-state.img.gz'
MIG_FILE_RESIN_DATA='p6-resin-data.img.gz'
MIG_FILE_RESIN_BOOT="p1-resin-boot-${MIGCONFIG_BOOTSIZE}.img.gz"
MIG_FILE_RESIN_CONFIG_JSON='testMigration.config.json'

function migExitError {
    touch ${MIGSSTATE_DIR}/MIG_BALENA_ERROR
	# TODO: rm alive file
    echo -e "\n" | tee -a ${MIGSCRIPT_LOG}
    echo -e "##################" | tee -a ${MIGSCRIPT_LOG}
    echo -e "# MIGRATION FAIL #" | tee -a ${MIGSCRIPT_LOG}
    echo -e "##################" | tee -a ${MIGSCRIPT_LOG}
    echo -e "\n" | tee -a ${MIGSCRIPT_LOG}
    date | tee -a ${MIGSCRIPT_LOG}
    echo -e "\n" | tee -a ${MIGSCRIPT_LOG}
    echo -e "MIGOS | ${BASH_SOURCE[1]##*/} | ${FUNCNAME[1]} | ${BASH_LINENO[0]} | EXIT | $1" |& tee -a ${MIGSCRIPT_LOG} /dev/kmsg
    echo -e "\n" | tee -a ${MIGSCRIPT_LOG}
    exit
}

# En caso de error, envia log del comando a la web
function logCommand {
    echo -e "MIGOS | ${BASH_SOURCE[1]##*/} | ${FUNCNAME[1]} | ${BASH_LINENO[0]} | $(cat /proc/uptime | awk '{print $1}') | INI | CMDLOG " |& tee -a ${MIGSCRIPT_LOG} /dev/kmsg

    if [[ -f ${MIGSSTATE_DIR}/MIGOS_NETWORK_OK ]]; then
        echo '{"device":"'"${MIGDID}"'", '\
        '"script":"mig2balena.sh", '\
        '"function":"'"${FUNCNAME[1]}"'", '\
        '"line":"'"${BASH_LINENO[0]}"'", '\
        '"uptime":"'"$(cat /proc/uptime | awk '{print $1}')"'", '\
        '"state":"'"CMDLOG"'", '\
        '"msg":"' | \
        cat - ${MIGCOMMAND_LOG} > temp.log && \
        mv temp.log ${MIGCOMMAND_LOG} && \
        echo '"}' >>${MIGCOMMAND_LOG} && \
        cat ${MIGCOMMAND_LOG} &>>${MIGSCRIPT_LOG} && \
        curl -X POST \
        -d "@${MIGCOMMAND_LOG}" \
        "${MIGWEBLOG_URL}/${MIGWEBLOG_KEYCOMMAND}" &>>${MIGSCRIPT_LOG} || \
        echo -e "MIGOS | ${BASH_SOURCE[1]##*/} | ${FUNCNAME[1]} | ${BASH_LINENO[0]} | $(cat /proc/uptime | awk '{print $1}') | FAIL | Can not send CMDLOG, curl fail" |& tee -a ${MIGSCRIPT_LOG} /dev/kmsg
    else
        echo -e "MIGOS | ${BASH_SOURCE[1]##*/} | ${FUNCNAME[1]} | ${BASH_LINENO[0]} | $(cat /proc/uptime | awk '{print $1}') | FAIL | Can not send CMDLOG, No network" |& tee -a ${MIGSCRIPT_LOG} /dev/kmsg
    fi

    echo -e "MIGOS | ${BASH_SOURCE[1]##*/} | ${FUNCNAME[1]} | ${BASH_LINENO[0]} | $(cat /proc/uptime | awk '{print $1}') | END | CMDLOG " |& tee -a ${MIGSCRIPT_LOG} /dev/kmsg

    return 0
}

# Guarda log de evento en el archivo de log, lo muestra por kmsg y lo envia a la web
function logEvent {
    #TODO: touch Alive file for Watchdog
    if [[ -f ${MIGSSTATE_DIR}/MIGOS_NETWORK_OK ]]; then
        >${MIGCOMMAND_LOG}
        echo '{"device":"'"${MIGDID}"'", '\
        '"script":"mig2balena.sh", '\
        '"function":"'"${FUNCNAME[1]}"'", '\
        '"line":"'"${BASH_LINENO[0]}"'", '\
        '"uptime":"'"$(cat /proc/uptime | awk '{print $1}')"'", '\
        '"state":"'"${MIGSCRIPT_STATE}"'", '\
        '"msg":"'"$1"'"}' | \
        tee -a ${MIGSCRIPT_LOG} /dev/kmsg /dev/tty | \
        curl -i -H "Accept: application/json" \
        -X POST \
        --data @- \
        "${MIGWEBLOG_URL}/${MIGWEBLOG_KEYEVENT}" &>>${MIGCOMMAND_LOG} || logCommand
    else
        echo -e "MIGOS | ${BASH_SOURCE[1]##*/} | ${FUNCNAME[1]} | ${BASH_LINENO[0]} | $(cat /proc/uptime | awk '{print $1}') | ${MIGSCRIPT_STATE} | $1" |& tee -a ${MIGSCRIPT_LOG} /dev/kmsg
    fi

    return 0
}

function updateBootMigState {
    MIGSCRIPT_STATE="INI"

    logEvent

    MIGSCRIPT_STATE="OK"

    umount ${MIGBOOT_DEVICE} |& tee -a ${MIGSCRIPT_LOG} ${MIGCOMMAND_LOG}

    mount ${MIGBOOT_DEVICE} ${MIGBOOT_MOUNTDIR} &>${MIGCOMMAND_LOG} && \
    logEvent "BOOT mounted"  || \
    {
        MIGSCRIPT_STATE="FAIL";
        logEvent;
        logCommand;
        return 1;
    }

    if [[ -d  ${MIGSSTATEDIR_BOOT} ]]; then
        rsync -av ${MIGSSTATEDIR_ROOT} ${MIGBOOT_MOUNTDIR} &>${MIGCOMMAND_LOG} && \
        logEvent "MIGSTATE_ROOT DIR UPDATED" && \
        umount ${MIGBOOT_DEVICE} &>>${MIGCOMMAND_LOG} && \
        logEvent "BOOT unmounted"  && \
        touch ${MIGSSTATEDIR_ROOT}/MIG_BALENA_MIGSTATE_OK || \
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
    MIGSCRIPT_STATE="INI"
    logEvent

    if [[ -f ${MIGSSTATE_DIR}/en.network ]]; then
        >${MIGCOMMAND_LOG}
        cp -v ${MIGSSTATE_DIR}/en.network /etc/systemd/network/en.network |& tee -a ${MIGSCRIPT_LOG} ${MIGCOMMAND_LOG} && \
        { 
            MIGSCRIPT_STATE="OK"
            touch ${MIGSSTATE_DIR}/MIG_BALENA_NETWORK_ETH_CONFIG_OK
            logEvent "ETH CONFIG"
        } || \
        { 
            MIGSCRIPT_STATE="ERROR"
            touch ${MIGSSTATE_DIR}/MIG_BALENA_NETWORK_ETH_CONFIG_FAIL
            logCommand
            logEvent "ETH CONFIG"
        }
    else
        MIGSCRIPT_STATE="FAIL"
        touch ${MIGSSTATE_DIR}/MIG_BALENA_NETWORK_ETH_CONFIG_NOT_FOUND
        logEvent "ETH CONFIG NOT FOUND"
    fi

    if [[ -f ${MIGSSTATE_DIR}/wlan0.network ]]; then
        >${MIGCOMMAND_LOG}
        cp -v ${MIGSSTATE_DIR}/wlan0.network /etc/systemd/network/wlan0.network |& tee -a ${MIGSCRIPT_LOG} ${MIGCOMMAND_LOG} && \
        { 
            MIGSCRIPT_STATE="OK"
            touch ${MIGSSTATE_DIR}/MIG_BALENA_NETWORK_WLAN_CONFIG_OK
            logEvent "WLAN CONFIG" 
        } || \
        { 
            MIGSCRIPT_STATE="ERROR"
            touch ${MIGSSTATE_DIR}/MIG_BALENA_NETWORK_WLAN_CONFIG_FAIL
            logCommand
            logEvent "WLAN CONFIG" 
        }
    else
        MIGSCRIPT_STATE="FAIL"
        touch ${MIGSSTATE_DIR}/MIG_BALENA_WLAN_CONFIG_NOT_FOUND
        logEvent "WLAN CONFIG NOT FOUND"
    fi

    if [[ -f ${MIGSSTATE_DIR}/wpa_supplicant.conf.bkp ]]; then
        >${MIGCOMMAND_LOG}
        mkdir -vp /etc/wpa_supplicant/ |& tee -a ${MIGSCRIPT_LOG} ${MIGCOMMAND_LOG} && \
        cp -v ${MIGSSTATE_DIR}/wpa_supplicant.conf.bkp /etc/wpa_supplicant/wpa_supplicant.conf |& tee -a ${MIGSCRIPT_LOG} ${MIGCOMMAND_LOG} && \
        { 
            MIGSCRIPT_STATE="OK"
            touch ${MIGSSTATE_DIR}/MIG_BALENA_WPA_CONFIG_OK
            logEvent "WPA CONFIG"
            /sbin/wpa_supplicant -c/etc/wpa_supplicant/wpa_supplicant.conf -Dnl80211,wext -iwlan0 &>>${MIGSCRIPT_LOG}
        } || \
        { 
            MIGSCRIPT_STATE="ERROR"
            touch ${MIGSSTATE_DIR}/MIG_BALENA_WPA_CONFIG_FAIL
            logEvent "WPA CONFIG"
        }
    else
        MIGSCRIPT_STATE="FAIL"
        touch ${MIGSSTATE_DIR}/MIG_BALENA_WPA_CONFIG_NOT_FOUND
        logEvent "WPA CONFIG NOT FOUND"
    fi

    MIGSCRIPT_STATE="END"
    logEvent
    return 0
}

function migStateInit {
    MIGSCRIPT_STATE="INI"
    logEvent

    [[ -f ${MIGSSTATE_DIR}/MIG_BALENA_MOUNT_BOOT_OK ]] && rm -v ${MIGSSTATE_DIR}/MIG_BALENA_MOUNT_BOOT_OK &>>${MIGSCRIPT_LOG}
    [[ -f ${MIGSSTATE_DIR}/MIG_BALENA_MOUNT_BOOT_ERROR ]] && rm -v ${MIGSSTATE_DIR}/MIG_BALENA_MOUNT_BOOT_ERROR &>>${MIGSCRIPT_LOG}

    umount -v ${MIGBOOT_DEVICE} &>>${MIGSCRIPT_LOG}

    >${MIGCOMMAND_LOG}
    mount -vo ro ${MIGBOOT_DEVICE} ${MIGBOOT_MOUNTDIR} |& tee -a ${MIGSCRIPT_LOG} ${MIGCOMMAND_LOG} && \
    {
        MIGSCRIPT_STATE="OK"
        touch ${MIGSSTATEDIR_ROOT}/MIG_BALENA_MOUNT_BOOT_OK
        logEvent "BOOT mounted"
    } || \
    { 
        MIGSCRIPT_STATE="ERROR"
        touch ${MIGSSTATEDIR_ROOT}/MIG_BALENA_MOUNT_BOOT_ERROR
        logCommand
        logEvent "Can not mount BOOT"
    }

    ls -alh 

    if [[ -d ${MIGSSTATEDIR_BOOT} ]]; then
        touch ${MIGSSTATEDIR_ROOT}/MIG_BALENA_MIGSTATE_BOOT_FOUND

        if [[ -f ${MIGSSTATEDIR_BOOT}/${MIGCONFIG_FILE} ]]; then
            >${MIGCOMMAND_LOG}
            cp -v ${MIGSSTATEDIR_BOOT}/${MIGCONFIG_FILE} ${MIGSSTATEDIR_ROOT} &>>${MIGSCRIPT_LOG} && \
            {
                MIGSCRIPT_STATE="OK"
                touch ${MIGSSTATEDIR_ROOT}/MIG_BALENA_MIG_CONFIG_OK
                logEvent "copyed ${MIGCONFIG_FILE}"
            } || \
            {
                MIGSCRIPT_STATE="ERROR"
                touch ${MIGSSTATEDIR_ROOT}/MIG_BALENA_MIG_CONFIG_ERROR
                logCommand
                logEvent "Can not copy ${MIGCONFIG_FILE}"
            }
        else
            MIGSCRIPT_STATE="FAIL"
            touch ${MIGSSTATEDIR_ROOT}/MIG_BALENA_MIG_CONFIG_NOT_FOUND
            logEvent "${MIGCONFIG_FILE} NOT FOUND"
        fi

        migRestoreNetworkConfig
    else
        MIGSCRIPT_STATE="FAIL"
        touch ${MIGSSTATEDIR_ROOT}/MIG_BALENA_MIGSTATE_BOOT_NOT_FOUND_ERROR
        logEvent "${MIGSSTATEDIR_BOOT} NOT FOUND"
        ls -alh ${MIGBOOT_MOUNTDIR} &>>${MIGSCRIPT_LOG}
        echo "=============" &>>${MIGSCRIPT_LOG}
        ls -alh ${MIGSSTATEDIR_BOOT} &>>${MIGSCRIPT_LOG}
        echo "=============" &>>${MIGSCRIPT_LOG}
    fi

    if [[ -f ${MIGSSTATEDIR_ROOT}/MIG_BALENA_MOUNT_BOOT_OK ]]; then
        >${MIGCOMMAND_LOG}
        umount -v ${MIGBOOT_DEVICE} |& tee -a ${MIGSCRIPT_LOG} ${MIGCOMMAND_LOG} && \
        { 
            MIGSCRIPT_STATE="OK"
            touch ${MIGSSTATEDIR_ROOT}/MIG_BALENA_UMOUNT_BOOT_OK
            logEvent "UMOUNT BOOT"
        } || \
        { 
            MIGSCRIPT_STATE="ERROR"
            touch ${MIGSSTATEDIR_ROOT}/MIG_BALENA_UMOUNT_BOOT_ERROR
            logCommand
            logEvent "UMOUNT BOOT"
        }
    else
        MIGSCRIPT_STATE="FAIL";
        logEvent "MIG_BALENA_MOUNT_BOOT_OK NOT FOUND"
    fi

    # rsync -av ${MIGSSTATEDIR_ROOT} ${MIGBOOT_MOUNTDIR} |& tee -a ${MIGCOMMAND_LOG} ${MIGSCRIPT_LOG} && \
    # logEvent "ROOT -> BOOT" && \
    # rsync -av ${MIGSSTATEDIR_BOOT} /root |& tee -a ${MIGCOMMAND_LOG} ${MIGSCRIPT_LOG} && \
    # logEvent "BOOT -> ROOT" && \
    # logEvent "MIGSTATE_ROOT DIR UPDATED" && \
    # migRestoreNetworkConfig && \
    # MIGSCRIPT_STATE="OK" && \
    # rsync -av ${MIGSSTATEDIR_ROOT} ${MIGBOOT_MOUNTDIR} |& tee -a ${MIGSCRIPT_LOG} ${MIGSCRIPT_LOG} && \
    # logEvent "MIGSTATE_BOOT DIR UPDATED" && \
    # umount ${MIGBOOT_DEVICE} &>>${MIGCOMMAND_LOG} && \
    # logEvent "BOOT unmounted"  && \
    # touch ${MIGSSTATEDIR_ROOT}/MIG_BALENA_MIGSTATE_OK || \
    # {
    #     MIGSCRIPT_STATE="FAIL";
    #     logEvent;
    #     logCommand;
    #     migExitError;
    # }

    MIGSCRIPT_STATE="END"
    logEvent
    return 0
}

function migCreateRamdisk {
    MIGSCRIPT_STATE="INI"
    logEvent

    umount -v ${MIG_RAMDISK} &>>${MIGSCRIPT_LOG}

    >${MIGSCRIPT_LOG}
    mkdir -vp ${MIG_RAMDISK} |& tee -a ${MIGSCRIPT_LOG} ${MIGCOMMAND_LOG} && \
    rm -vrf ${MIG_RAMDISK}/* |& tee -a ${MIGSCRIPT_LOG} ${MIGCOMMAND_LOG} && \
    mount -vt tmpfs -o size=400M tmpramdisk ${MIG_RAMDISK} |& tee -a ${MIGSCRIPT_LOG} ${MIGCOMMAND_LOG} && \
    {
        MIGSCRIPT_STATE="OK"
        touch ${MIG_RAMDISK}/MIG_BALENA_RAMDISK_OK
        logEvent "RAMDISK"
    } || \
    { 
        MIGSCRIPT_STATE="ERROR"
        touch ${MIG_RAMDISK}/MIG_BALENA_RAMDISK_ERROR
        logCommand
        logEvent
        migExitError
    }

    MIGSCRIPT_STATE="END"
    logEvent
    return 0
}

function backupRaspbianBoot {
    MIGSCRIPT_STATE="INI"
    logEvent

    [[ -f ${MIGSSTATE_DIR}/MIG_BALENA_MOUNT_ROOTFS_OK ]] && rm -v ${MIGSSTATE_DIR}/MIG_BALENA_MOUNT_ROOTFS_OK &>>${MIGSCRIPT_LOG}
    [[ -f ${MIGSSTATE_DIR}/MIG_BALENA_MOUNT_ROOTFS_ERROR ]] && rm -v ${MIGSSTATE_DIR}/MIG_BALENA_MOUNT_ROOTFS_ERROR &>>${MIGSCRIPT_LOG}
    
    umount -v ${MIGROOTFS_DEVICE} &>>${MIGSCRIPT_LOG}

    >${MIGCOMMAND_LOG}
    mkdir -vp ${MIGROOTFS_MOUNTDIR} |& tee -a ${MIGSCRIPT_LOG} ${MIGCOMMAND_LOG} && \
    mount -vo ro ${MIGROOTFS_DEVICE} ${MIGROOTFS_MOUNTDIR} |& tee -a ${MIGSCRIPT_LOG} ${MIGCOMMAND_LOG} && \
    {
        MIGSCRIPT_STATE="OK"
        logEvent "ROOTFS mounted"
        touch ${MIGSSTATE_DIR}/MIG_BALENA_MOUNT_ROOTFS_OK
    } || \
    {
        MIGSCRIPT_STATE="ERROR"
        touch ${MIGSSTATE_DIR}/MIG_BALENA_MOUNT_ROOTFS_ERROR
        logCommand
        logEvent "Can not mount ROOTFS"
    }

    if [[ -f ${MIGROOTFS_MOUNTDIR}/root/${MIGBKP_RASPBIANBOOT} ]]; then
        >${MIGCOMMAND_LOG}
        cp -v ${MIGROOTFS_MOUNTDIR}/root/${MIGBKP_RASPBIANBOOT} /root |& tee -a ${MIGSCRIPT_LOG} ${MIGCOMMAND_LOG} && \
        { 
            MIGSCRIPT_STATE="OK"
            touch ${MIGSSTATEDIR_ROOT}/MIG_BALENA_CP_BKP_RASPBIAN_BOOT_OK
            logEvent "Copyed ${MIGBKP_RASPBIANBOOT}" 
        } || \
        { 
            MIGSCRIPT_STATE="ERROR"
            touch ${MIGSSTATEDIR_ROOT}/MIG_BALENA_CP_BKP_RASPBIAN_BOOT_ERROR
            logCommand
            logEvent "Can not Copy ${MIGBKP_RASPBIANBOOT}"
        }
    else
        MIGSCRIPT_STATE="FAIL";
        touch ${MIGSSTATEDIR_ROOT}/MIG_BALENA_BKP_RASPBIAN_BOOT_NOT_FOUND_FAIL
        logEvent "${MIGBKP_RASPBIANBOOT} NOT FOUND"
    fi

    if [[ -f ${MIGSSTATEDIR_ROOT}/MIG_BALENA_MOUNT_ROOTFS_OK ]]; then
        >${MIGCOMMAND_LOG}
        umount -v ${MIGROOTFS_MOUNTDIR} |& tee -a ${MIGSCRIPT_LOG} ${MIGCOMMAND_LOG} && \
        { 
            MIGSCRIPT_STATE="OK"
            touch ${MIGSSTATEDIR_ROOT}/MIG_BALENA_UMOUNT_ROOTFS_OK
            logEvent "UMOUNT ROOTFS"
        } || \
        { 
            MIGSCRIPT_STATE="ERROR"
            touch ${MIGSSTATEDIR_ROOT}/MIG_BALENA_UMOUNT_ROOTFS_ERROR
            logCommand
            logEvent "UMOUNT ROOTFS"
        }
    else
        MIGSCRIPT_STATE="FAIL";
        logEvent "MIG_BALENA_MOUNT_ROOTFS_OK NOT FOUND"
    fi

    MIGSCRIPT_STATE="END"
    logEvent
    return 0
}

function testBucketConnection {
    MIGSCRIPT_STATE="INI"

    [[ -f ${MIGSSTATE_DIR}/MIG_BALENA_NETWORK_ERROR ]] && rm ${MIGSSTATE_DIR}/MIG_BALENA_NETWORK_ERROR
    [[ -f ${MIGSSTATE_DIR}/MIGOS_NETWORK_OK ]] && rm ${MIGSSTATE_DIR}/MIGOS_NETWORK_OK

	until $(wget -q --tries=10 --timeout=10 --spider "${MIGBUCKET_URL}/${MIGBUCKET_FILETEST} &>>${MIGSCRIPT_LOG}"); do
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
    
    touch ${MIGSSTATE_DIR}/MIGOS_NETWORK_OK
    
    MIGSCRIPT_STATE="END"
    logEvent
    return 0
}

function updateStateFSM {
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
            gunzip -c ${MIG_FILE_RESIN_BOOT} | dd of=${MIGBOOT_DEVICE} bs=4M &>${MIGCOMMAND_LOG} || { logCommand; migExitError; }
            logEvent "BOOT - rm"
            rm ${MIG_FILE_RESIN_BOOT} &>${MIGCOMMAND_LOG} || { logCommand; migExitError; }
            touch ${MIGSSTATE_DIR}/MIG_FSM_BOOT_OK 
            logEvent "BOOT - [OK]"
            ;;
            
        'CONFIG')
            logEvent "CONFIG - Mount Boot"
            mkdir -p ${MIGBOOT_MOUNTDIR} && mount ${MIGBOOT_DEVICE} ${MIGBOOT_MOUNTDIR} &>${MIGCOMMAND_LOG} || { logCommand; migExitError; }
            logEvent "CONFIG - wget json"
            wget "${MIGBUCKET_URL}/$file_config_json" &>${MIGCOMMAND_LOG} || { logCommand; migExitError; }
            logEvent "CONFIG - cp json"
            cp $file_config_json ${MIGBOOT_MOUNTDIR}/config.json &>${MIGCOMMAND_LOG} || { logCommand; migExitError; }
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
    echo -e "\n\n" | tee -a ${MIGSCRIPT_LOG}
    echo -e "###############################################" | tee -a ${MIGSCRIPT_LOG}
    date | tee -a ${MIGSCRIPT_LOG}
    echo -e "" | tee -a ${MIGSCRIPT_LOG}
    
    MIGSCRIPT_STATE="INI"

	[[ ! -d ${MIGSSTATE_DIR} ]] && mkdir -p ${MIGSSTATE_DIR} && \
    logEvent "Missing ${MIGSSTATE_DIR} ... Created." || \
    logEvent
    
    [[ -f ${MIGSSTATE_DIR}/MIG_BALENA_ERROR ]] && rm -v ${MIGSSTATE_DIR}/MIG_BALENA_ERROR &>>${MIGSCRIPT_LOG}
    [[ -f ${MIGSSTATE_DIR}/MIG_BALENA_SUCCESS ]] && rm -v ${MIGSSTATE_DIR}/MIG_BALENA_SUCCESS &>>${MIGSCRIPT_LOG}

    # try to restore migstate config and network config
    [[ ! -f ${MIGSSTATE_DIR}/MIG_INIT_MIGSTATE_BOOT_FOUND ]] && migStateInit || \
    {
        MIGSCRIPT_STATE="OK"
        logEvent "/init was successfully completed"
    }

    # try to copy backup raspbian boot
    [[ ! -f /root/${MIGBKP_RASPBIANBOOT} ]] && backupRaspbianBoot || \
    {
        MIGSCRIPT_STATE="OK"
        logEvent "${MIGBKP_RASPBIANBOOT} found in /root"
    }

    if [[ ! -f ${MIGSSTATE_DIR}/${MIGCONFIG_FILE} ]]; then
        MIGSCRIPT_STATE="FAIL"
        logEvent "Missing ${MIGCONFIG_FILE}"
        ls -alh ${MIGSSTATE_DIR} &>${MIGCOMMAND_LOG}
        logCommand
        migExitError
    else 
        source ${MIGSSTATE_DIR}/${MIGCONFIG_FILE} || \
        { logCommand; migExitError; }
    fi

    testBucketConnection

    
    [[ ! -f ${MIG_RAMDISK}/MIG_INIT_RAMDISK_OK ]] && migCreateRamdisk || \
    {
        rm -rf ${MIG_RAMDISK}/* || { logCommand; migExitError; }
        MIGSCRIPT_STATE="OK";
        logEvent "${MIG_RAMDISK} was successfully mounted";
    }


    while [[ ! -f ${MIGSSTATE_DIR}/MIG_FSM_SUCCESS ]]; do
        updateStateFSM
        migrationFSM
        updateBootMigState
    done

    touch ${MIGSSTATE_DIR}/MIG_BALENA_SUCCESS

    MIGSCRIPT_STATE="END"
    logEvent "BALENA MIGRATION SUCCESS"
    
    echo -e "" | tee -a ${MIGSCRIPT_LOG}
    date | tee -a ${MIGSCRIPT_LOG}
    echo -e "***********************************************" | tee -a ${MIGSCRIPT_LOG}
    echo -e "\n\n" | tee -a ${MIGSCRIPT_LOG}
}


mig2Balena

#exec /sbin/reboot
# wget 10.0.0.211/balenaos/scripts/mig2balena.sh
# scp trecetp@fermi:~/RPI3/balena-migration-ramdisk/packages/mig2balena.service/mig2balena.sh /srv/http/balenaos/scripts/
