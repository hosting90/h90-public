#!/bin/bash
#
#   Script for detailed monitoring of Clickhouse database
#   Author: Filip LANGER
#   Contact: filip.langer@group.one

#   CHANGELOG:
#       15.10.2026 - First version

#   variables
tmp_file="/tmp/check_clickhouse_${1}.tmp";  #  $1 used for specified check
clickhouse_user="nagios";
clickhouse_password="${2}";
version=$(clickhouse-server --version | egrep -o "[0-9\.]*" | head -n 1);
output="Clickhouse v.${version} ${1}";

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
        "databases_usage")
            clickhouse-client --user ${clickhouse_user} --password "${clickhouse_password}" -q "
SELECT database, round(sum(bytes_on_disk)/1024/1024/1024, 2)
FROM system.parts
WHERE active
GROUP BY database
ORDER BY 2 DESC
" > ${tmp_file};
            if [[ $? -gt 0 ]];
            then
                error "Error while checking system database space usage!";
            fi;

        ;;

        "system_database_usage")
            clickhouse-client --user ${clickhouse_user} --password "${clickhouse_password}" -q "
SELECT table, round(sum(bytes_on_disk)/1024/1024/1024, 2)
FROM system.parts
WHERE active AND database = 'system'
GROUP BY table
ORDER BY 2 DESC
" > ${tmp_file};
            if [[ $? -gt 0 ]];
            then
                error "Error while checking databases space usage!";
            fi;

        ;;        
    esac;
}

#   script body
case ${1} in 
    "running")
        end_code=0;
        result="";
        for service in clickhouse-server.service; do
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

    "databases_usage")
        info_text="${1} DB Usage (GB)"
        result="";
        end_code=0;

        read_values "${1}";
        
        while IFS= read -r line; do
            db_name=$(echo ${line} | awk '{print $1}');
            db_disk_usage=$(echo ${line} | awk '{print $2}');

            result="${result} ${db_name}_disk_usage_gb=${db_disk_usage};;;;";
        done < ${tmp_file};

        #   return info
        case "${end_code}" in
            "0")
                output="${output} OK: ${info_text} | ${result}";
            ;;
            "1")
                warning "${output} WARNING: ${info_text} | ${result}";
            ;;
            *)
                error "${output} CRITICAL: ${info_text} | ${result}";
            ;;
        esac;  
    ;;

    "system_database_usage")
        info_text="${1} System DB / Table Usage (GB)"
        result="";
        end_code=0;

        read_values "${1}";
        
        while IFS= read -r line; do
            table_name=$(echo ${line} | awk '{print $1}');
            table_disk_usage=$(echo ${line} | awk '{print $2}');

            result="${result} system_${table_name}_disk_usage_gb=${table_disk_usage};;;;";
        done < ${tmp_file};

        #   return info
        case "${end_code}" in
            "0")
                output="${output} OK: ${info_text} | ${result}";
            ;;
            "1")
                warning "${output} WARNING: ${info_text} | ${result}";
            ;;
            *)
                error "${output} CRITICAL: ${info_text} | ${result}";
            ;;
        esac;      
    ;;
esac;

echo ${output};

exit;
