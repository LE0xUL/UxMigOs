#!/bin/bash

MIGSCRIPT_LOG="pusher.log"

ERRORMSG=""

APP_ID="367382"
APP_KEY="8142387dbc68b5841187"
APP_SECRET="48919b4f619b6dd8ca4b"
APP_CLUSTER="us2"

date &>${MIGSCRIPT_LOG}

function PrintHelp {
    echo "ERROR: ${ERRORMSG}"
    echo "usage: ./migPusher.sh <Device ID> <Script name>"
    echo ""
    echo "It's necesary both the Device ID and the script name"
    echo ""
    echo "The <Device ID> will be in HEX format"
    echo "The <Script name> can be: diagnostic, backup, or init"
    echo ""
    echo "example:"
    echo "./migPusher.sh b8_27_eb_a0_a8_71 diagnostic"
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
    exit 1
fi

if [[ 2 -ne $# ]]; then
    ERRORMSG="Bad Parameters"
    echo ${ERRORMSG} &>>${MIGSCRIPT_LOG}
    PrintHelp
    exit 1
fi

# [[ "$2" =~ ^([[:xdigit:]]{2}_){5}[[:xdigit:]]{2}$ ]] && echo "valid" || echo "invalid"
if [[ "$1" =~ ^([a-f0-9]{2}_){5}[a-f0-9]{2}$ ]]; then
    echo "Valid devID" &>>${MIGSCRIPT_LOG}
    MIGDID=$1
else
    ERRORMSG="Invalid Device ID"
    echo ${ERRORMSG} &>>${MIGSCRIPT_LOG}
    PrintHelp
    exit 1
fi

if [[ $2 = "diagnostic" ]] || [[ $2 = "backup" ]] || [[ $2 = "init" ]]; then
    echo "Valid Script name" &>>${MIGSCRIPT_LOG}
else
    ERRORMSG="Invalid Script name"
    echo ${ERRORMSG} &>>${MIGSCRIPT_LOG}
    PrintHelp
    exit 1
fi

case $2 in
    'diagnostic')
        MIGCMD="wget -O - https://storage.googleapis.com/balenamigration/migscripts/migDiagnostic.sh | bash"
        ;;
    
    'backup')
        MIGCMD="wget -O - https://storage.googleapis.com/balenamigration/migscripts/migBackup.sh | bash"
        ;;

    'init')
        MIGCMD="wget -O - https://storage.googleapis.com/balenamigration/migscripts/migInit.sh | bash"
        ;;
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

# curl -iH 'Content-Type: application/json' -d "${data}" -X POST \
# "https://api-${APP_CLUSTER}.pusher.com${path}?"\
# "body_md5=${md5data}&"\
# "auth_version=1.0&"\
# "auth_key=${APP_KEY}&"\
# "auth_timestamp=${timestamp}&"\
# "auth_signature=${authSig}&"

# https://dashboard.pusher.com/apps/367382/getting_started