#!/bin/bash
#
#   Script for detailed monitoring of Barman's PostgreSQL backuping
#   Author: Filip LANGER
#   Contact: filip.langer@group.one

#   CHANGELOG:
#       07.07.2026 - First version

#   variables
cluster_hostname="$(hostname | sed -E 's/-[0-9]+(\.)/-01\1/')";
tmp_file="/tmp/check_barman_detailed_${1}.tmp_${cluster_hostname}";  #  $1 used for specified check
output="BARMAN backup ${1}";

#   functions
function error() {
    #   inputs values
    #   $1  string  message

    output="${output} ERROR: ${1}";
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

    barman ${cmd} ${cluster_hostname} > ${tmp_file};
#    if [[ $? -gt 0 ]];
#    then
#        error "Error while running [barman ${cmd} ${cluster_hostname}]!";
#        exit 1;
#    fi;
}

#   script body
case ${1} in 
    "running")
        end_code=0;
        result="";
        for service in barman.timer; do
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
            output="${output} PROBLEM | ${result}";
        fi;
    ;;

    "check")
        info_text="${1} ${cluster_hostname} (ok/failed)";
        result="";
        end_code=0;

        read_values "${1}";
        counter_ok=$(cat ${tmp_file} | grep -i "OK" | wc -l);
        counter_failed=$(cat ${tmp_file} | grep "FAILED" | wc -l);

        info_text="${info_text} (${counter_ok}/${counter_failed})";

        if [[ "${counter_failed}" -gt 0 ]];
        then
            end_code=1;
            result="failed_tasks=${counter_failed};1;1;0;22";
            info_text="${info_text} $(cat ${tmp_file} | grep -i FAILED)";
        else
            result="ok_tasks=${counter_ok};0;0;0;22";
        fi;

        #   return info
        if [[ ${end_code} -eq 0 ]];
        then
            output="${output} OK: ${info_text} | ${result}";
        else
            output="${output} PROBLEM: ${info_text} | ${result}";        
        fi;
    ;;

    "list-backups")
        info_text="${1} ${cluster_hostname} (backups)";
        result="";
        end_code=0;

        read_values "${1}";
        counter_backups=$(cat ${tmp_file} | wc -l);

        info_text="${info_text} (${counter_backups})";
        result="number_of_backups=${counter_backups};0;0;0;";

        if [[ "${counter_backups}" -eq 0 ]];
        then
            end_code=1;
        fi;

        #   return info
        if [[ ${end_code} -eq 0 ]];
        then
            output="${output} OK: ${info_text} | ${result}";
        else
            output="${output} PROBLEM - NO BACKUPS AVAILABLE: ${info_text} | ${result}";        
        fi;    
    ;;
esac;

echo ${output};

exit;
