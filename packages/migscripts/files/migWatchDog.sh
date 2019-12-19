#!/bin/bash

MIGSSTATEDIR_BOOT="/boot/migstate"
MIGSSTATEDIR_ROOT="/root/migstate"
MIGSSTATE_DIR="${MIGSSTATEDIR_ROOT}"
MIGCOMMAND_LOG="${MIGSSTATE_DIR}/cmdwatch.log"
MIGSCRIPT_LOG="${MIGSSTATE_DIR}/migwatch.log"
MIGBKP_RASPBIANBOOT="migboot-backup-raspbian.tgz"

upSeconds="$(cat /proc/uptime | grep -o '^[0-9]\+')"
upMins=$((${upSeconds} / 60))


mkdir -p ${MIGSSTATE_DIR} &>/dev/null

function logCommand {
    if [[ -f ${MIGSSTATE_DIR}/MIG_BALENA_NETWORK_OK ]]; then
		echo "${BASH_SOURCE[1]##*/} | ${FUNCNAME[1]}[${BASH_LINENO[0]}] cmdlog : $1 " &>/dev/kmsg

		echo '{"device":"'"${MIGDID}"'", "stage":"'"${MIGSCRIPT_STAGE}"'", "event":"'"${MIGSCRIPT_EVENT}"'", "state":"'"CMDLOG"'", "msg":"['"${BASH_LINENO[0]}"'] ' | \
		cat - ${MIGCOMMAND_LOG} > temp.log && mv temp.log ${MIGCOMMAND_LOG}
		echo '"}' >> ${MIGCOMMAND_LOG} && cat ${MIGCOMMAND_LOG} &>> ${MIGSCRIPT_LOG}
        curl -X POST \
        -d "@${MIGCOMMAND_LOG}" \
        "${MIGWEBLOG_URL}/${MIGWEBLOG_KEYCOMMAND}"
	else
		echo "${BASH_SOURCE[1]##*/} | ${FUNCNAME[1]}[${BASH_LINENO[0]}] cmdlog : $1 " |& tee -a ${MIGSCRIPT_LOG} /dev/kmsg
    fi

    return 0
}

