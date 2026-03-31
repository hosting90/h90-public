#!/bin/bash
#
#   Skript for detailed monitoring of PHP FPM
#   Author: Filip LANGER
#   Contact: filip.langer@group.one

#   CHANGELOG:
#       30.03.2026 - First version

#   variables
tmp_file="/tmp/check_php_fpm_detailed_${1}.tmp";  #  $1 used for specified check
output="PHP FPM ${1}";

#   functions
function error() {
    #   inputs values
    #   $1  string  message

    output="${output} ERROR: ${1}";
    exit 1;
}

function check_running() {
    #   inputs values
    #   $1  PHP FPM Version (etc. 8.3)

    systemctl is-active php${1}-fpm >/dev/null 2>&1;
    if [[ $? -gt 0 ]];
    then
        return 1;
    else
        return 0;
    fi;
}

function read_values() {
    #   inputs values
    #   $1  string  type (etc. pool_process)
    #   $2  string  PHP FPM Version (etc. 8.3)
    #   $3  string  PHP FPM pool name (etc. www.conf)

    local type="${1}";
    local version="${2}";
    local pool_name="${3}";

    local script_name=$(cat /etc/php/${version}/fpm/pool.d/${pool_name} | sed "/^;/d" | grep "pm.status_path" | awk '{print $3}');
    local socket=$(cat /etc/php/${version}/fpm/pool.d/${pool_name} | sed "/^;/d" | grep "listen" | grep sock | awk '{print $3}');

    if [[ ! -z "${script_name}" ]] && [[ ! -z "${socket}" ]];
    then
        SCRIPT_NAME=${script_name} SCRIPT_FILENAME=${script_name} REQUEST_METHOD=GET QUERY_STRING="" cgi-fcgi -bind -connect ${socket} > ${tmp_file}_${pool_name};
        if [[ $? -gt 0 ]];
        then
            error "Can't readh pool [${pool_name}] stats!";
            exit 1;
        fi;
    fi;
}

#   script body
case ${1} in 
    "running")
        end_code=0;
        result="";
        for version in $(ls /etc/php/); do
            if check_running "${version}";
            then
                result="${result} php_fpm_${version}=1;0;0;0;1";
            else
                end_code=1;
                result="${result} php_fpm_${version}=0;0;0;0;1";
            fi;
        done;

        if [[ $end_code -eq 0 ]];
        then
            output="${output} OK | ${result}";
        else
            output="${output} PROBLEM | ${result}";
        fi;
    ;;

    "pool_process")
        info_text="info (idle/total)";
        result="";
        end_code=0;

        for version in $(ps aux | grep php | grep master | awk '{print $14}' | egrep -o "[0-9]\.[0-9]*"); do
            for pool in $(ls /etc/php/${version}/fpm/pool.d/); do
                read_values "${1}" "${version}" "${pool}";

                pool_file="${tmp_file}_${pool}";

                if [[ -f "${pool_file}" ]];
                then
                    pool_name=$(cat ${pool_file} | grep "pool:" | awk '{print $2}');
                    idle_processes=$(cat ${pool_file} | grep "idle processes:" | awk '{print $3}');
                    total_processes=$(cat ${pool_file} | grep "total processes:" | awk '{print $3}');

                    info_text="${info_text} ${pool_name}_${version} (${idle_processes}/${total_processes})";
                    result="${result} ${pool_name}_${version}_pool_free=${idle_processes};5;2;0;${total_processes}";

                    if [[ ${idle_processes} -eq 0 ]];
                    then
                        end_code=1;
                    fi;
                fi;
            done;
        done;

        #   return info
        if [[ ${end_code} -eq 0 ]];
        then
            output="${output} OK: ${info_text} | ${result}";
        else
            output="${output} NOT ENOUGH POOLS: ${info_text} | ${result}";        
        fi;
    ;;

    "pool_memory")
        output="${output} MEMORY INFO (MB) |";

        for version in $(ps aux | grep php | grep master | awk '{print $14}' | egrep -o "[0-9]\.[0-9]*"); do
            for pool in $(ls /etc/php/${version}/fpm/pool.d/); do
                read_values "${1}" "${version}" "${pool}";

                pool_file="${tmp_file}_${pool}";

                if [[ -f "${pool_file}" ]];
                then
                    pool_name=$(cat ${pool_file} | grep "pool:" | awk '{print $2}');
                    memory_peak=$(cat ${pool_file} | grep "memory peak:" | awk '{print $3}');
                    memory_peak_mb=$(( memory_peak / 1000000 ));

                    output="${output} ${pool_name}_${version}_memory_usage=${memory_peak_mb};;;;";
                fi;
            done;
        done;
    ;;

    "max_memory")
        mem_used=0;
        mem_total_gb=$(free -g | grep "Mem:" | awk '{print $2}');

        for version in $(ps aux | grep php | grep master | awk '{print $14}' | egrep -o "[0-9]\.[0-9]*"); do
            for pool in $(ls /etc/php/${version}/fpm/pool.d/); do
                read_values "${1}" "${version}" "${pool}";

                pool_file="${tmp_file}_${pool}";

                if [[ -f "${pool_file}" ]];
                then
                    memory_peak=$(cat ${pool_file} | grep "memory peak:" | awk '{print $3}');

                    mem_used=$(( mem_used + memory_peak ));
                fi;
            done;
        done;

        #   convert values
        mem_used_gb=$(( mem_used / 1000000000 ));

        output="${output} PHP FPM total RAM use (${mem_used_gb}/${mem_total_gb}GB) | total_fpm_mem_used=${mem_used_gb};$((mem_total_gb*80/100));$((mem_total_gb*90/100));0;${mem_total_gb} system_total_mem=${mem_total_gb};;;;";
    ;;
esac;

echo ${output};

exit;
