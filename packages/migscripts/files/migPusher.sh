#!/bin/bash

# TODO
# - weblogs events to logentries
# - send logfile to transfer and weblog

MIGSCRIPT_LOG="pusher.log"
APP_ID="367382"
APP_KEY="8142387dbc68b5841187"
APP_SECRET="48919b4f619b6dd8ca4b"
APP_CLUSTER="us2"
API_KEY='-aP8iW3jzXcNxoHIGFlrrVIsTOkQiK5Y3gopCYJhLCQ'

# MIGBUCKET_URL='http://10.0.0.21/balenaos'
MIGBUCKET_URL='https://storage.googleapis.com/balenamigration'

# exec 3>&1 4>&2
# trap 'exec 2>&4 1>&3' 0 1 2 3
# exec 1>pusher2.log 2>&1

# set -x

date &>${MIGSCRIPT_LOG}

function PrintHelp {
    echo ""
    echo "Usage: ./migPusher.sh <tool> <Device ID> [event | scriptName]"
    # echo "usage: ./migPusher.sh [api | cli] <Device ID> [event | scriptName]"
    echo ""
    echo "Always is necessary all three paramateres"
    echo ""
    echo "The <tool> can be: api or cli"
    echo "The <Device ID> will be in HEX format"
    echo "The <scriptName> can be: Diagnostic, InstallMIGOS"
    echo "The <event> can be: subscribe"
    echo ""
    echo "Usage examples:"
    echo "./migPusher.sh api b8_27_eb_a0_a8_71 Diagnostic"
    echo "./migPusher.sh cli b8_27_eb_a0_a8_71 subscribe"
    echo "./migPusher.sh cli b8_27_eb_a0_a8_71 Diagnostic"
    echo ""
}

function exitError {
    PrintHelp
    echo "EXIT | ${FUNCNAME[1]}[${BASH_LINENO[0]}]: $1" | tee -a ${MIGSCRIPT_LOG}
    exit $LINENO
}

echo "command line: $@" &>>${MIGSCRIPT_LOG}
echo "number: $#" &>>${MIGSCRIPT_LOG}

for arg in "$@"
do
    echo "$arg" &>>${MIGSCRIPT_LOG}
done

echo "" &>>${MIGSCRIPT_LOG}

