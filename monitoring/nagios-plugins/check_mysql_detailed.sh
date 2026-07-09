#!/bin/bash
#
#   Script for detailed monitoring of MySQL / MariaDB database
#   Author: Filip LANGER
#   Contact: filip.langer@group.one

#   CHANGELOG:
#       09.07.2026 - First version

#   variables
tmp_file="/tmp/check_mysql_detailed_${1}.tmp";  #  $1 used for specified check
if [[ "$(mysql -V | grep -i mariadb | wc -l)" -gt 0 ]]; then db_type="MariaDB"; else db_type="MySQL"; fi;
mysql_version="$(mysql -V | awk '{print $3}')";
output="${db_type} v.${mysql_version} ${1}";
long_running_transaction_warning=1;
long_running_transaction_critical=10;
idle_transaction_warning=25;
idle_transaction_critical=50;

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
            sudo -u root mysql -N -e "SELECT table_schema, ROUND(SUM(data_length+index_length)/1024/1024/1024,2) AS size_gb FROM information_schema.tables GROUP BY table_schema;" > ${tmp_file};
            if [[ $? -gt 0 ]];
            then
                error "Error while calculating databases-spaces!";
            fi;
        ;;

        "long_running_transaction")
            sudo -u root mysql -N -e "SELECT COUNT(*) FROM information_schema.innodb_trx WHERE TIMESTAMPDIFF(SECOND, trx_started, NOW()) > 300;" > ${tmp_file};
            if [[ $? -gt 0 ]];
            then
                error "Error while checking count long running transactions!";
            fi;            
        ;;

        "idle_transaction")
            sudo -u root mysql -N -e "SELECT COUNT(*) FROM information_schema.processlist WHERE COMMAND='Sleep' AND TIME > 300;" > ${tmp_file};
            if [[ $? -gt 0 ]];
            then
                error "Error while checking idle transactions!";
            fi;                        
        ;;

        "blocked_queries")
            sudo -u root mysql -N -e "SELECT COUNT(*) FROM sys.innodb_lock_waits;" > ${tmp_file};
            if [[ $? -gt 0 ]];
            then
                error "Error while checking blocked queries!";
            fi;                                    
        ;;
        "connections_usage")
            sudo -u root mysql -N -e "SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME='Threads_connected'; SELECT @@GLOBAL.max_connections;" > ${tmp_file};
            if [[ $? -gt 0 ]];
            then
                error "Error while checking connections usage!";
            fi;
        ;;
        "binlog_size")
            local binlog_basename=$(sudo -u root mysql -N -e "SHOW VARIABLES LIKE 'log_bin_basename';" | awk '{print $2}');
            if [[ $? -gt 0 ]];
            then
                error "Error while checking binlog size!";
            fi;            

            if ls "${binlog_basename}".* >/dev/null 2>&1; 
            then
                local folder_usage_bytes=$(du -cb "${binlog_basename}".* | tail -n 1 | awk '{print $1}');
            fi;

            local folder_usage_gb=$(awk "BEGIN {printf \"%.2f\", $folder_usage_bytes/1024/1024/1024}");

            echo -e "${folder_usage_gb}" > ${tmp_file};
        ;;
        "tmp_tables")
            sudo -u root mysql -N -e "SHOW GLOBAL STATUS LIKE 'Created_tmp_disk_tables';" | awk '{print $2}' > ${tmp_file};
            if [[ $? -gt 0 ]];
            then
                error "Error while checking tmp tables!";
            fi;            
        ;;
    esac;
}

#   script body
case ${1} in 
    "running")
        end_code=0;
        result="";
        for service in mysql.service; do
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
        sudo mysql -u root -N -e "SELECT 1;" > /dev/null 2>&1;
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
        info_text="${1} Long Running transaction [count]";
        result="";
        end_code=0;

        read_values "${1}";

        counter=$(cat ${tmp_file});

        info_text="${info_text} ${counter}";

        if [[ ${counter} -gt 0 ]] && [[ ${counter} -lt ${long_running_transaction_critical} ]];
        then
            end_code=1;
        elif [[ "${counter}" -ge ${long_running_transaction_critical} ]];
        then
            end_code=2;
        fi;

        result="long_running_transaction_counter=${counter};${long_running_transaction_warning};${long_running_transaction_critical};0;";

        #   return info
        case "${end_code}" in
            "0")
                output="${output} OK: ${info_text} | ${result}";
            ;;

            "1")
                warning "${output} WARNING: ${info_text} | ${result}";
            ;;

            "*")
                error "${output} CRITICAL: ${info_text} | ${result}";
            ;;
        esac;
    ;;

    "idle_transaction")
        info_text="${1} Idle transaction [count]";
        result="";
        end_code=0;

        read_values "${1}";

        counter=$(cat ${tmp_file});

        info_text="${info_text} ${counter} transactions";

        if [[ ${counter} -gt ${idle_transaction_warning} ]] && [[ ${counter} -lt ${idle_transaction_critical} ]];
        then
            end_code=1;
        elif [[ ${counter} -ge ${idle_transaction_critical} ]];
        then
            end_code=2;
        fi;

        result="idle_transaction_counter=${counter};${idle_transaction_warning};${idle_transaction_critical};0;";

        #   return info
        case "${end_code}" in
            "0")
                output="${output} OK: ${info_text} | ${result}";
            ;;

            "1")
                warning "${output} WARNING: ${info_text} | ${result}";
            ;;

            "*")
                error "${output} CRITICAL: ${info_text} | ${result}";
            ;;
        esac;
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

        actuall_value=$(cat ${tmp_file} | head -n 1);
        max_value=$(cat ${tmp_file} | tail -n 1);

        if [[ ${actuall} -gt ${max_value} ]];
        then
            end_code=1;
        fi;

        info_text="${info_text} (${actuall_value}/${max_value})";

        result="mysql_connections=${actuall_value};$(( max_value / 100 * 80 ));$(( max_value / 100 * 90 ));0;${max_value}";

        #   return info
        if [[ ${end_code} -eq 0 ]];
        then
            output="${output} OK: ${info_text} | ${result}";
        else
            error "${output} PROBLEM: ${info_text} | ${result}";        
        fi;        
    ;;

    "binlog_size")
        info_text="${1} binlog files space usage [GiB]";
        result="";
        end_code=0;

        read_values "${1}";

        actual_size=$(cat ${tmp_file});

        info_text="${info_text} ${actual_size} GiB";        

        result="actual_binlog_size=${actual_size};;;0;";

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

    "tmp_tables")
        info_text="${1} tmp_tables created on disk counter";
        result="";
        end_code=0;

        read_values "${1}";

        counter=$(cat ${tmp_file});

        info_text="${info_text} ${counter} tables";

        result="tmp_tables_created_on_disk=${counter};;;0;";

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
