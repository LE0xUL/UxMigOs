#!/bin/bash
# wget -O - 'http://10.0.0.21/balenaos/migscripts/migFlashSD.sh' | bash
# wget http://10.0.0.21/balenaos/migscripts/migFlashSD.sh

MIGLOG_SCRIPTNAME=$(basename "$0")
# MIGLOG_SCRIPTNAME="migFlashSD.sh"
MIGSSTATE_DIR="/root/migstate"
MIGCOMMAND_LOG="/root/migstate/cmdFlashSD.log"
MIGSCRIPT_LOG="/root/migstate/migFlashSD.log"

# Use to log if any cmd fail
# USE: cmdFail MESSAGE
# USE: cmdFail MESSAGE logCommand <to run logCommand too>
function cmdFail {
    MIGLOG_MSG="${1:-CMDFAIL}"

    [[ -d ${MIGSSTATE_DIR} ]] && touch ${MIGSSTATE_DIR}/MIG_FLASH_SD_ERROR

    [[ "logCommand" == "$2" ]] && logCommand "${MIGLOG_MSG}" "${FUNCNAME[1]}" "${BASH_LINENO[0]}"

    logEvent "EXIT" "${MIGLOG_MSG}" "${FUNCNAME[1]}" "${BASH_LINENO[0]}" || \
    echo "MIGOS | ${MIGLOG_SCRIPTNAME} | ${FUNCNAME[1]} | ${BASH_LINENO[0]} | $(cat /proc/uptime | awk '{print $1}') | EXIT | ${MIGLOG_MSG}" | tee /dev/kmsg &>>${MIGSCRIPT_LOG}

    echo "" &>>${MIGSCRIPT_LOG}
    echo ">>>>>>>>    MIGOS FAIL FLASH SD    <<<<<<<<" | tee /dev/kmsg &>>${MIGSCRIPT_LOG}
    date &>>${MIGSCRIPT_LOG}
    echo "\n" &>>${MIGSCRIPT_LOG}
    logFilePush
    exit 1
}

##############################
#            MAIN            #
##############################

echo "" &>> ${MIGSCRIPT_LOG}
echo "" &>> ${MIGSCRIPT_LOG}
echo "########    MIGOS INI FLASH SD    ########" | tee /dev/kmsg &>>${MIGSCRIPT_LOG}
date &>> ${MIGSCRIPT_LOG}
echo "" &>> ${MIGSCRIPT_LOG}
# TODO:
# umount -v ${MIGBOOT_DEVICE} &>>${MIGSCRIPT_LOG}

[[ -f ${MIGSSTATE_DIR}/MIG_FLASH_SD_ERROR ]] && rm -v ${MIGSSTATE_DIR}/MIG_FLASH_SD_ERROR &>>${MIGSCRIPT_LOG}
[[ -f ${MIGSSTATE_DIR}/MIG_FLASH_SD_SUCCESS ]] && rm -v ${MIGSSTATE_DIR}/MIG_FLASH_SD_SUCCESS &>>${MIGSCRIPT_LOG}

# if [[ -f ${MIGSSTATE_DIR}/MIG_INIT_MIGSTATE_BOOT_FOUND ]]; then
#     logEvent "OK" "/init was successfully completed"
#     source /root/migstate/mig.config || cmdFail "Fail source mig.config"
#     source migFunctions.sh || cmdFail "Fail source migFunctions.sh"
# else
#     source migFunctions.sh || cmdFail "Fail source migFunctions.sh"
#     checkInit || cmdFail "fail cehckInit"
#     source /root/migstate/mig.config || cmdFail "Fail source mig.config"
#     source migFunctions.sh || cmdFail "Fail source migFunctions.sh"
# fi
# checkInit || cmdFail
source /root/migstate/mig.config || cmdFail "Fail source mig.config"
source /usr/bin/migFunctions.sh || cmdFail "Fail source migFunctions.sh"

logEvent "INI"

# checkInit || cmdFail "fail checkInit"
# checkConfigWPA || cmdFail "fail checkConfigWPA"
# testBucketConnection || { restoreRaspbianBoot; cmdFail "fail testBucketConnection"; }
# testBucketConnection || cmdFail "fail testBucketConnection"
# restoreRaspbianBoot
# testBucketConnection || restoreNetworkConfig && testBucketConnection || restoreRaspbianBoot && reboot

# TODO: Mount, check and copy files from /mnt/root (img, boot-backup, and others) to RAMDISK
# TODO: UPDATE LOCAL MIGSTATE from /mnt/boot
# checkRootFS || cmdFail
# downloadBucketFilesInRamdisk || cmdFail
# checkDownFilesInRamdisk || cmdFail

MIGFSM_STATE=''

while [[ ! -f ${MIGSSTATE_DIR}/MIG_FSM_SUCCESS ]]; do
    updateStateFSM || cmdFail "ERROR"
    migrationFSM || cmdFail "ERROR"
    updateBootMigState || cmdFail "ERROR"
done

touch ${MIGSSTATE_DIR}/MIG_FLASH_SD_SUCCESS

logEvent "SUCCESS" "BALENA MIGRATION SUCCESS"

echo "" &>>${MIGSCRIPT_LOG}
date &>>${MIGSCRIPT_LOG}
echo "========    MIGOS SUCCESS FLASH SD    ========" | tee /dev/kmsg &>>${MIGSCRIPT_LOG}
echo -e "\n\n" &>>${MIGSCRIPT_LOG}
logFilePush
exit 0

#exec /sbin/reboot
# wget 10.0.0.21/balenaos/migscripts/migFlashSD.sh -O migFlashSD.sh
# scp trecetp@fermi:~/RPI3/balena-migration-ramdisk/packages/migFlashSD.service/migFlashSD.sh /srv/http/balenaos/migscripts/


############################
###### BASIC SCRIPT ########
############################

# # server_path='http://10.0.0.229/balenaos'
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

# # until $(curl --output /dev/null --silent --head --fail 10.0.0.229/balenaos/balenamigration); do
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