#!/bin/bash
#
#   Script for detailed monitoring of Metabase database
#   Author: Filip LANGER
#   Contact: filip.langer@group.one

#   CHANGELOG:
#       20.10.2026 - First version

#   variables
tmp_file="/tmp/check_metabase_${1}.tmp";  #  $1 used for specified check
TRIGGER_WARNING=90;
TRIGGER_CRITICAL=95;
SERVICE="metabase";

output="Metabase ${1}";

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
            PID=$(pgrep -d, -f 'metabase.jar');
            ps -p "${PID}" -o %cpu= | awk -v n=$(nproc) '{s+=$1} END{printf "%.2f\n", s/n}' > ${tmp_file};
            if [[ $? -gt 0 ]];
            then
                error "Failed while check actuall cpu_usage from ${SERVICE}!";
            fi;
        ;;

        "ram_usage")

            PID=$(pgrep -d, -f 'metabase.jar');
            ps -p "${PID}" -o %mem= | awk '{s+=$1} END{printf "%.2f\n", s}' > ${tmp_file};
            if [[ $? -gt 0 ]];
            then
                error "Failed while check actuall ram_usage from ${SERVICE}!";
            fi;
        ;;

        "heap_mem_usage")

            PID=$(pgrep -d, -f 'metabase.jar');
            JUSER=$(ps -o user= -p "$PID");
            MAX_KB=$(sudo -u "$JUSER" jcmd "$PID" VM.flags | tr ' ' '\n' | awk -F= '/^-XX:MaxHeapSize=/{print int($2/1024)}');
            if [ -z "$MAX_KB" ] || [ "$MAX_KB" -eq 0 ]; then
                error "Failed to read MaxHeapSize!";
            fi;


sudo -u "$JUSER" jstat -gc "$PID" | awk -v max="$MAX_KB" '
  NR==1 { for (i=1; i<=NF; i++) col[$i]=i; next }
  { used = $col["S0U"] + $col["S1U"] + $col["EU"] + $col["OU"];
    printf "%.2f\n", used*100/max }' > "${tmp_file}";
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

    "heap_mem_usage")
        info_text="${1} Heap Java Proccess RAM usage (%)"
        result="";
        end_code=0;

        read_values "${1}";

        actuall_usage=$(cat ${tmp_file} | head -n 1 | awk -F "." '{print $1}');
        info_text="${info_text} (${actuall_usage}%)";

        result="${SERVICE}_heap_ram_usage=${actuall_usage};${TRIGGER_WARNING};${TRIGGER_CRITICAL};0;100";

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
esac;

echo ${output};

exit;
