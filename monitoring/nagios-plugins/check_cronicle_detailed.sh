#!/bin/bash
#
#   Skript for detailed monitoring of Cronicle (cron jobs)
#   Author: Filip LANGER
#   Contact: filip.langer@group.one

#   CHANGELOG:
#       28.08.2026 - First version

#   variables
tmp_file="/tmp/check_cronicle_${1}.tmp";  #  $1 used for specified check
output="Cronicle ${1}";
CRONICLE_URL="http://localhost:3012";
CRONICLE_API_KEY="${2}";
TODAY_START=$(date -d "today 00:00:00" +%s);

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

    systemctl is-active ${1} >/dev/null 2>&1;
    if [[ $? -gt 0 ]];
    then
        return 1;
    else
        return 0;
    fi;
}

function read_values() {
    #   inputs values
    #   $1  string  command (check|list-backups...)

    local cmd="${1}";

    case "${cmd}" in
        "activity")

            local response=$(curl -s "${CRONICLE_URL}/api/app/get_history/v1?offset=0&limit=5000&api_key=${CRONICLE_API_KEY}");
            if [[ $? -gt 0 ]];
            then
                error "Error while checking actuall activity from cronicle!";
            fi;

            local result=$(echo "$response" | jq --argjson start "$TODAY_START" '[.rows[] | select(.epoch >= $start)] as $today | "\($today | length)/\($today | map(select(.code==0)) | length)/\($today | map(select(.code!=0)) | length)"');
            if [[ $? -gt 0 ]];
            then
                error "Error while preparing output from cronicle's activity!";
            fi;

            echo "${result}" > ${tmp_file};
        ;;
    esac;
}

#   script body
case ${1} in 
    "running")
        end_code=0;
        result="";
        for service in cronicle.service; do
            if check_running "${service}";
            then
                result="${result} ${service}=1;0;0;0;1";
            else
                end_code=1;
                result="${result} ${service}=0;0;0;0;1";
            fi;
        done;

        if [[ $end_code -eq 0 ]];
        then
            output="${output} OK | ${result}";
        else
            warning "${output} PROBLEM | ${result}"
        fi;
    ;;

    "activity")
        info_text="${1} Today CronJobs (all/ok/failed)";
        result="";
        end_code=0;

        read_values "${1}";
        
        counter=$(cat ${tmp_file});
        counter_all=$(echo "${counter}" | awk -F "/" '{print $1}' | egrep -o "[0-9]*");
        counter_ok=$(echo "${counter}" | awk -F "/" '{print $2}' | egrep -o "[0-9]*");
        counter_failed=$(echo "${counter}" | awk -F "/" '{print $3}' | egrep -o "[0-9]*");
        
        info_text="${info_text} (${counter})";

        if [[ "${counter_failed}" -gt 0 ]];
        then
            end_code=1;
        fi;

        result="${result} counter_all_jobs=${counter_all};;;; counter_ok_jobs=${counter_ok};;;; counter_failed_jobs=${counter_failed};;;;";

        #   return info
        if [[ ${end_code} -eq 0 ]];
        then
            output="${output} OK: ${info_text} | ${result}";
        else
            error "${output} PROBLEM: ${info_text} | ${result}";        
        fi;
    ;;
esac;

echo ${output};

exit;
