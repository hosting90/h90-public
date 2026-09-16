#!/bin/bash
#
#   Script for detailed monitoring of Apache WWW server
#   Author: Filip LANGER
#   Contact: filip.langer@group.one

#   CHANGELOG:
#       16.09.2026 - First version

#   variables
tmp_file="/tmp/check_apache_detailed_${1}.tmp";     #  $1 used for specified check
apache_version=$(apachectl -v | grep "version" | awk -F "/" '{print $2}' | egrep -o "[0-9\.]*");
mpm_type=$(apachectl -V | grep MPM | awk '{print $3}');
output="Apache v.${apache_version} ${1}";

#   declare MPM values (as defaults)
case "${mpm_type}" in
    "prefork")
        declare -A MPM_VALUES=(
            [StartServers]=5
            [MinSpareServers]=5
            [MaxSpareServers]=10
            [ServerLimit]=256
            [MaxRequestWorkers]=256
            [MaxConnectionsPerChild]=0
        );
    ;;

    "worker")
        declare -A MPM_VALUES=(
            [StartServers]=3
            [MinSpareThreads]=75
            [MaxSpareThreads]=250
            [ThreadsPerChild]=25
            [ServerLimit]=16
            [MaxRequestWorkers]=400
            [MaxConnectionsPerChild]=0
        )
    ;;

    "event")
        declare -A MPM_VALUES=(
            [StartServers]=3
            [MinSpareThreads]=75
            [MaxSpareThreads]=250
            [ThreadsPerChild]=25
            [ServerLimit]=16
            [MaxRequestWorkers]=400
            [MaxConnectionsPerChild]=0
        )    
    ;;
esac;

#   declare the scoreboard
declare -A MPM_SCOREBOARD=(
    [idle]=0
    [starting]=0
    [reading]=0
    [sending]=0
    [keepalive]=0
    [dns_lookup]=0
    [closing]=0
    [logging]=0
    [graceful_stop]=0
    [idle_cleanup]=0
    [open_slot]=0
)