function logEvent {
    echo "${BASH_SOURCE[1]##*/} | ${FUNCNAME[1]}[${BASH_LINENO[0]}] event : $1 " |& tee -a ${MIGSCRIPT_LOG} /dev/kmsg
    
    if [[ -f ${MIGSSTATE_DIR}/MIG_BALENA_NETWORK_OK ]]; then
        echo '{"device":"'"${MIGDID}"'", "stage":"'"${BASH_SOURCE[1]##*/}"'", "event":"'"${FUNCNAME[1]}"'", "state":"'"${BASH_LINENO[0]}"'", "msg":"'"$1"'"}' | \
        tee -a /dev/tty | \
        curl -i -H "Accept: application/json" \
        -X POST \
        --data @- \
        "${MIGWEBLOG_URL}/${MIGWEBLOG_KEYEVENT}" &>${MIGCOMMAND_LOG} || logCommand
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
        rsync -av ${MIGSSTATEDIR_ROOT} ${MIGSSTATEDIR_BOOT} &>${MIGCOMMAND_LOG} && \
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

function restoreRaspianBoot {
	logEvent "INI"
	if [[ -f /root/${MIGBKP_RASPBIANBOOT} ]] ; then
		umount /dev/mmcblk0p1 &>/dev/null

		logEvent "mount" && \
		mount /dev/mmcblk0p1 /mnt/boot &>${MIGCOMMAND_LOG} && \
		logEvent "rm all" && \
		rm -rf /mnt/boot/* &>>${MIGCOMMAND_LOG} && \
		logEvent "tar -x" && \
		tar -xzf /root/${MIGBKP_RASPBIANBOOT} -C /mnt &>>${MIGCOMMAND_LOG} && \
		logEvent "cp migstate" && \
		cp -r ${MIGSSTATE_DIR} /mnt/boot/ &>>${MIGCOMMAND_LOG} && \
		logEvent "reboot" && \
		{
			reboot;
			sleep 10;
		} || \
		{
			logCommand
		}
	else
		logEvent "Missing: /root/${MIGBKP_RASPBIANBOOT}"
	fi
	logEvent "END"
}

# # curl -s http://server/path/script.sh | bash -s arg1 arg2
until [[ ! -f ${MIGSSTATE_DIR}/MIG_FSM_SUCCESS ]]; do
	if [[ -f ${MIGSSTATE_DIR}/MIG_BALENA_FAIL ]] && [[ -f ${MIGSSTATE_DIR}/MIG_BALENA_NETWORK_ERROR ]]; then
		if [[ ! -f ${MIGSSTATE_DIR}/MIG_FSM_SFDISK_OK ]]; then 
			restoreRaspianBoot
		else
			restoreMigosBoot
		fi
	fi
    sleep 10
done


# # server_path='http://10.0.0.210/balenaos'
# server_path='https://storage.googleapis.com/balenamigration'
# file_test_conection='balenamigration'
# file_resin_sfdisk='resin-partitions-60.sfdisk.gz'
# file_resin_rootA='p2-resin-rootA.img.gz'
# file_resin_rootB='p3-resin-rootB.img.gz'
# file_resin_state='p5-resin-state.img.gz'
# file_resin_data='p6-resin-data.img.gz'
# file_resin_boot='p1-resin-boot-60.img.gz'
# file_config_json='testMigration.config.json'
# attempt_counter=0
# max_attempts=5

# function logmsg {
# 	echo $1 | tee /dev/kmsg | tee -a /tmp/logBalenaMigration
# 	# echo "Log message: $1" >&2
# 	return 0
# }

# logmsg "BalenaMigration: Init [OK]"
# touch /tmp/balenaMigration_Init

# mkdir -p /tmp/ramdisk && mount -t tmpfs -o size=400M tmpramdisk /tmp/ramdisk && cd /tmp/ramdisk && \
# logmsg "BalenaMigration: Ramdisk [OK]"
# touch /tmp/balenaMigration_Ramdisk

# # until $(curl --output /dev/null --silent --head --fail 10.0.0.210/balenaos/balenamigration); do
# until $(wget -q --tries=10 --timeout=10 --spider "$server_path/$file_test_conection"); do
# 	if [ ${attempt_counter} -eq ${max_attempts} ];then
# 		logmsg "BalenaMigration: Network [ERROR]"
# 		touch /tmp/balenaMigration_Network_ERROR
# 		exit 1
#     fi

#     attempt_counter=$(($attempt_counter+1))
# 	logmsg "BalenaMigration: Network attempt ${attempt_counter} [FAIL]"
#     sleep 10
# done

# wget --spider "$server_path/$file_test_conection"

# if [[ $? -eq 0 ]]; then
# 	logmsg "BalenaMigration: Network [OK]"
# 	touch /tmp/balenaMigrationNetwork_OK
	
# 	wget "$server_path/$file_resin_sfdisk" && gunzip -c $file_resin_sfdisk | sfdisk /dev/mmcblk0 && rm $file_resin_sfdisk && \
# 	logmsg "BalenaMigration: sfdisk [OK]" && \
# 	wget "$server_path/$file_resin_rootA" && gunzip -c $file_resin_rootA | dd of=/dev/mmcblk0p2 status=progress bs=4M && rm $file_resin_rootA && \
# 	logmsg "BalenaMigration: RootA [OK]" && \
# 	wget "$server_path/$file_resin_rootB" && gunzip -c $file_resin_rootB | dd of=/dev/mmcblk0p3 status=progress bs=4M && rm $file_resin_rootB && \
# 	logmsg "BalenaMigration: RootB [OK]" && \
# 	wget "$server_path/$file_resin_state" && gunzip -c $file_resin_state | dd of=/dev/mmcblk0p5 status=progress bs=4M && rm $file_resin_state && \
# 	logmsg "BalenaMigration: State [OK]" && \
# 	wget "$server_path/$file_resin_data"  && gunzip -c $file_resin_data  | dd of=/dev/mmcblk0p6 status=progress bs=4M && rm $file_resin_data && \
# 	logmsg "BalenaMigration: Data [OK]" && \
# 	wget "$server_path/$file_resin_boot"  && gunzip -c $file_resin_boot  | dd of=/dev/mmcblk0p1 status=progress bs=4M && rm $file_resin_boot && \
# 	logmsg "BalenaMigration: Boot [OK]" && \
# 	mkdir -p /mnt/boot && mount /dev/mmcblk0p1 /mnt/boot/ && wget "$server_path/$file_config_json" && cp $file_config_json /mnt/boot/config.json && \
# 	logmsg "BalenaMigration: Config [OK]" && \
# 	logmsg "BalenaMigration: End [OK]" && \
# 	touch /tmp/balenaMigration_Successful || \
# 	logmsg "BalenaMigration: End [FAIL]"
# else
# 	logmsg "BalenaMigration: Network [FAIL]"
# 	touch /tmp/balenaMigration_Network_FAIL
# fi

# logmsg "BalenaMigration: Finish [OK]"
# touch /tmp/balenaMigration_Finish

# sleep 10

# #exec /sbin/reboot
