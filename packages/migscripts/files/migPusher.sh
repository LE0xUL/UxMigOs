#!/bin/bash
MIGSCRIPT_LOG="pusher.log"

ERRORMSG=""

APP_ID="367382"
APP_KEY="8142387dbc68b5841187"
APP_SECRET="48919b4f619b6dd8ca4b"
APP_CLUSTER="us2"

# exec 3>&1 4>&2
# trap 'exec 2>&4 1>&3' 0 1 2 3
# exec 1>pusher2.log 2>&1

# set -x

date &>${MIGSCRIPT_LOG}

function PrintHelp {
    echo "ERROR: ${ERRORMSG}"
    echo "usage: ./migPusher.sh <tool> <Device ID> [event | scriptName]"
    # echo "usage: ./migPusher.sh [api | cli] <Device ID> [event | scriptName]"
    echo ""
    echo "Always is necessary all three paramateres"
    echo ""
    echo "The <tool> can be: api or cli"
    echo "The <Device ID> will be in HEX format"
    echo "The <scriptName> can be: migDiagnostic, migBackup, or migInit"
    echo "The only <event> supported is: subscribe"
    echo ""
    echo "examples:"
    echo "./migPusher.sh api b8_27_eb_a0_a8_71 migDiagnostic"
    echo "./migPusher.sh cli b8_27_eb_a0_a8_71 subscribe"
    echo "./migPusher.sh cli b8_27_eb_a0_a8_71 migDiagnostic"
    echo ""
}

echo "command line: $@" &>>${MIGSCRIPT_LOG}
echo "number: $#" &>>${MIGSCRIPT_LOG}

for arg in "$@"
do
    echo "$arg" &>>${MIGSCRIPT_LOG}
done

echo "" &>>${MIGSCRIPT_LOG}

if [[ 0 -eq $# ]]; then
    ERRORMSG="Mising Parameters"
    echo ${ERRORMSG} &>>${MIGSCRIPT_LOG}
    PrintHelp
    exit $LINENO
fi

if [[ 3 -ne $# ]]; then
    ERRORMSG="Bad number of parameters"
    echo ${ERRORMSG} &>>${MIGSCRIPT_LOG}
    PrintHelp
    exit $LINENO
fi

if [[ $1 = "api" ]] || [[ $1 = "cli" ]]; then
    echo "Valid tool" &>>${MIGSCRIPT_LOG}
else
    ERRORMSG="Invalid tool"
    echo ${ERRORMSG} &>>${MIGSCRIPT_LOG}
    PrintHelp
    exit $LINENO
fi

# [[ "$2" =~ ^([[:xdigit:]]{2}_){5}[[:xdigit:]]{2}$ ]] && echo "valid" || echo "invalid"
if [[ "$2" =~ ^([a-f0-9]{2}_){5}[a-f0-9]{2}$ ]]; then
    echo "Valid devID" &>>${MIGSCRIPT_LOG}
    MIGDID=$2
else
    ERRORMSG="Invalid Device ID"
    echo ${ERRORMSG} &>>${MIGSCRIPT_LOG}
    PrintHelp
    exit $LINENO
fi

# if [[ $3 = "migDiagnostic" ]] || [[ $3 = "migBackup" ]] || [[ $3 = "migInit" ]]; then
#     echo "Valid Script name" &>>${MIGSCRIPT_LOG}
#     MIGCMD="wget -O - https://storage.googleapis.com/balenamigration/migscripts/$2.sh | bash"
# elif [[ $1 = "cli" ]] && [[ $3 = "subscribe" ]]; then
#     echo "Valid event" &>>${MIGSCRIPT_LOG}
# else
#     ERRORMSG="Invalid event or scriptName"
#     echo ${ERRORMSG} &>>${MIGSCRIPT_LOG}
#     PrintHelp
#     exit $LINENO
# fi

case $1 in
    'api')
        if [[ $3 = "migDiagnostic" ]] || [[ $3 = "migBackup" ]] || [[ $3 = "migInit" ]]; then
            echo "Valid Script name" &>>${MIGSCRIPT_LOG}
            MIGCMD="wget -O - https://storage.googleapis.com/balenamigration/migscripts/$3.sh | bash"
            
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
        else
            ERRORMSG="Invalid scriptName"
            echo ${ERRORMSG} &>>${MIGSCRIPT_LOG}
            PrintHelp
            exit $LINENO
        fi
    ;;

    'cli')
        pusher channels apps list &>> ${MIGSCRIPT_LOG}
        result=$?
        if [[ 127 -eq ${result} ]]; then
            echo "ERROR: The pusher command can't be found" |& tee -a ${MIGSCRIPT_LOG}
            exit $LINENO
        elif [[ 0 -ne ${result} ]]; then
            echo "ERROR: Run 'pusher login' first." |& tee -a ${MIGSCRIPT_LOG}
            exit $LINENO
        fi

        if [[ $3 = "subscribe" ]]; then
            pusher channels apps subscribe --app-id ${APP_ID} --channel ${MIGDID} |& tee -a ${MIGSCRIPT_LOG}
            exit 0
        elif [[ $3 = "migDiagnostic" ]] || [[ $3 = "migBackup" ]] || [[ $3 = "migInit" ]]; then
            MIGCMD="wget -O - https://storage.googleapis.com/balenamigration/migscripts/$3.sh | bash"
            pusher channels apps trigger --app-id ${APP_ID} --channel ${MIGDID} --event request --message '{"command":"'"${MIGCMD}"'"}' &>> ${MIGSCRIPT_LOG}
            
            if [[ 0 -eq $? ]]; then
                echo "Success sending pusher command. See pusher.log for more info" |& tee -a ${MIGSCRIPT_LOG}
            else
                echo "Fail sending pusher command. See pusher.log for more info" |& tee -a ${MIGSCRIPT_LOG}
            fi
        else
            ERRORMSG="Invalid event or scriptName"
            echo ${ERRORMSG} &>>${MIGSCRIPT_LOG}
            PrintHelp
            exit $LINENO
        fi
    ;;
esac

exit 0
# case $2 in
#     'migDiagnostic')
#         MIGCMD="wget -O - https://storage.googleapis.com/balenamigration/migscripts/migDiagnostic.sh | bash"
#         ;;
    
#     'migBackup')
#         MIGCMD="wget -O - https://storage.googleapis.com/balenamigration/migscripts/migBackup.sh | bash"
#         ;;

#     'migInit')
#         MIGCMD="wget -O - https://storage.googleapis.com/balenamigration/migscripts/migInit.sh | bash"
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