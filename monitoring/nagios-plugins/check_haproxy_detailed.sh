#!/bin/bash
#
#   Script for detailed monitoring of HAProxy service
#   Author: Filip LANGER
#   Contact: filip.langer@group.one

#   CHANGELOG:
#       16.09.2026 - First version

#   variables
tmp_file="/tmp/check_haproxy_detailed_${1}.tmp";     #  $1 used for specified check
haproxy_version=$(haproxy -v | head -n 1 | awk '{print $3}' | egrep -o "[0-9\.]*" | head -n 1);
haproxy_stats_socket=$(grep -i "stats socket" /etc/haproxy/haproxy.cfg | head -n 1 | awk '{print $3}');
output="HAProxy v.${haproxy_version} ${1}";


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
        "traffic")
            echo "show info" | socat stdio ${haproxy_stats_socket} | egrep "Maxconn:|CurrConns:|ConnRate:|ConnRateLimit:|SessRate:|SessRateLimit:|SslRate:|SslRateLimit:" > ${tmp_file};
            if [[ $? -gt 0 ]];
            then
                error "Error while returning traffic values from socket!";
            fi;
        ;;

        "usage")
            echo "show info" | socat stdio ${haproxy_stats_socket} | egrep "Run_queue:|Idle_pct:" > ${tmp_file};
            if [[ $? -gt 0 ]];
            then
                error "Error while returning usage values from socket!";
            fi;        
        ;;

        "stats_frontend"|"stats_backend"|"stats_servers")
            STAT_OUTPUT=$(echo "show stat" | socat stdio "${haproxy_stats_socket}");
            HEADER=$(head -n1 <<< "$STAT_OUTPUT" | sed 's/^# //');
            TS=$(date +%s);

            if [[ -f "${tmp_file}" ]];
            then
                rm ${tmp_file};
            fi;

            echo "show stat" | socat stdio "${haproxy_stats_socket}" | awk -F',' -v header="$HEADER" -v ts="$TS" '
BEGIN {
    n = split(header, cols, ",")
    for (i = 1; i <= n; i++) idx[cols[i]] = i
}
/^#/ { next }
/^$/ { next }
{
    pxname   = $(idx["pxname"])
    svname   = $(idx["svname"])
    status   = idx["status"]   ? $(idx["status"])   : "-"
    scur     = idx["scur"]     ? $(idx["scur"])     : 0
    slim     = idx["slim"]     ? $(idx["slim"])     : 0
    qcur     = idx["qcur"]     ? $(idx["qcur"])     : 0
    chkfail  = idx["chkfail"]  ? $(idx["chkfail"])  : 0
    econ     = idx["econ"]     ? $(idx["econ"])     : 0
    eresp    = idx["eresp"]    ? $(idx["eresp"])    : 0
    hrsp5xx  = idx["hrsp_5xx"] ? $(idx["hrsp_5xx"]) : 0
    bin_b    = idx["bin"]      ? $(idx["bin"])      : 0
    bout_b   = idx["bout"]     ? $(idx["bout"])     : 0

    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n",
        ts, pxname, svname, status, scur, slim, qcur, chkfail, econ, eresp, hrsp5xx, bin_b, bout_b
}
' >> "${tmp_file}";
        ;;

        "stats_table")
            echo "show table" | socat stdio ${haproxy_stats_socket} | grep "^# table:" > ${tmp_file};
            if [[ $? -gt 0 ]];
            then
                error "Error while returning stick tables values from socket!";
            fi;          
        ;;
    esac;
}


