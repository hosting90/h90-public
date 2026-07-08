#!/bin/bash
#
#   Script for detailed monitoring of Barman's PostgreSQL backuping
#   Author: Filip LANGER
#   Contact: filip.langer@group.one

#   CHANGELOG:
#       08.07.2026 - Updated list-backups (now checking separately full and inc backups)
#               - New check for error logs (backuping error logs)
#               - New check for creating graphs of backup folders (disk-space)
#               - New check (last archived wal file)
#       07.07.2026 - First version

#   variables
cluster_hostname="$(hostname | sed -E 's/-[0-9]+(\.)/-01\1/')";
tmp_file="/tmp/check_barman_detailed_${1}.tmp_${cluster_hostname}";  #  $1 used for specified check
full_log="/var/log/barman/full_backup.log";
inc_log="/var/log/barman/incremental_backup.log";
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

    case "${cmd}" in
        "logs")
            tail -n 5 ${full_log} > ${tmp_file}_full;
            if [[ $? -gt 0 ]];
            then
                error "Error while read full log [${full_log}]!";
            fi;

            tail -n 5 ${inc_log} > ${tmp_file}_inc;
            if [[ $? -gt 0 ]];
            then
                error "Error while read inc log [${inc_log}]!";
            fi;
        ;;

        "space")
            local backup_folder=$(sudo -n -u barman barman show-server ${cluster_hostname} | grep "backup_directory" | awk -F ": " '{print $2}');
            sudo -n -u barman du -b --max-depth=1 "${backup_folder}/" | awk '{printf "%.2f GiB\t%s\n", $1/1024/1024/1024, $2}' > ${tmp_file};  # in GiB
        ;;

        "last_wal")
            su - postgres -c "psql -Atqc \"SELECT CASE WHEN last_failed_time IS NULL OR last_archived_time > last_failed_time THEN 'OK' ELSE 'CRITICAL' END FROM pg_stat_archiver;\"" > ${tmp_file};
        ;;

        *)
            sudo -n -u barman barman ${cmd} ${cluster_hostname} > ${tmp_file};
        ;;
    esac;
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
        info_text="${1} ${cluster_hostname} (full/inc)";
        result="";
        end_code=0;

        read_values "${1}";
        counter_full_backups=$(cat ${tmp_file} | grep "\- F \-" | wc -l);
        counter_inc_backups=$(cat ${tmp_file} | grep "\- I \-" | wc -l);

        info_text="${info_text} (${counter_full_backups}/${counter_inc_backups})";
        result="number_of_full_backups=${counter_full_backups};0;0;0; number_of_inc_backups=${counter_inc_backups};0;0;0;";

        if [[ "${counter_full_backups}" -eq 0 ]] || [[ "${counter_inc_backups}" -eq 0 ]];
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

    "logs")
        info_text="${1} ${cluster_hostname} (full_err/inc_err)";
        result="";
        end_code=0;

        read_values "${1}";
        counter_full_errors=$(cat ${tmp_file}_full | grep "ERROR" | wc -l);
        counter_inc_errors=$(cat ${tmp_file}_inc | grep "ERROR" | wc -l);

        info_text="${info_text} (${counter_full_errors}/${counter_inc_errors})";
        result="number_of_full_errors=${counter_full_errors};1;1;0; number_of_inc_errors=${counter_inc_errors};1;1;0;";

        if [[ "${counter_full_backups}" -gt 0 ]] || [[ "${counter_inc_backups}" -gt 0 ]];
        then
            end_code=1;
        fi;

        #   return info
        if [[ ${end_code} -eq 0 ]];
        then
            output="${output} OK: ${info_text} | ${result}";
        else
            output="${output} PROBLEM - BACKUPING ERRORS FOUND: ${info_text} | ${result}";        
        fi;        
    ;;

    "space")
        info_text="${1} ${cluster_hostname} [GiB] (Basebackups/WALs)";
        result="";
        end_code=0;

        read_values "${1}";
        base_gb=$(cat ${tmp_file} | grep "/base" | awk '{print $1}');
        wal_gb=$(cat ${tmp_file} | grep "/wals" | awk '{print $1}');

        info_text="${info_text} (${base_gb}/${wal_gb})";
        result="base_backups_gb=${base_gb};;;0; wal_gb=${wal_gb};;;0;";

        #   return info
        if [[ ${end_code} -eq 0 ]];
        then
            output="${output} OK: ${info_text} | ${result}";
        else
            output="${output} PROBLEM - NOT ENOUGH SPACE: ${info_text} | ${result}";        
        fi;         
    ;;

    "last_wal")
        info_text="${1} ${cluster_hostname} Last archived WAL status ";
        result="";
        end_code=0;

        read_values "${1}";

        if [[ "$(cat ${tmp_file} | grep "OK" | wc -l)" -eq 0 ]];
        then
            info_text="${info_text} Wal file failed to archive";
            end_code=1;
        else
            info_text="${info_text} Wal file archived successfully";
        fi;

        result="last_archived_wal_err=${end_code};1;1;0;1";

        #   return info
        if [[ ${end_code} -eq 0 ]];
        then
            output="${output} OK: ${info_text} | ${result}";
        else
            output="${output} PROBLEM - ${info_text} | ${result}";        
        fi;    
    ;;
esac;

echo ${output};

exit;
