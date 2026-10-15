#!/bin/bash
#
#   Script for easy check if service run on server
#   Author: Filip LANGER
#   Contact: filip.langer@group.one

#   CHANGELOG:
#       15.10.2026 - First version

#   variables
SERVICE="${1}";
tmp_file="/tmp/check_service_${SERVICE}.tmp";  #  $1 used for specified check
output="Service check ${SERVICE}";

#   functions
function error() {
    #   inputs values
    #   $1  string  message

    echo "${1}";
    exit 2;
}

function warning() {
    #   inputs values
    #   $1  string  message
    echo "${1}";
    exit 1;
}

function check_running() {
    #   inputs values
    #   $1  string  service

    systemctl is-active ${SERVICE}.service >/dev/null 2>&1;
    if [[ $? -gt 0 ]];
    then
        #   check if service is inactive and waiting for timer (logrotate)
        trigger=$(systemctl show -p TriggeredBy --value ${SERVICE}.service);
        if [[ ! -z "${trigger}" ]];
        then
            if systemctl is-active ${trigger} >/dev/null 2>&1;
            then
                return 0;
            fi;
        fi;
        return 1;
    else
        return 0;
    fi;
}

#   script body
end_code=0;
result="";
if check_running "${SERVICE}";
then
    result="${result} ${SERVICE}=1;0;0;0;1";
else
    end_code=1;
    result="${result} ${SERVICE}=0;0;0;0;1";
fi;

if [[ $end_code -eq 0 ]];
then
    output="${output} OK | ${result}";
else
    warning "${output} PROBLEM | ${result}"
fi;

echo ${output};

exit;
