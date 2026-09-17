#!/bin/bash
#
#   Script for detailed monitoring of Keeplived service
#   Author: Filip LANGER
#   Contact: filip.langer@group.one

#   CHANGELOG:
#       17.09.2026 - Added more string for checking errors
#       16.09.2026 - First version

#   variables
tmp_file="/tmp/check_keepalived_detailed_${1}.tmp";     #  $1 used for specified check
keepalived_version=$(keepalived --version 2>&1 | head -1 | grep -oP 'v\K[0-9.]+' | head -n 1);
keepalived_original_state=$(cat /etc/keepalived/keepalived.conf | grep -i "state" | awk '{print $2}');
keepalived_vip_address=$(cat /etc/keepalived/keepalived.conf | grep -A 2 "virtual_ipaddress {" | grep "dev" | head -n 1 | awk '{print $1}');
journalctl_last_minutes="10";
output="Keepalived v.${keepalived_version} ${1}";


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
        "errors")
            journalctl -u keepalived --since "${journalctl_last_minutes} min ago" --no-pager | egrep -i "error|cant|not permitted" | awk -F ":" '{print $5}' > ${tmp_file};
            if [[ $? -gt 0 ]];
            then
                error "Error while checking journalctl for errors!";
            fi;
        ;;
    esac;
}


#   script body
case ${1} in 
    "running")
        end_code=0;
        result="";
        for service in keepalived.service; do
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

    "configtest")
        info_text="${1}";
        result="";        
        end_code=0;

        test_output=$(keepalived -t -f /etc/keepalived/keepalived.conf 2>&1);
        RC=$?;
        result="keepalived_config_errors=0;1;1;0;1";

        if [[ $RC -ne 0 ]];
        then
            end_code=2;
            info_text="${info_text} Errors on Keepalived's config found!";
            info_text="${info_text} ${test_output}";
            result="keepalived_config_errors=1;1;1;0;1";
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

    "state")
        info_text="${1}";
        result="";
        end_code=0;    

        if [[ "${keepalived_original_state}" == "MASTER" ]];
        then
            #   master server
            if [[ "$(ip a | grep "${keepalived_vip_address}" | wc -l)" -eq 0 ]];
            then
                end_code=2;
                info_text="${info_text} MASTER server in BACKUP state found!";
                result="keepalived_master_state=0;0;0;0;1";
            else
                info_text="${info_text} MASTER server is OK.";
                result="keepalived_master_state=1;0;0;0;1";
            fi;
        else
            #   backup server
            if [[ "$(ip a | grep "${keepalived_vip_address}" | wc -l)" -gt 0 ]];
            then
                end_code=1;
                info_text="${info_text} BACKUP server in MASTER state found!";
                result="keepalived_master_state=0;1;1;0;1";
            else
                info_text="${info_text} BACKUP server is OK.";
                result="keepalived_master_state=0;1;1;0;1";
            fi;            
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

    "errors")
        info_text="${1} Count of errors in last 10 minutes";
        result="";
        end_code=0;

        read_values "${1}";

        counter=$(cat ${tmp_file} | wc -l);

        errors=$(cat ${tmp_file});
        info_text="${info_text} (${counter} errors found)";
        info_text="${info_text} ${errors}";

        result="keepalived_errors=${counter};1;2;0;";

        if [[ ${counter} -gt 0 ]] && [[ ${counter} -lt 2 ]];
        then
            end_code=1;
        elif [[ ${counter} -ge 2 ]];
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
