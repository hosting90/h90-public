#!/bin/bash
#
#   Script for detailed monitoring of Qdrant database
#   Author: Filip LANGER
#   Contact: filip.langer@group.one

#   CHANGELOG:
#       20.10.2026 - First version

#   variables
tmp_file="/tmp/check_qdrant_${1}.tmp";  #  $1 used for specified check
TRIGGER_WARNING=75;
TRIGGER_CRITICAL=90;
SERVICE="qdrant";
METRICS_HOST="http://localhost";
METRICS_PORT="6333";
CURL_PARAMS=" -s";
VERSION=$(curl${CURL_PARAMS} ${METRICS_HOST}:${METRICS_PORT} | jq .'version' | awk -F "\"" '{print $2}');

output="Qdrant v.${VERSION} ${1}";

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
        #   check if qdrant isn't in a docker itself
        if [[ "$(docker ps | grep "qdrant/qdrant" | grep -i "up" | wc -l)" -gt 0  ]];
        then
            return 0;
        else
            return 1;
        fi;
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
            PID=$(pgrep -d, -f './qdrant');
            ps -p "${PID}" -o %cpu= | awk -v n=$(nproc) '{s+=$1} END{printf "%.2f\n", s/n}' > ${tmp_file};
            if [[ $? -gt 0 ]];
            then
                error "Failed while check actuall cpu_usage from ${SERVICE}!";
            fi;
        ;;

        "ram_usage")

            PID=$(pgrep -d, -f './qdrant');
            ps -p "${PID}" -o %mem= | awk '{s+=$1} END{printf "%.2f\n", s}' > ${tmp_file};
            if [[ $? -gt 0 ]];
            then
                error "Failed while check actuall ram_usage from ${SERVICE}!";
            fi;
        ;;

        "recovery_mode")

            curl${CURL_PARAMS} ${METRICS_HOST}:${METRICS_PORT}/metrics | grep "app_status_recovery_mode" | grep -v "#" | awk '{print $2}' > ${tmp_file};
            if [[ $? -gt 0 ]];
            then
                error "Failed while check for recovery mode is on/off.";
            fi;
        ;;

        "fds")
            
            curl${CURL_PARAMS} ${METRICS_HOST}:${METRICS_PORT}/metrics | egrep "process_open_fds|process_max_fds" | grep -v "#" > ${tmp_file};
            if [[ $? -gt 0 ]];
            then
                error "Failed while check for FDS.";
            fi;        
        ;;

        "collections")

            curl${CURL_PARAMS} ${METRICS_HOST}:${METRICS_PORT}/metrics | egrep "collections_total|collections_vector_total" | grep -v "#" > ${tmp_file};
            if [[ $? -gt 0 ]];
            then
                error "Failed while check for collections.";
            fi;
        ;;

        "vectors")
            curl${CURL_PARAMS} ${METRICS_HOST}:${METRICS_PORT}/metrics | grep "vectors" | grep "collection" | grep -v "#" | sed -n 's/^collection_vectors{collection="\([^"]*\)".*} \(.*\)$/\1 \2/p' > ${tmp_file};
            if [[ $? -gt 0 ]];
            then
                error "Failed while check for vectors details.";
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
        info_text="${1} RAM (%)"
        result="";
        end_code=0;

        read_values "${1}";

        actuall_usage=$(cat ${tmp_file} | head -n 1 | awk -F "." '{print $1}');
        info_text="${info_text} RAM (${actuall_usage}%)";

        result="${SERVICE}_ram_usage=${actuall_usage};${TRIGGER_WARNING};${TRIGGER_CRITICAL};0;100";

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

    "recovery_mode")
        info_text="${1}"
        result="";
        end_code=0;

        read_values "${1}";

        actuall_value=$(cat ${tmp_file});

        result="${SERVICE}_recovery_mode=${actuall_value};1;1;0;1";

        if [[ ${actuall_usage} -gt 0 ]];
        then
            info_text="${info_text} Qdrant running in a Recovery mode!";
            end_code=2;
        else
            info_text="${info_text} Qdrant running in a Normal mode.";
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

    "fds")
        info_text="${1} Files descriptors"
        result="";
        end_code=0;

        read_values "${1}";

        actuall_value=$(cat ${tmp_file} | grep "process_open_fds" | awk '{print $2}' | egrep -o "[0-9]*");
        max_value=$(cat ${tmp_file} | grep "process_max_fds" | awk '{print $2}' | egrep -o "[0-9]*");

        warning_value=$(( max_value * TRIGGER_WARNING / 100 ));
        critical_value=$(( max_value * TRIGGER_CRITICAL / 100 ));
        percentual_value=$(( actuall_value * 100 / max_value ));

        result="${SERVICE}_fds_usage=${percentual_value};${TRIGGER_WARNING};${TRIGGER_CRITICAL};0;100 ${SERVICE}_actuall_fds=${actuall_value};${warning_value};${critical_value};0;${max_value}";

        if [[ ${percentual_value} -gt ${TRIGGER_WARNING} ]] && [[ ${percentual_value} -lt ${TRIGGER_CRITICAL} ]];
        then
            end_code=1;
        elif [[ ${percentual_value} -ge ${TRIGGER_CRITICAL} ]];
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

    "collections")
        info_text="${1} Collections / Collections_vectors_total"
        result="";
        end_code=0;

        read_values "${1}";

        collections=$(cat ${tmp_file} | grep "collections_total" | awk '{print $2}' | egrep -o "[0-9]*");
        collections_vectors=$(cat ${tmp_file} | grep "collections_vector_total" | awk '{print $2}' | egrep -o "[0-9]*");

        info_text="${info_text} (${collections} / ${collections_vectors})";
        result="${SERVICE}_collections=${collections};;;0; ${SERVICE}_collections_vectors=${collections_vectors};;;0;";

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

    "vectors")
        info_text="${1} Vectors detail"
        result="";
        end_code=0;

        read_values "${1}";

        while read -r name value; do
            result="${result} ${name}_vectors=${value};;;0;";
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
