#!/bin/bash
#
#   Script for detailed monitoring of PostgreSQL database
#   Author: Filip LANGER
#   Contact: filip.langer@group.one

#   CHANGELOG:
#       08.07.2026 - First version

#   variables
tmp_file="/tmp/check_barman_detailed_${1}.tmp";  #  $1 used for specified check
postgresql_version="$(psql -V | awk '{print $3}')";
postgresql_major_version=$(echo "${postgresql_version}" | awk -F "." '{print $1}');
output="PostgreSQL v.${postgresql_version} ${1}";

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
        "databases_space")
            su - postgres -c "psql -At -F $'\t' -c \"SELECT datname, round(pg_database_size(datname)/1024.0/1024/1024,2) FROM pg_database ORDER BY pg_database_size(datname) DESC;\"" > ${tmp_file};
            if [[ $? -gt 0 ]];
            then
                error "Error while calculating databases-spaces!";
            fi;
        ;;

        "long_running_transaction")
            su - postgres -c "psql -Atqc \"SELECT COALESCE(max(EXTRACT(EPOCH FROM (now()-xact_start))),0) FROM pg_stat_activity WHERE xact_start IS NOT NULL;\"" > ${tmp_file};
            if [[ $? -gt 0 ]];
            then
                error "Error while checking long running transactions!";
            fi;            
        ;;

        "idle_transaction")
            su - postgres -c "psql -Atqc \"SELECT count(*) FROM pg_stat_activity WHERE state='idle in transaction';\"" > ${tmp_file};
            if [[ $? -gt 0 ]];
            then
                error "Error while checking idle transactions!";
            fi;                        
        ;;

        "blocked_queries")
            su - postgres -c "psql -Atqc \"SELECT count(*) FROM pg_stat_activity WHERE wait_event_type='Lock';\"" > ${tmp_file};
            if [[ $? -gt 0 ]];
            then
                error "Error while checking blocked queries!";
            fi;                                    
        ;;
        "connections_usage")
            su - postgres -c "psql -Atqc \"SELECT count(*), current_setting('max_connections') FROM pg_stat_activity;\"" > ${tmp_file};
            if [[ $? -gt 0 ]];
            then
                error "Error while checking connections usage!";
            fi;
        ;;
        "autovacuum")
            su - postgres -c "psql -Atqc \"SELECT count(*) FROM pg_stat_user_tables WHERE last_autovacuum IS NULL OR last_autovacuum < now()-interval '1 day';\"" > ${tmp_file};
            if [[ $? -gt 0 ]];
            then
                error "Error while checking vacuum usage!";
            fi;            
        ;;
    esac;
}

#   script body
case ${1} in 
    "running")
        end_code=0;
        result="";
        for service in postgresql.service postgresql@${postgresql_major_version}-main.service; do
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
            error "${output} PROBLEM | ${result}";
        fi;
    ;;

    "connection")
        end_code=0;
        result="";
        su - postgres -c "psql -c \"SELECT 1;\"" > /dev/null 2>&1;
        if [[ $? -gt 0 ]];
        then
            end_code=1;
            result="connection_problem=1;1;1;0;1";
        else
            result="connection_problem=0;1;1;0;1";
        fi;

        if [[ $end_code -eq 0 ]];
        then
            output="${output} OK | ${result}";
        else
            error "${output} PROBLEM | ${result}";
        fi;        
    ;;

    "databases_space")
        info_text="${1}";
        result="";
        end_code=0;

        read_values "${1}";

        while IFS=$'\t' read -r db size; do
            info_text="${info_text} [${db} - ${size}GiB]";
            result="${result} ${db}_gb=${size};0;0;0;";
        done < ${tmp_file};

        #   return info
        if [[ ${end_code} -eq 0 ]];
        then
            output="${output} OK: ${info_text} | ${result}";
        else
            error "${output} PROBLEM: ${info_text} | ${result}";        
        fi;
    ;;

    "long_running_transaction")
        info_text="${1} Long Running transaction [s]";
        result="";
        end_code=0;

        read_values "${1}";

        seconds=$(cat ${tmp_file} | awk -F "." '{print $1}');

        info_text="${info_text} ${seconds}s";

        if [[ ${seconds} -gt 1800 ]];
        then
            end_code=1;
        fi;

        result="long_running_transaction=${seconds};1800;3600;0;";

        #   return info
        if [[ ${end_code} -eq 0 ]];
        then
            output="${output} OK: ${info_text} | ${result}";
        else
            warning "${output} PROBLEM: ${info_text} | ${result}";        
        fi;
    ;;

    "idle_transaction")
        info_text="${1} Idle transaction [count]";
        result="";
        end_code=0;

        read_values "${1}";

        counter=$(cat ${tmp_file});

        info_text="${info_text} ${counter} transactions";

        if [[ ${counter} -gt 0 ]];
        then
            end_code=1;
        fi;

        result="idle_transaction_counter=${counter};1;1;0;";

        #   return info
        if [[ ${end_code} -eq 0 ]];
        then
            output="${output} OK: ${info_text} | ${result}";
        else
            warning "${output} PROBLEM: ${info_text} | ${result}";        
        fi;        
    ;;

    "blocked_queries")
        info_text="${1} Blocked queries [count]";
        result="";
        end_code=0;

        read_values "${1}";

        counter=$(cat ${tmp_file});

        info_text="${info_text} ${counter} blocked queries";

        if [[ ${counter} -gt 0 ]];
        then
            end_code=1;
        fi;

        result="blocked_queries_counter=${counter};1;1;0;";

        #   return info
        if [[ ${end_code} -eq 0 ]];
        then
            output="${output} OK: ${info_text} | ${result}";
        else
            warning "${output} PROBLEM: ${info_text} | ${result}";        
        fi;        
    ;;    

    "connections_usage")
        info_text="${1} Connections usage (actuall/max)";
        result="";
        end_code=0;

        read_values "${1}";

        actuall_value=$(cat ${tmp_file} | awk -F "|" '{print $1}');
        max_value=$(cat ${tmp_file} | awk -F "|" '{print $2}');

        if [[ ${actuall} -gt ${max_value} ]];
        then
            end_code=1;
        fi;

        info_text="${info_text} (${actuall_value}/${max_value})";

        result="postgresql_connections=${actuall_value};$(( max_value / 100 * 80 ));$(( max_value / 100 * 90 ));0;${max_value}";

        #   return info
        if [[ ${end_code} -eq 0 ]];
        then
            output="${output} OK: ${info_text} | ${result}";
        else
            error "${output} PROBLEM: ${info_text} | ${result}";        
        fi;        
    ;;

    "autovacuum")
        info_text="${1} Tabled need to be vacuued [count]";
        result="";
        end_code=0;

        read_values "${1}";

        counter=$(cat ${tmp_file});

        if [[ ${counter} -gt 0 ]];
        then
            end_code=1;
        fi;

        info_text="${counter} tables";

        result="tables_need_autovacuum=${counter};1;1;0;";

        #   return info
        if [[ ${end_code} -eq 0 ]];
        then
            output="${output} OK: ${info_text} | ${result}";
        else
            warning "${output} PROBLEM: ${info_text} | ${result}";        
        fi;   
    ;;
esac;

echo ${output};

exit;