#   script body
case ${1} in 
    "running")
        end_code=0;
        result="";
        for service in haproxy.service; do
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

        counter_alerts=$(haproxy_configtest 2>&1 | grep -i "alert" | wc -l);
        result="haproxy_config_errors=0;1;1;0;1";

        if [[ ${counter_alerts} -ne 0 ]];
        then
            end_code=2;
            info_text="${info_text} Errors on HAProxy's config found!";
            info_text="${info_text} ${test_output}";
            result="haproxy_config_errors=1;1;1;0;1";
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

    "traffic")
        info_text="${1}";
        result="";
        end_code=0;

        read_values "${1}";

        conn_limit=$(cat ${tmp_file} | grep "^Maxconn:" | awk '{print $2}');
        conn_actuall=$(cat ${tmp_file} | grep "^CurrConns:" | awk '{print $2}');

        connrate_limit=$(cat ${tmp_file} | grep "^ConnRateLimit:" | awk '{print $2}');    # unlimited = 0
        connrate_actuall=$(cat ${tmp_file} | grep "^ConnRate:" | awk '{print $2}');
        
        sessrate_limit=$(cat ${tmp_file} | grep "^SessRateLimit:" | awk '{print $2}');
        sessrate_actuall=$(cat ${tmp_file} | grep "^SessRate:" | awk '{print $2}');

        sslrate_limit=$(cat ${tmp_file} | grep "^SslRateLimit:" | awk '{print $2}');
        sslrate_actuall=$(cat ${tmp_file} | grep "^SslRate:" | awk '{print $2}');

        if [[ ${conn_limit} -ne 0 ]];
        then
            conn_percent=$(( (100 / conn_limit) * conn_actuall ));
            info_text="${info_text} connections ${conn_percent}%";
            result="${result} haproxy_connections=${conn_actuall};;;0;${conn_limit} haproxy_connections_percent=${conn_percent};75;90;0;100";
        else
            result="${result} haproxy_connections=${conn_actuall};;;0;";
        fi;
        if [[ ${connrate_limit} -ne 0 ]];
        then
            connrate_percent=$(( (100 / connreate_limit) * connrate_actuall ));
            info_text="${info_text} connections_rate ${connrate_percent}%";
            result="${result} haproxy_connections_rate=${connrate_actuall};;;0;${connrate_limit} haproxy_connections_rate_percent=${connrate_percent};75;90;0;100";
        else
            result="${result} haproxy_connections_rate=${connrate_actuall};;;0;";
        fi;        
        if [[ ${sessrate_limit} -ne 0 ]];
        then
            sessrate_percent=$(( (100 / sessreate_limit) * sessrate_actuall ));
            info_text="${info_text} sessions_rate ${sessrate_percent}%";
            result="${result} haproxy_sessions_rate=${sessrate_actuall};;;0;${sessrate_limit} haproxy_sessions_rate_percent=${sessrate_percent};75;90;0;100";
        else
            result="${result} haproxy_sessions_rate=${sessrate_actuall};;;0;";
        fi;                                
        if [[ ${sslrate_limit} -ne 0 ]];
        then
            sslrate_percent=$(( (100 / sslreate_limit) * sslrate_actuall ));
            info_text="${info_text} ssl_rate ${sslrate_percent}%";
            result="${result} haproxy_ssl_rate=${sslrate_actuall};;;0;${sslrate_limit} haproxy_ssl_rate_percent=${sslrate_percent};75;90;0;100";
        else
            result="${result} haproxy_ssl_rate=${sslrate_actuall};;;0;";
        fi;         

        if [[ $conn_percent -gt 90 ]] || [[ $connrate_percent -gt 90 ]] || [[ $sessrate_percent -gt 90 ]] || [[ $sslrate_percent -gt 90 ]];
        then
            end_code=2;
        else
            if [[ $conn_percent -gt 75 ]] || [[ $connrate_percent -gt 75 ]] || [[ $sessrate_percent -gt 75 ]] || [[ $sslrate_percent -gt 75 ]];
            then
                end_code=1;
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

    "usage")
        info_text="${1}";
        result="";
        end_code=0;

        read_values "${1}";

        queue_value=$(cat ${tmp_file} | grep "^Run_queue:" | awk '{print $2}');
        idle_value=$(cat ${tmp_file} | grep "^Idle_pct:" | awk '{print $2}');

        if [[ "${queue_value}" -gt 30 ]];
        then
            info_text="${info_text} Tasks queued HAproxy is under pressue (${queue_value} tasks waiting)";
            end_code=1;
        fi;

        if [[ ${idle_value} -le 10 ]];
        then
            end_code=2;
            info_text="${info_text} HAProxy is under critical usage pressure (idle is only ${idle_value}%)";
        elif [[ "${idle_value}" -le 25 ]] && [[ ${idle_value} -gt 10 ]];
        then
            end_code=1;
            info_text="${info_text} HAProxy is under higher usage pressure (idle is ${idle_value}%)";
        fi;

        result="${result} haproxy_queued_tasks=${queue_value};1;;0 haproxy_idle_percent_usage=${idle_value};25;10;0;100";

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

    "stats_frontend")
        info_text="${1}";
        result="";
        end_code=0;

        read_values "${1}";    

        counter_frontend_all=$(cat ${tmp_file} | grep "FRONTEND" | wc -l);
        counter_frontend_open=$(cat ${tmp_file} | grep "FRONTEND" | grep "OPEN" | wc -l);
        counter_frontend_stop=$(cat ${tmp_file} | grep "FRONTEND" | grep "STOP" | wc -l);

        if [[ ${counter_frontend_stop} -gt 0 ]];
        then
            end_code=2;
            info_text="${info_text} Some frontends are stopped";
        fi;
        result="${result} haproxy_frontend_stop=${counter_frontend_stop};1;1;0;${counter_frontend_all}";

        for frontend_name in $(cat ${tmp_file} | grep "FRONTEND" | awk '{print $2}'); do
            tmp_code=0;
            frontend_conn_limit=$(cat ${tmp_file} | grep -w "FRONTEND" | grep -w "${frontend_name}" | awk '{print $6}');
            frontend_conn_actuall=$(cat ${tmp_file} | grep -w "FRONTEND" | grep -w "${frontend_name}" | awk '{print $5}');
            frontend_usage_percent=$(( (100 / frontend_conn_limit) * frontend_conn_actuall ));

            if [[ ${frontend_usage_percent} -ge 90 ]];
            then
                tmp_code=2;
                info_text="${info_text} FRONTEND [${frontend_name}] critical usage (${frontend_usage_percent}%)";
            elif [[ ${frontend_usage_percent} -ge 75 ]] && [[ ${frontend_usage_percent} -lt 90 ]];
            then
                tmp_code=1;
                info_text="${info_text} FRONTEND [${frontend_name}] higher usage (${frontend_usage_percent}%)";
            fi;

            case ${end_code} in 
                0)
                    end_code=${tmp_code};
                ;;

                1)
                    if [[ $tmp_code -ne 0 ]];
                    then
                        end_code=${tmp_code};
                    fi;
                ;;
            esac;

            result="${result} haproxy_frontend_${frontend_name}_usage=${frontend_usage_percent};75;90;0;100";
        done;     

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

    "stats_backend")
        info_text="${1}";
        result="";
        end_code=0;

        read_values "${1}";    

        counter_backend_all=$(cat ${tmp_file} | grep "BACKEND" | wc -l);
        counter_backend_up=$(cat ${tmp_file} | grep "BACKEND" | grep "UP" | wc -l);
        counter_backend_down=$(cat ${tmp_file} | grep "BACKEND" | grep "DOWN" | wc -l);

        if [[ ${counter_backend_down} -gt 0 ]];
        then
            end_code=2;
            info_text="${info_text} Some backends are down";
        fi;        
        result="${result} haproxy_backend_down=${counter_backend_down};1;1;0;${counter_backend_all}";

        for backend_name in $(cat ${tmp_file} | grep -w "BACKEND" | awk '{print $2}'); do
            tmp_code=0;
            backend_conn_limit=$(cat ${tmp_file} | grep -w "BACKEND" | grep -w "${backend_name}" | awk '{print $6}');
            backend_conn_actuall=$(cat ${tmp_file} | grep -w "BACKEND" | grep -w "${backend_name}" | awk '{print $5}');
            backend_usage_percent=$(( (100 / backend_conn_limit) * backend_conn_actuall ));

            if [[ ${backend_usage_percent} -ge 90 ]];
            then
                tmp_code=2;
                info_text="${info_text} backend [${backend_name}] critical usage (${backend_usage_percent}%)";
            elif [[ ${backend_usage_percent} -ge 75 ]] && [[ ${backend_usage_percent} -lt 90 ]];
            then
                tmp_code=1;
                info_text="${info_text} backend [${backend_name}] higher usage (${backend_usage_percent}%)";
            fi;

            case ${end_code} in 
                0)
                    end_code=${tmp_code};
                ;;

                1)
                    if [[ $tmp_code -ne 0 ]];
                    then
                        end_code=${tmp_code};
                    fi;
                ;;
            esac;

            result="${result} haproxy_backend_${backend_name}_usage=${backend_usage_percent};75;90;0;100";
        done;   

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

    "stats_servers")
        info_text="${1}";
        result="";
        end_code=0;

        read_values "${1}";    

        counter_servers_all=$(cat ${tmp_file} | grep -v "BACKEND" | grep -v "FRONTEND" | wc -l);
        counter_servers_up=$(cat ${tmp_file} | grep -v "BACKEND" | grep -v "FRONTEND" | grep "UP" | wc -l);
        counter_servers_down=$(cat ${tmp_file} | grep -v "BACKEND" | grep -v "FRONTEND" | grep "DOWN" | wc -l);
        counter_servers_maint=$(cat ${tmp_file} | grep -v "BACKEND" | grep -v "FRONTEND" | grep "MAINT" | wc -l);
        counter_servers_drain=$(cat ${tmp_file} | grep -v "BACKEND" | grep -v "FRONTEND" | grep "DRAIN" | wc -l);
        counter_servers_nolb=$(cat ${tmp_file} | grep -v "BACKEND" | grep -v "FRONTEND" | grep "NOLB" | wc -l);
        counter_servers_no_check=$(cat ${tmp_file} | grep -v "BACKEND" | grep -v "FRONTEND" | grep "no check" | wc -l);

        if [[ ${counter_server_maint} -gt 0 ]];
        then
            end_code=1;
            info_text="${info_text} Some servers are in maintenance state";
        fi;

        if [[ ${counter_server_drain} -gt 0 ]];
        then
            end_code=1;
            info_text="${info_text} Some servers are in drain state";
        fi;

        if [[ ${counter_servers_nolb} -gt 0 ]];
        then
            end_code=1;
            info_text="${info_text} Some servers are in nolb state";
        fi;                

        if [[ ${counter_servers_down} -gt 0 ]];
        then
            end_code=2;
            info_text="${info_text} Some servers are down";
        fi;        
        result="${result} haproxy_servers_maint=${counter_servers_maint};1;1;0;${counter_servers_all} haproxy_servers_drain=${counter_servers_drain};1;1;0;${counter_servers_all} haproxy_servers_nolb=${counter_servers_nolb};1;1;0;${counter_servers_all} haproxy_servers_down=${counter_servers_down};1;1;0;${counter_servers_all}";

        for server_name in $(cat ${tmp_file} | grep -v "FRONTEND" | grep -v "BACKEND" | awk '{print $3}'); do
            tmp_code=0;
            server_conn_limit=$(cat ${tmp_file} | grep -v "FRONTEND" | grep -v "BACKEND" | grep -w "${server_name}" | awk '{print $6}');
            server_conn_actuall=$(cat ${tmp_file} | grep -v "FRONTEND" | grep -v "BACKEND" | grep -w "${server_name}" | awk '{print $5}');
            if [[ ${server_conn_limit} -eq 0 ]];
            then
                server_usage_percent=0;
            else
                server_usage_percent=$(( (100 / server_conn_limit) * server_conn_actuall ));
            fi;

            if [[ ${server_usage_percent} -ge 90 ]];
            then
                tmp_code=2;
                info_text="${info_text} server [${server_name}] critical usage (${server_usage_percent}%)";
            elif [[ ${server_usage_percent} -ge 75 ]] && [[ ${server_usage_percent} -lt 90 ]];
            then
                tmp_code=1;
                info_text="${info_text} server [${server_name}] higher usage (${server_usage_percent}%)";
            fi;

            case ${end_code} in 
                0)
                    end_code=${tmp_code};
                ;;

                1)
                    if [[ $tmp_code -ne 0 ]];
                    then
                        end_code=${tmp_code};
                    fi;
                ;;
            esac;

            result="${result} haproxy_server_${server_name}_usage=${server_usage_percent};75;90;0;100";
        done;    

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

    "stats_table")
        info_text="${1}";
        result="";
        end_code=0;

        read_values "${1}";    

        for table_name in $(cat ${tmp_file} | awk '{print $3}' | awk -F "," '{print $1}'); do
            table_size="$(cat ${tmp_file} | grep "${table_name}" | awk -F ":" '{print $4}' | awk -F "," '{print $1}')";
            table_used="$(cat ${tmp_file} | grep "${table_name}" | awk -F ":" '{print $5}')";
            table_usage_percent=$(( (100 / table_size) * table_used ));

            result="${result} haproxy_table_${table_name}_usage=${table_used};;;0;${table_size} haproxy_table_${table_name}_usage_percent=${table_usage_percent};75;90;0;100";

            if [[ $table_usage_percent -ge 90 ]];
            then
                end_code=2;
                info_text="${info_text} STICK TABLE [${table_name}] critical usage (${table_usage_percent}%)";
            elif [[ $table_usage_percent -lt 90 ]] && [[ $table_usage_percent -ge 75 ]];
            then
                if [[ $end_code -ne 2 ]];
                then
                    end_code=1;
                    info_text="${info_text} STICK TABLE [${table_name}] higher usage (${table_usage_percent}%)";
                fi;
            fi;
        done;

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
