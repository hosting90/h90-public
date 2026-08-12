#!/bin/bash
#
#   Script for detailed monitoring of Docker
#   Author: Filip LANGER
#   Contact: filip.langer@group.one

#   CHANGELOG:
#       05.08.2026 - Added options to skipped containers, that client develops
#       31.07.2026 - First version

#   variables
tmp_file="/tmp/check_barman_detailed_${1}.tmp";     #  $1 used for specified check
warning_minutes_trigger=30;
critical_minutes_trigger=60;
output="Docker ${1}";
exclude="${2}";

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
        "containers")

            if [[ -z "${exclude}" ]];
            then
                docker ps -a > ${tmp_file};            
            else
                docker ps -a | egrep -v "${exclude}" > ${tmp_file};
            fi;

            if [[ $? -gt 0 ]];
            then
                error "Error while checking actuall docker state!";
            fi;
        ;;

        "stats")
            docker stats --no-stream --format "{{.Container}} {{.Name}} {{.CPUPerc}} {{.MemUsage}}" | \
awk '{
    cpu=$3;
    mem=$4;                     # e.g. "120MiB"
    val=mem; unit=mem;
    gsub(/[A-Za-z]/, "", val);   # keep only the number
    gsub(/[0-9.]/, "", unit);    # keep only the letters
    if (unit == "GiB") gb = val;
    else if (unit == "MiB") gb = val / 1024;
    else if (unit == "KiB") gb = val / 1024 / 1024;
    else gb = val / 1024 / 1024 / 1024;  # B
    printf "%-15s %-20s %-8s %.4f GB\n", $1, $2, cpu, gb;
}' > ${tmp_file}
            if [[ $? -gt 0 ]];
            then
                error "Error while checking actuall docker stats!";
            fi;            
        ;;

        "uptime")
            if [[ -f "${tmp_file}" ]]; then rm ${tmp_file}; fi;

            docker ps --format "{{.ID}} {{.Names}}" | while read -r cid name; do
                started=$(docker inspect --format '{{.State.StartedAt}}' "$cid")
                started_epoch=$(date -d "$started" +%s)
                now_epoch=$(date +%s)
                uptime_days=$(echo "scale=2; ($now_epoch - $started_epoch) / 86400" | bc -l)
                printf "%s %.2f\n" "$name" "$uptime_days" >> ${tmp_file};
            done;
        ;;

        "disk_space")
            docker ps -s --format "{{.Names}} {{.Size}}" | \
awk '{
    val=$2; unit=$2;
    gsub(/[A-Za-z()]/, "", val);
    gsub(/[0-9.]/, "", unit);
    if (unit == "GB") gb=val;
    else if (unit == "MB") gb=val/1024;
    else if (unit == "kB") gb=val/1024/1024;
    else gb=val/1024/1024/1024;
    printf "%s %.4f GB\n", $1, gb;
}' > ${tmp_file};
        ;;
    esac;
}

#   script body
case ${1} in 
    "running")
        end_code=0;
        result="";
        for service in docker.service docker.socket; do
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
            error "${output} PROBLEM | ${result}"
        fi;
    ;;

    "containers")
        info_text="${1} Containers (all/ok/problem/excluded)";
        result="";
        end_code=0;

        read_values "${1}";
        
        counter_all_from_file=$(cat ${tmp_file} | grep -v "CONTAINER ID" | wc -l);
        counter_ok=$(cat ${tmp_file} | grep -v "CONTAINEER ID" | grep "Up " | wc -l);
        counter_problem=$(cat ${tmp_file} | grep -v "CONTAINER ID" | grep -v "Up " | wc -l);
        
        if [[ -z "${exclude}" ]];
        then
            counter_excluded=0;
        else
            if [[ "$(echo ${exclude} | grep -o '|' | wc -l)" -gt 0 ]];
            then
                counter_excluded=$(echo ${exclude} | grep -o '|' | wc -l);
                ((counter_excluded++));
            else
                counter_excluded=1;
            fi;
        fi;

        counter_all=$(( counter_all_from_file + counter_excluded ));

        info_text="${info_text} (${counter_all}/${counter_ok}/${counter_problem}/${counter_excluded})";

        if [[ "${counter_problem}" -gt 0 ]];
        then
            end_code=1;
            result="problematic_container=${counter_problem};1;1;0;${counter_all}";
            info_text="${info_text} $(cat ${tmp_file} | grep -v "CONTAINER ID" | grep -v "Up " | awk '{print $1" "$2}')";
        else
            result="ok_tasks=${counter_ok};0;0;0;${counter_all}";
        fi;

        #   return info
        if [[ ${end_code} -eq 0 ]];
        then
            output="${output} OK: ${info_text} | ${result}";
        else
            error "${output} PROBLEM: ${info_text} | ${result}";        
        fi;
    ;;

    "stats")
        info_text="${1} Stats"
        result="";
        end_code=0;

        read_values "${1}";

        while IFS= read -r line; do
            container_name=$(echo ${line} | awk '{print $2}');
            container_cpu=$(echo ${line} | awk '{print $3}' | awk -F "%" '{print $1}');
            container_mem=$(echo ${line} | awk '{print $4}');

            result="${result} ${container_name}_cpu_usage_percent=${container_cpu};;;; ${container_name}_mem_usage_gb=${container_mem};;;;";
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

    "uptime")
        info_text="${1} Containers uptime";
        result="";
        end_code=0;

        read_values "${1}";

        while IFS= read -r line; do
            container_name=$(echo ${line} | awk '{print $1}');
            container_uptime=$(echo ${line} | awk '{print $2}');

            result="${result} ${container_name}_uptime_days=${container_uptime};;;;";
        done < ${tmp_file}
        
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

    "disk_space")
        info_text="${1} Disk usage";
        result="";
        end_code=0;

        read_values "${1}";

        while IFS= read -r line; do
            container_name=$(echo ${line} | awk '{print $1}');
            container_disk_usage=$(echo ${line} | awk '{print $2}');

            result="${result} ${container_name}_disk_usage_gb=${container_disk_usage};;;;";
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
