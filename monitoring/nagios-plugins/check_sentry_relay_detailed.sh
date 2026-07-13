#!/bin/bash
#
#   Script for detailed monitoring of Sentry Relay (locally used)
#   Author: Filip LANGER
#   Contact: filip.langer@group.one

#   CHANGELOG:
#       12.07.2026 - First version

#   variables
tmp_file="/tmp/check_sentry_relay_detailed_${1}.tmp";  #  $1 used for specified check
sentry_binary_path="/home/sentry/relay";
sentry_version="$(${sentry_binary_path} -V | awk '{print $2}')";
output="Sentry Relay v.${sentry_version} ${1}";
version_check_url="https://api.github.com/repos/getsentry/relay/releases/latest";
ram_usage_warning=900;      # MiB
ram_usage_critical=1500;    # MiB
cpu_usage_warning=50;       # %
cpu_usage_critical=100;     # %
check_last_minutes=5;   #   value for checking last X minutes of logs for errors


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
        "version_check")
            curl -s "${version_check_url}" | grep "tag_name" | awk -F "\"" '{print $4}' > ${tmp_file};
            if [[ $? -gt 0 ]];
            then
                error "Error while checking for last version!";
            fi;
        ;;

        "healthcheck")
            curl -s http://127.0.0.1:3000/api/relay/healthcheck/ready/ | grep "is_healthy" | awk -F ":" '{print $2}' | awk -F "}" '{print $1}'  > ${tmp_file};
            if [[ $? -gt 0 ]];
            then
                error "Error while checking for healthcheck!";
            fi;            
        ;;

        "cpu_usage")
            ps -C relay -o %cpu= | awk '{printf "%.0f", $1}' > ${tmp_file};
            if [[ $? -gt 0 ]];
            then
                error "Error while checking CPU usage!";
            fi;
        ;;

        "ram_usage")
            ps -C relay -o %mem=,rss= | awk '{printf "%.0f", $2/1024}' > ${tmp_file};
            if [[ $? -gt 0 ]];
            then
                error "Error while checking RAM usage!";
            fi;
        ;;
    esac;
}

#   script body
case ${1} in 
    "running")
        end_code=0;
        result="";
        for service in sentry-relay.service; do
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

    "version_check")
        info_text="${1}";
        result="";
        end_code=0;

        read_values "${1}";

        last_version=$(cat ${tmp_file});
        if [[ "${sentry_version}" == "${last_version}" ]];
        then
            output="${output} OK: ${info_text} - Server used last version.";
        else
            warning "${output} WARNING: ${info_text} - Sentry can be upgraded to version ${last_version}.";
        fi;     
    ;;

    "healthcheck")
        info_text="${1}";
        result="";
        end_code=0;

        read_values "${1}";

        if [[ "$(cat ${tmp_file})" == "ready" ]];
        then
            info_text="${info_text} Healthy";
            result="${result} is_sentry_healthy=1;1;1;0;1";
        else
            info_text="${info_text} Non-healthy";
            result="${result} is_sentry_healthy=0;1;1;0;1";
            enc_code=2;
        fi;

        #   return info
        if [[ ${end_code} -eq 0 ]];
        then
            output="${output} OK: ${info_text} | ${result}";
        else
            error "${output} CRITICAL: ${info_text} | ${result}";        
        fi;
    ;;

    "cpu_usage")
        info_text="${1}";
        result="";
        end_code=0;

        read_values "${1}";

        actuall_value=$(cat ${tmp_file});
        result="${result} sentry_cpu_usage=${actuall_value};${cpu_usage_warning};${cpu_usage_critical};0";

        if [[ "${actuall_value}" -ge ${cpu_usage_warning} ]] && [[ "${actuall_value}" -lt ${cpu_usage_critical} ]];
        then
            info_text="${info_text} High CPU usage";
            end_code=1;
        elif [[ "${actuall_value}" -ge ${cpu_usage_critical} ]];
        then
            info_text="${info_text} Abnormal CPU usage";
            end_code=2;
        else
            info_text="${info_text} Normal CPU usage";
        fi;

        case "${end_code}" in
            0)
                output="${output} OK: ${info_text} | ${result}";
            ;;

            1)
                warning "${output} WARNING: ${info_text} | ${result}";
            ;;

            *)
                error "${output} CRITICAL: ${info_text} | ${result}";
            ;;
        esac;
    ;;

    "ram_usage")
        info_text="${1}";
        result="";
        end_code=0;

        read_values "${1}";

        actuall_value=$(cat ${tmp_file});
        result="${result} sentry_ram_usage=${actuall_value};${ram_usage_warning};${ram_usage_critical};0";

        if [[ "${actuall_value}" -ge ${ram_usage_warning} ]] && [[ "${actuall_value}" -lt ${ram_usage_critical} ]];
        then
            info_text="${info_text} High RAM usage";
            end_code=1;
        elif [[ "${actuall_value}" -ge ${ram_usage_critical} ]];
        then
            info_text="${info_text} Abnormal RAM usage";
            end_code=2;
        else
            info_text="${info_text} Normal RAM usage";
        fi;

        case "${end_code}" in
            0)
                output="${output} OK: ${info_text} | ${result}";
            ;;

            1)
                warning "${output} WARNING: ${info_text} | ${result}";
            ;;

            *)
                error "${output} CRITICAL: ${info_text} | ${result}";
            ;;
        esac;
    ;;    

    "log")
        info_text="${1} log (warning/unknown/error)";
        result="";
        end_code=0;

        log_warning_counter=$(journalctl -u sentry-relay --since "${check_last_minutes} minutes ago" --no-pager | grep "WARN" | wc -l);
        log_unknown_counter=$(journalctl -u sentry-relay --since "${check_last_minutes} minutes ago" --no-pager | grep -v "INFO" | grep -v "WARN" | grep -v "ERROR" | wc -l);
        log_error_counter=$(journalctl -u sentry-relay --since "${check_last_minutes} minutes ago" --no-pager | grep "ERROR" | wc -l);

        info_text="${info_text} (${log_warning_counter}/${log_unknown_counter}/${log_error_counter})";
        result="${result} sentry_relay_warning_msg=${log_warning_counter};1;1;0; sentry_relay_unknown_msg=${log_unknown_counter};1;1;0; sentry_relay_error_msg=${log_error_counter};1;1;0;";

        if [[ ${log_unknown_counter} -ne 0 ]] && [[ ${log_warning_counter} -eq 0 ]] && [[ ${log_error_counter} -eq 0 ]];
        then
            end_code=1;
        elif [[ ${log_unknown_counter} -ne 0 ]] && [[ ${log_warning_counter} -ne 0 ]] || [[ ${log_error_counter} -ne 0 ]];
        then
            end_code=2;
        fi;

        case "${end_code}" in
            0)
                output="${output} OK: ${info_text} | ${result}";
            ;;

            1)
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
