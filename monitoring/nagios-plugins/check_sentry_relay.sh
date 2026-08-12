#!/bin/bash
#
#   Script for monitoring sentry-relay
#   Author: Filip LANGER
#   Contact: filip.langer@group.one

#   CHANGELOG:
#       26.06.2026 - First version

#   variables
output="SENTRY RELAY ${1}";
check_last_minutes=5;   #   value for checking last X minutes of logs for errors

#   functions
function error() {
    #   inputs values
    #   $1  string  message

    output="${output} ERROR: ${1}";
    exit 1;
}

function check_running() {
    #   no input variables

    systemctl is-active sentry-relay >/dev/null 2>&1;
    if [[ $? -gt 0 ]];
    then
        return 1;
    else
        return 0;
    fi;
}

#   script body
case ${1} in 
    "running")
        end_code=0;
        result="";
        if check_running;
        then
            result="${result} sentry_relay=1;0;0;0;1";
        else
            end_code=1;
            result="${result} sentry_relay=0;0;0;0;1";
        fi;

        if [[ $end_code -eq 0 ]];
        then
            output="${output} OK | ${result}";
        else
            output="${output} PROBLEM | ${result}";
        fi;
    ;;

    "memory")
        info_text="memory [MB] (usage/high/max)";
        result="";
        end_code=0;

        mem_cur=$(( $(systemctl show sentry-relay -p MemoryCurrent --value) / 1024 / 1024 ));
        mem_high=$(( $(systemctl show sentry-relay -p MemoryHigh --value) / 1024 / 1024 ));
        mem_max=$(( $(systemctl show sentry-relay -p MemoryMax --value) / 1024 / 1024 ));

        info_text="${info_text} (${mem_cur}/${mem_high}/${mem_max})";
        result="${result} sentry_relay_ram_usage=${mem_cur};${mem_high};$(( (mem_high + mem_max) / 2 ));0;${mem_max}";

        if [[ ${mem_cur} -ge ${mem_high} ]] && [[ ${mem_cur} -lt ${mem_max} ]];
        then
            end_code=1;
        elif [[ ${mem_cur} -ge ${mem_max} ]];
        then
            end_code=2;
        fi;

        #   return info
        if [[ ${end_code} -eq 0 ]];
        then
            output="${output} OK: ${info_text} | ${result}";
        elif [[ ${end_code} -eq 1 ]];
        then
            output="${output} WARNING - HIGH RAM USAGE: ${info_text} | ${result}";
        else
            output="${output} NOT ENOUGH RAM: ${info_text} | ${result}";        
        fi;
    ;;

    "log")
        info_text="log (warning/unknown/error)";
        result="";
        end_code=0;

        log_warning_counter=$(journalctl -u sentry-relay --since "${check_last_minutes} minutes ago" --no-pager | grep "WARN" | wc -l);
        log_unknown_counter=$(journalctl -u sentry-relay --since "${check_last_minutes} minutes ago" --no-pager | grep -v "INFO" | grep -v "WARN" | grep -v "ERROR" | wc -l);
        log_error_counter=$(journalctl -u sentry-relay --since "${check_last_minutes} minutes ago" --no-pager | grep "ERROR" | wc -l);

        info_text="${info_text} (${log_warning_counter}/${log_unknown_counter}/${log_error_counter})";
        result="${result} sentry_relay_warning_msg=${log_warning_counter};1;1;0; sentry_relay_unknown_msg=${log_unknown_counter};1;1;0; sentry_relay_error_msg=${log_error_counter};1;1;0;";

        if [[ ${log_warning_counter} -ne 0 ]] || [[ ${log_unknown_counter} -ne 0 ]] || [[ ${log_error_counter} -ne 0 ]];
        then
            end_code=1;
        fi;

        #   return info
        if [[ ${end_code} -eq 0 ]];
        then
            output="${output} OK: (0/0/0) | ${result}";
        else
            output="${output} CHCECK LOGS: ${info_text} | ${result}";
        fi;
    ;;    
esac;

echo ${output};

exit;
