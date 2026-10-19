#!/bin/bash
#
#   Script for detailed monitoring of Redis like database (redis, keydb, valkey)
#   Author: Filip LANGER
#   Contact: filip.langer@group.one

#   CHANGELOG:
#       19.10.2026 - First version

#   variables
tmp_file="/tmp/check_redis_${1}.tmp";  #  $1 used for specified check
pid=$(pidof redis-server valkey-server keydb-server);
TRIGGER_WARNING=90;
TRIGGER_CRITICAL=95;
if [[ "$(netstat -tlnp | grep "redis" | wc -l)" -gt 0 ]];
then
    SOFTWARE="Redis";
    SERVICE="redis-server";
    COMMAND="redis-cli";
    VERSION="$(${SERVICE} --version | awk '{print $2}' | egrep -o "[0-9\.]*")";
elif [[ "$(netstat -tlnp | grep "valkey" | wc -l)" -gt 0 ]];
then
    SOFTWARE="Valkey";
    SERVICE="valkey-server";
    COMMAND="valkey-cli";
    VERSION="$(${SERVICE} --version | awk '{print $2" "$3}' | egrep -o "[0-9\.]*" | head -n 1)";
elif [[ "$(netstat -tlnp | grep "keydb" | wc -l)" -gt 0 ]];
then
    SOFTWARE="Keydb";
    SERVICE="keydb-server";
    COMMAND="keydb-cli";
    VERSION="$(${SERVICE} --version | awk '{print $3}' | egrep -o "[0-9\.]*")";
fi;

if [[ -z "${SOFTWARE}" ]];
then
    error "No redis-like software found!";
fi;

output="${SOFTWARE} v.${VERSION} ${1}";

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
        "cpu_usage")
            
            local NCPU=$(nproc);
            ps -C ${SERVICE} -o %cpu= | awk -v n=$(nproc) '{s+=$1} END{printf "%.2f\n", s/n}' > ${tmp_file};
            if [[ $? -gt 0 ]];
            then
                error "Failed while check actuall cpu_usage from ${SERVICE}!";
            fi;
        ;;

        "ram_usage")

            ps -C ${SERVICE} -o %mem= | awk '{s+=$1} END{printf "%.2f\n", s}' > ${tmp_file};
            if [[ $? -gt 0 ]];
            then
                error "Failed while check actuall ram_usage from ${SERVICE}!";
            fi;

            ${COMMAND} INFO memory | tr -d '\r' | awk -F: '/^maxmemory:/{m=$2} /^used_memory:/{u=$2} /^total_system_memory:/{t=$2} END{if(m==0)m=t; printf "%.2f\n", u/m*100}' >> ${tmp_file};
            if [[ $? -gt 0 ]];
            then
                error "Failed while check actuall maxmemory usage from ${SERVICE}!";
            fi;
        ;;

        "db_entries")

            N=$(${COMMAND} CONFIG GET databases | tail -1)
            ${COMMAND} INFO keyspace | tr -d '\r' \
            | awk -F'[:=,]' -v n="$N" '/^db/{k[substr($1,3)]=$3} END{for(i=0;i<n;i++) print i, k[i]+0}' > ${tmp_file};
            if [[ $? -gt 0 ]];
            then
                error "Failed while check db_entries.";
            fi;
        ;;
    esac;
}

#   script body
case ${1} in 
    "running")
        end_code=0;
        result="";
        for service in ${SERVICE}.service; do
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

    "cpu_usage")
        info_text="${1} CPU Usage (%)"
        result="";
        end_code=0;

        read_values "${1}";

        actuall_usage=$(cat ${tmp_file} | awk -F "." '{print $1}');

        info_text="${info_text} (${actuall_usage}%)";

        result="${SERVICE}_cpu_usage=${actuall_usage};${TRIGGER_WARNING};${TRIGGER_CRITICAL};0;100";

        if [[ ${actuall_usage} -gt ${TRIGGER_WARNING} ]] && [[ ${actuall_usage} -lt ${TRIGGER_CRITICAL} ]];
        then
            end_code=1;
        elif [[ ${actuall_usage} -ge ${TRIGGER_CRITICAL} ]];
        then
            end_code=2;
        fi;

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

    "ram_usage")
        info_text="${1} RAM and MAXMEM Usage (%)"
        result="";
        end_code=0;

        read_values "${1}";

        actuall_usage=$(cat ${tmp_file} | head -n 1 | awk -F "." '{print $1}');
        actuall_maxmem_usage=$(cat ${tmp_file} | tail -n 1 | awk -F "." '{print $1}');

        info_text="${info_text} RAM (${actuall_usage}%) MAXMEM (${actuall_maxmem_usage})";

        result="${SERVICE}_ram_usage=${actuall_usage};${TRIGGER_WARNING};${TRIGGER_CRITICAL};0;100 ${SERVICE}_maxmem_usage=${actuall_maxmem_usage};${TRIGGER_WARNING};${TRIGGER_CRITICAL};0;100";

        if [[ ${actuall_usage} -gt ${TRIGGER_WARNING} ]] && [[ ${actuall_usage} -lt ${TRIGGER_CRITICAL} ]];
        then
            end_code=1;
        elif [[ ${actuall_usage} -ge ${TRIGGER_CRITICAL} ]];
        then
            end_code=2;
        fi;

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

    "db_count")
        info_text="${1} (#)"
        result="";
        end_code=0;

        read_values "${1}";

        actuall_value=$(${COMMAND} CONFIG GET databases | tail -1);
        if [[ $? -gt 0 ]];
        then
            error "Failed while reading number of DBs.";
        fi;

        info_text="${info_text} (${actuall_value})";

        result="${SERVICE}_db_counter=${actuall_value};;;;";

        output="${output} OK: ${info_text} | ${result}";
    ;; 

    "db_entries")
        info_text="${1} KEYS counter"
        result="";
        end_code=0;

        read_values "${1}";

        while IFS= read -r line; do
            db_name=$(echo ${line} | awk '{print $1}');
            db_entries=$(echo ${line} | awk '{print $2}');

            result="${result} db_nr_${db_name}_entries=${db_entries};;;;";
        done < ${tmp_file};

        output="${output} OK: ${info_text} | ${result}";        
    ;;
esac;

echo ${output};

exit;
