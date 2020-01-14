#!/bin/bash

appID="367382"
key="8142387dbc68b5841187"
secret="48919b4f619b6dd8ca4b"
cluster="us2"

timestamp=$(date +%s)
echo "timestamp: $timestamp"

data='{"name":"request","channel":"b8_27_eb_a0_a8_71","data":"{\"command\":\"hostname\"}"}'
# data='{"data":"{\"message\":\"Hola!!!\"}","name":"my-event","channel":"my-channel"}'
echo "data: $data"

# Be sure to use `printf %s` to prevent a trailing \n from being added to the data.
md5data=$(printf '%s' "$data" | md5sum | awk '{print $1;}')
echo "md5data: ${md5data}"

path="/apps/${appID}/events"
queryString="auth_key=${key}&auth_timestamp=${timestamp}&auth_version=1.0&body_md5=${md5data}"
echo "queryString: $queryString"

# Be sure to use a multi-line, double quoted string that doesn't end in \n as 
# input for the SHA-256 HMAC.
authSig=$(printf '%s' "POST
$path
$queryString" | openssl dgst -sha256 -hex -hmac "$secret" | awk '{print $2;}')
echo "auth_signature: ${authSig}"

# curl -i -H "Content-Type: application/json" -d "$data" "https://api-${cluster}.pusher.com${path}?${queryString}&auth_signature=${authSig}"
# curl -vH "Content-Type: application/json" -d "$data" "http://api.pusherapp.com${path}?${queryString}&auth_signature=${authSig}"
# curl -v -H "Content-Type:application/json" -d "$data" -X POST "https://api-${cluster}.pusher.com${path}?${queryString}&auth_signature=${authSig}"
# curl -v -H "Content-Type: application/json" -d "event%5Bchannel=b8_27_eb_a0_a8_71&event%5Bevent_name%5D=request&event%5Bdata%5D=%7B%0D%0A++%22command%22%3A+%22pwd%22%0D%0A%7D" "https://api-${cluster}.pusher.com${path}?${queryString}&auth_signature=${authSig}"

curl -iH 'Content-Type: application/json' -d "${data}" -X POST \
"https://api-${cluster}.pusher.com${path}?"\
"body_md5=${md5data}&"\
"auth_version=1.0&"\
"auth_key=${key}&"\
"auth_timestamp=${timestamp}&"\
"auth_signature=${authSig}&"

# curl -vH 'Content-Type: application/json' -d '{"data":"{\"message\":\"hello world\"}","name":"my-event","channel":"my-channel"}' \
# "https://api-us2.pusher.com/apps/367382/events?"\
# "body_md5=2c99321eeba901356c4c7998da9be9e0&"\
# "auth_version=1.0&"\
# "auth_key=8142387dbc68b5841187&"\
# "auth_timestamp=1579023829&"\
# "auth_signature=54c431255cf7b5fccaff0c0595d6e4e165545d1fa3b867d5409efbdef98a5684&"

# curl -vH "Content-Type: application/json" -d '{"name":"request","channel":"b8_27_eb_a0_a8_71","data":"{\"command\":\"hostname\"}"}' "http://api.pusherapp.com/apps/367382/events?auth_key=8142387dbc68b5841187&auth_timestamp=1579022230&auth_version=1.0&body_md5=774aa2ad36d6044d4661b78e95187390&auth_signature=c2560809d6cab2f48c8822159d0abf5f4a7a9a53641515dd71c9dab53ac9b659"
# curl -vH "Content-Type: application/json" -d '{"name":"request","channel":"b8_27_eb_a0_a8_71","data":"{\"command\":\"hostname\"}"}' "https://api-us2.pusher.com/apps/367382/events?auth_key=8142387dbc68b5841187&auth_timestamp=1579022230&auth_version=1.0&body_md5=774aa2ad36d6044d4661b78e95187390&auth_signature=c2560809d6cab2f48c8822159d0abf5f4a7a9a53641515dd71c9dab53ac9b659"

# 400 Request body is malformed (invalid JSON).
# 400 Bad Request
# I have to admit, this is my favorite status code 😂. Every time I get slammed with 400 Bad Request red error on my console, I first look up and ask “What kind of life did I choose?” before I proceed to investigate it.
# Bad requests occur when the client sends a request with either incomplete data, badly constructed data or invalid data. Many times, it could be the fault of the developer who did not specify properly what kind of data they expect. Be that as it may, it happens because the data you sent to a request is incorrect.