[[ 0 -eq $# ]] && exitError "Mising Parameters"
[[ 3 -ne $# ]] && exitError "Bad number of parameters"

# [[ "$2" =~ ^([[:xdigit:]]{2}_){5}[[:xdigit:]]{2}$ ]] && echo "valid" || echo "invalid"
if [[ "$2" =~ ^([a-f0-9]{2}_){5}[a-f0-9]{2}$ ]]; then
    echo "Valid devID" &>>${MIGSCRIPT_LOG}
    MIGDID=$2
else
    exitError "Invalid Device ID"
fi

# if [[ $3 = "migDiagnostic" ]] || [[ $3 = "migInstallMIGOS" ]] || [[ $3 = "migRestoreRaspbBoot" ]]; then
#     echo "Valid Script name" &>>${MIGSCRIPT_LOG}
#     MIGCMD="wget -O - https://storage.googleapis.com/balenamigration/migscripts/$2.sh | bash"
# elif [[ $1 = "cli" ]] && [[ $3 = "subscribe" ]]; then
#     echo "Valid event" &>>${MIGSCRIPT_LOG}
# else
#     exitError "Invalid event or scriptName"
#     echo ${ERRORMSG} &>>${MIGSCRIPT_LOG}
#     PrintHelp
#     exit $LINENO
# fi

case $1 in
    'api')
        case $3 in
            "Diagnostic"|"InstallMIGOS"|"RestoreRaspbBoot")
                echo "Valid Script name: $3" &>>${MIGSCRIPT_LOG}
                MIGCMD="cd /tmp && \
                wget ${MIGBUCKET_URL}/migscripts/mig$3.sh -O mig$3.sh && \
                wget ${MIGBUCKET_URL}/migscripts/mig$3.sh.md5 -O mig$3.sh.md5 && \
                md5sum --check mig$3.sh.md5 && \
                bash mig$3.sh"
            ;;
            "reboot")
                echo "Valid event name: $3" &>>${MIGSCRIPT_LOG}
                MIGCMD="[ ! -f /root/migstate/MIG_DIAGNOSTIC_IS_RUNING ] && \
                [ ! -f /root/migstate/MIG_INSTALL_MIGOS_IS_RUNING ] && \
                [ ! -f /root/migstate/MIG_RESTORE_RASPB_BOOT_IS_RUNING ] && \
                reboot"
            ;;
            "subscribe")
                exitError "Subscribe event is not suportted with api <tool>" 
            ;;              
            *)
                exitError "Invalid <event> or <scriptName>"
        esac

        timestamp=$(date +%s)
        echo "timestamp: $timestamp" &>>${MIGSCRIPT_LOG}

        # data='{"data":"{\"message\":\"Hola!!!\"}","name":"my-event","channel":"my-channel"}'
        data='{"name":"request","channel":"'"${MIGDID}"'","data":"{\"command\":\"'"${MIGCMD}"'\"}"}'
        echo "data: $data" &>>${MIGSCRIPT_LOG}

        # Be sure to use `printf %s` to prevent a trailing \n from being added to the data.
        md5data=$(printf '%s' "$data" | md5sum | awk '{print $1;}')
        echo "md5data: ${md5data}" &>>${MIGSCRIPT_LOG}

        path="/apps/${APP_ID}/events"
        echo "path: ${path}" &>>${MIGSCRIPT_LOG}

        queryString="auth_key=${APP_KEY}&auth_timestamp=${timestamp}&auth_version=1.0&body_md5=${md5data}"
        echo "queryString: $queryString" &>>${MIGSCRIPT_LOG}

        # Be sure to use a multi-line, double quoted string that doesn't end in \n as 
        # input for the SHA-256 HMAC.
        authSig=$(printf '%s' "POST
$path
$queryString" | openssl dgst -sha256 -hex -hmac "${APP_SECRET}" | awk '{print $2;}')
        echo "auth_signature: ${authSig}" &>>${MIGSCRIPT_LOG}

        curl -vH "Content-Type: application/json" -d "$data" "https://api-${APP_CLUSTER}.pusher.com${path}?${queryString}&auth_signature=${authSig}" &>>${MIGSCRIPT_LOG}
        
        echo "Data has been sent to pusher. See pusher.log for more info" |& tee -a ${MIGSCRIPT_LOG}
    ;;

    'cli')
        pusher channels apps list &>> ${MIGSCRIPT_LOG}
        result=$?

        if [[ 127 -eq ${result} ]]; then
            exitError "The pusher command can't be found"
        elif [[ 0 -ne ${result} ]]; then
            # echo "ERROR: Run 'pusher login' first." |& tee -a ${MIGSCRIPT_LOG}
            # exit $LINENO
            echo "Try login to pusher" &>> ${MIGSCRIPT_LOG}
            ( echo ${API_KEY} ) | pusher login &>> ${MIGSCRIPT_LOG}
            if [[ 0 -ne $? ]]; then
                exitError "Can't login in pusherCLI"
            fi
        fi

        case $3 in
            "Diagnostic"|"InstallMIGOS"|"RestoreRaspbBoot")
                echo "Valid Script name: $3" &>>${MIGSCRIPT_LOG}
                MIGCMD="cd /tmp && \
                wget ${MIGBUCKET_URL}/migscripts/mig$3.sh -O mig$3.sh && \
                wget ${MIGBUCKET_URL}/migscripts/mig$3.sh.md5 -O mig$3.sh.md5 && \
                md5sum --check mig$3.sh.md5 && \
                bash mig$3.sh"
            ;;
            "reboot")
                echo "Valid event name: $3" &>>${MIGSCRIPT_LOG}
                MIGCMD="[ ! -f /root/migstate/MIG_DIAGNOSTIC_IS_RUNING ] && \
                [ ! -f /root/migstate/MIG_INSTALL_MIGOS_IS_RUNING ] && \
                [ ! -f /root/migstate/MIG_RESTORE_RASPB_BOOT_IS_RUNING ] && \
                reboot"
            ;;
            "subscribe")
                pusher channels apps subscribe --app-id ${APP_ID} --channel ${MIGDID} |& tee -a ${MIGSCRIPT_LOG}
                exit 0
            ;;
            *)
                exitError "Invalid <event> or <scriptName>"
        esac

        pusher channels apps trigger --app-id ${APP_ID} --channel ${MIGDID} --event request --message '{"command":"'"${MIGCMD}"'"}' &>> ${MIGSCRIPT_LOG}
            
        if [[ 0 -eq $? ]]; then
            echo "Success sending pusher command. See pusher.log for more info" |& tee -a ${MIGSCRIPT_LOG}
        else
            echo "Fail sending pusher command. See pusher.log for more info" |& tee -a ${MIGSCRIPT_LOG}
        fi
    ;;
    *)
        exitError "Invalid tool"
esac

exit 0
# case $2 in
#     'migDiagnostic')
#         MIGCMD="wget -O - https://storage.googleapis.com/balenamigration/migscripts/migDiagnostic.sh | bash"
#         ;;
    
#     'migInstallMIGOS')
#         MIGCMD="wget -O - https://storage.googleapis.com/balenamigration/migscripts/migInstallMIGOS.sh | bash"
#         ;;

#     'migRestoreRaspbBoot')
#         MIGCMD="wget -O - https://storage.googleapis.com/balenamigration/migscripts/migRestoreRaspbBoot.sh | bash"
#         ;;
# esac

# curl -iH 'Content-Type: application/json' -d "${data}" -X POST \
# "https://api-${APP_CLUSTER}.pusher.com${path}?"\
# "body_md5=${md5data}&"\
# "auth_version=1.0&"\
# "auth_key=${APP_KEY}&"\
# "auth_timestamp=${timestamp}&"\
# "auth_signature=${authSig}&"

# pusher channels apps trigger --app-id 367382 --channel b8_27_eb_a0_a8_71 --event request --message '{"command":"echo puscherCLI2 > /dev/kmsg"}'
# --app-id 367382 --channel my-channel --event my-event --message 'Hola CLI'
# pusher channels apps trigger --app-id 367382 --channel my-channel --event my-event --message '{"message":"hello world"}'

# curl -H 'Content-Type: application/json' -d '{"data":"{\"message\":\"hello world\"}","name":"my-event","channel":"my-channel"}' \
# "https://api-us2.pusher.com/apps/367382/events?"\
# "body_md5=2c99321eeba901356c4c7998da9be9e0&"\
# "auth_version=1.0&"\
# "auth_key=8142387dbc68b5841187&"\
# "auth_timestamp=1579131255&"\
# "auth_signature=479810b50ba68f876c051e20783d34acd549c0b67f55570f650b0dba012189cc&"

# https://dashboard.pusher.com/apps/367382/getting_started