declare -A MPM_SCOREBOARD_CHAR_MAP=(
    [_]="idle"
    [S]="starting"
    [R]="reading"
    [W]="sending"
    [K]="keepalive"
    [D]="dns_lookup"
    [C]="closing"
    [L]="logging"
    [G]="graceful_stop"
    [I]="idle_cleanup"
    ["."]="open_slot"
);


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
        "mpm_workers")
            curl -s "http://localhost/server-status?auto" > ${tmp_file};
            if [[ $? -gt 0 ]];
            then
                error "Error while loading values from server-status!";
            fi;
        ;;

        "mpm_values")
            case "${os_family}" in
                "rhel")
                    grep -riE 'MaxRequestWorkers|ServerLimit|ThreadsPerChild|StartServers|MaxConnectionsPerChild' /etc/httpd/conf/httpd.conf /etc/httpd/conf.d/*.conf | grep -v ":#" | awk -F ":" '{print $2}' | awk '{print $1" "$2}' | sort | uniq 2>/dev/null > ${tmp_file};
                    ;;
                
                "debian")
                    grep -riE 'MaxRequestWorkers|ServerLimit|ThreadsPerChild|StartServers|MaxConnectionsPerChild' /etc/apache2/mods-available/mpm_*.conf | grep -v ":#" | awk -F ":" '{print $2}' | awk '{print $1" "$2}' | sort | uniq 2>/dev/null > ${tmp_file};
                    ;;
            esac;
        ;;

        "mpm_scoreboard")
            curl -s "http://localhost/server-status?auto" | awk -F': ' '/^Scoreboard/{print $2}' > ${tmp_file};
            if [[ $? -gt 0 ]];
            then
                error "Error while loading values from server-status's scoreboard!";
            fi;
        ;;
    esac;
}

function to_snake_case() {
    local input="$1"
    echo "$input" \
        | sed -r 's/([a-z0-9])([A-Z])/\1_\2/g; s/([A-Z]+)([A-Z][a-z])/\1_\2/g' \
        | tr '[:upper:]' '[:lower:]';    
}

#   script body
#   check os family
if [[ -f "/etc/os-release" ]];
then
    os_id=$(cat /etc/os-release | grep "^ID=" | awk -F "=" '{print $2}' | sed 's/"//g');

    case "${os_id}" in
        rhel|centos|rocky|almalinux|fedora|amzn)
            os_family="rhel";
            os_service="httpd";
            ;;
        debian|ubuntu|raspbian)
            os_family="debian";
            os_service="apache2";
            ;;
    esac;
else
    error "Can't reach the OS family!";
fi;

case ${1} in 
    "running")
        end_code=0;
        result="";
        for service in ${os_service}.service; do
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

        test_output=$(apachectl configtest 2>&1);
        RC=$?;
        result="apache_config_errors=0;1;1;0;1 apache_config_warnings=0;1;1;0;1";

        if [[ $RC -ne 0 ]];
        then
            end_code=2;
            info_text="${info_text} Errors on Apache's config found!";
            info_text="${info_text} ${output}";
            result="apache_config_errors=1;1;1;0;1 apache_config_warnings=0;1;1;0;1";
        elif echo "${test_output}" | grep -qi warning; then
            end_code=1;
            info_text="${info_text} Warning on Apache's config found!";
            info_text="${info_text} ${output}";
            result="apache_config_errors=0;1;1;0;1 apache_config_warnings=1;1;1;0;1";
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

    "vhost_count")
        info_text="${1}";
        result="";
        end_code=0;    

        counter=$(apachectl -S 2>&1 | grep -c "port .* namevhost\|is a NameVirtualHost");
        
        info_text="${info_text} ${counter}Vhosts";

        result="apache_vhosts_counter=${counter};;;;";

        output="${output} OK: ${info_text} | ${result}";
    ;;

    "mpm_workers")
        info_text="${1} MPM (${mpm_type}) workers usage (%)";
        result="";
        end_code=0;

        read_values "${1}";

        busy_workers=$(cat ${tmp_file} | awk -F': ' '/BusyWorkers/{print $2}' | head -n 1);
        idle_workers=$(cat ${tmp_file} | awk -F': ' '/IdleWorkers/{print $2}' | head -n 1);
        total_workers=$(( busy_workers + idle_workers ));
        percent_workers_usage=$(( 100 * busy_workers / total_workers ));

        info_text="${info_text} (${percent_workers_usage}%)";

        result="busy_workers=${busy_workers};;;0;${total_workers} idle_workers=${idle_workers};;;0;${total_workers} percent_workers_usage=${percent_workers_usage};75;90;0;100";

        if [[ ${percent_workers_usage} -gt 75 ]] && [[ ${percent_workers_usage} -lt 90 ]];
        then
            end_code=1;
        elif [[ ${percent_workers_usage} -ge 90 ]];
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

    "mpm_values")
        info_text="${1} MPM (${mpm_type}) settings checker";
        result="";
        end_code=0;

        read_values "${1}";

        #   overwrite keys in array for specific MPM
        while read -r key val; do
            MPM_VALUES["${key}"]="${val}";
        done < ${tmp_file};

        for key in "${!MPM_VALUES[@]}"; do
            snake_key=$(to_snake_case "${key}");

            result="${result} ${snake_key}=${MPM_VALUES[$key]};;;;";
        done;

        #   return output
        output="${output} OK: ${info_text} | ${result}";
    ;;

    "mpm_scoreboard")
        info_text="${1} MPM (${mpm_type}) scoreboard checker";
        result="";
        end_code=0;

        read_values "${1}";

        for char in "${!MPM_SCOREBOARD_CHAR_MAP[@]}"; do
            name="${MPM_SCOREBOARD_CHAR_MAP[$char]}";
            count=$(grep -o "[$char]" <<< "${tmp_file}" | wc -l);
            MPM_SCOREBOARD["$name"]=$count;
        done;

        for key in "${!MPM_SCOREBOARD[@]}"; do
            result="${result} ${key}=${MPM_SCOREBOARD[$key]};;;;";
        done;

        #   return output
        output="${output} OK: ${info_text} | ${result}";        
    ;;
esac;

echo ${output};

exit;
