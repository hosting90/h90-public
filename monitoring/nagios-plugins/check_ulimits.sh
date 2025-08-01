#!/bin/bash
#
#   Skript for a gitlab check
#   Author: Filip LANGER
#   Contact: filip.langer@group.one

#   variables
PROCESS="$1";

#   functions
function check_input() {
    if [[ -z "${PROCESS}" ]];
    then
        echo -e "Missing params!\nUsage: ${0} <process>";
        exit 1;
    fi;
}

function check_process_limit() {
    # check if there's least one process
    if [ "$(pgrep -f "${PROCESS}" | wc -l)" -eq 0 ];
    then
        echo -e "None process [${PROCESS}] found on system.";
        exit 2;
    fi;

    for pid in $(ps aux | grep "${PROCESS}" | awk '{print $2}'); do
        if [[ ! -f "/proc/${pid}/limits" || ! -d "/proc/${pid}/fd" ]];
        then
            continue;
        fi;
      
        local actuall_limit=$(cat /proc/${pid}/limits | grep -i "max open files" | awk '{print $4}');
        local actuall_value=$(ls /proc/${pid}/fd | wc -l);

        if [[ ${actuall_value} -ge ${actuall_limit} ]];
        then
            echo -e "Process [${PROCESS}] / PID [${pid}] reach the ulimit (actuall_value/actuall_limit) [${actuall_value}]/[${actuall_limit}] - process task [$(ps -p ${pid} -o cmd=)]";
            exit 3;
        fi;
    done;
}

#   script body
check_input;
check_process_limit;

exit;
