#!/bin/bash
#
#   Script for detailed monitoring of HAProxy service
#   Author: Filip LANGER
#   Contact: filip.langer@group.one

#   CHANGELOG:
#       24.11.2026 - Added deeply SSL certificates checks (collaborate with Claude AI)
#       26.09.2026 - Fixed non-funcional conditions for stats_servers (maintenance | drain)
#       18.09.2026 - Fixed error when no stick tables found
#       16.09.2026 - First version

#   variables
tmp_file="/tmp/check_haproxy_detailed_${1}.tmp";     #  $1 used for specified check
haproxy_version=$(haproxy -v | head -n 1 | awk '{print $3}' | egrep -o "[0-9\.]*" | head -n 1);
haproxy_stats_socket=$(grep -i "stats socket" /etc/haproxy/haproxy.cfg | head -n 1 | awk '{print $3}');
haproxy_confs=(/etc/haproxy/haproxy.cfg /etc/haproxy/conf.d/); # in these files / folders script checks for crt paths / certificates files
ssl_warn_days=7;
ssl_sclient_timeout=5;
output="HAProxy v.${haproxy_version} ${1}";

set -o pipefail;


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

# === MULTIPLE FUNCTIONS FOR SSL CHECKS ===
function return_config_files() {
    #   no inputs available

    local config;
    for config in "${haproxy_confs[@]}"; do
        if [[ -d "${config}" ]];
        then
            #   directory
            find "${config}" -maxdepth 1 -type f -name '*.conf' | sort;
        elif [[ -f "${config}" ]];
        then
            #   file itself
            echo "${config}";
        fi;
    done;
}

function return_bind_certs() {
    # no inputs available

    return_config_files | xargs -r awk '
    { sub(/#.*/, "") }
    $1 == "crt-base" { base = $2; next }
    $1 == "bind" {
      for (i = 3; i < NF; i++)
        if ($i == "crt" || $i == "crt-list") {
          p = $(i+1)
          if (p !~ /^\// && base != "") p = base "/" p
          print $i, p, $2
        }
    }';
}

function return_normalize_addr() {
    #   input: $1 = bind address (e.g. 10.0.0.5:443, *:443, ipv6@:::443)
    #       return easily s_client target (IPv4 / IPv6)

    local a=${1#ipv4@}; a=${a#ipv6@};
    [[ $a == unix@* || $a == abns@* || $a == /* || $a == fd@* || $a == sockpair@* ]] && return;

    local port=${a##*:} host=${a%:*};

    host=${host#[}; host=${host%]};

    case $host in ""|"*"|0.0.0.0|::|"::0") host=$wildcard_ip ;; esac;

    [[ $host == *:* ]] && host="[$host]";

    echo "$host:$port";
}

function return_cert_targets() {
    #   no inputs available

    return_bind_certs | while read -r kw path addrs; do
    local files;

    case $kw in
      crt-list)
        files=$(grep -v '^[[:space:]]*#' "$path" 2>/dev/null | awk 'NF{print $1}');
        ;;
      *)
        if [[ -d $path ]]; then
          files=$(find "$path" -maxdepth 1 -type f \
            ! -name '*.key' ! -name '*.ocsp' ! -name '*.issuer' ! -name '*.sctl');
        else
          files=$path;
        fi ;;
    esac;

    local IFS=','; local addr_list=($addrs); unset IFS;
    local f a t;

    while read -r f; do
      [[ -z $f ]] && continue;
      if [[ -n $LOCAL_TARGET ]]; then
        echo "$f $LOCAL_TARGET";
      else
        for a in "${addr_list[@]}"; do
          t=$(return_normalize_addr "$a"); [[ -n $t ]] && echo "$f $t";
        done;
      fi;
    done <<<"$files";
  done | sort -u;
}

function return_cert_names() {
    #   stdin = PEM certificate
    #       prints CN + all DNS SANs

    local pem; pem=$(cat);
    {
        openssl x509 -noout -subject -nameopt multiline <<<"$pem" 2>/dev/null | awk -F' = ' '/commonName/{print $2}';
        openssl x509 -noout -ext subjectAltName <<<"$pem" 2>/dev/null | grep -oE 'DNS:[^,[:space:]]+' | cut -d: -f2;
    } | sort -u;
}

function return_exp_state() {
    #   stdin = PEM certificate
    #       prints: EXPIRED / EXPIRING / OK

    local pem; pem=$(cat);

    if ! openssl x509 -noout -checkend 0 <<<"$pem" >/dev/null 2>&1; then
        echo "EXPIRED";
    elif ! openssl x509 -noout -checkend $((ssl_warn_days*86400)) <<<"$pem" >/dev/null 2>&1; then
        echo "EXPIRING";
    else
        echo "VALID";
    fi;
}

function fp() {
    openssl x509 -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2;
}

function enddate() {
    openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2;
}

function subject() {
    openssl x509 -noout -subject 2>/dev/null | sed 's/^subject= *//';
}
# === END OF MULTIPLE FUNCTIONS FOR SSL CHECKS ===

function read_values() {
    #   inputs values
    #   $1  string  command (check|list-backups...)

    local cmd="${1}";

    case "${cmd}" in
        "ssl")
            declare -A targets order;
            n=0;

            while read -r f t; do
                [[ -z ${targets[$f]+x} ]] && order[$((n++))]=$f;
                targets[$f]+="$t ";
            done < <(return_cert_targets);

            for ((i = 0; i < n; i++)); do
                f=${order[$i]};
                echo "== $f   (bind: ${targets[$f]% })";

                # ---- 1) FILE ----
                pem=$(openssl x509 -in "$f" 2>/dev/null) || true;
                if [[ -z $pem ]]; then
                    printf '  %-5s %-9s cannot read/parse certificate\n' FILE ERROR;
                    continue;
                fi;

                end=$(enddate <<<"$pem");
                st=$(return_exp_state <<<"$pem");
                file_fp=$(fp <<<"$pem");

                printf '  %-5s %-9s %-26s %s\n' FILE "$st" "exp $end" "$(subject <<<"$pem")"

                # ---- 2) LIVE: every domain x every bind address of this cert ----
                names=$(return_cert_names <<<"$pem");

                for t in ${targets[$f]}; do
                    while read -r name; do
                        [[ -z $name ]] && continue;
                        sni=$name;
                        [[ $sni == \*.* ]] && sni="wildcard-test.${sni#*.}";

                        served=$(timeout "${ssl_sclient_timeout}" openssl s_client -connect "$t" -servername "$sni" \
                                    </dev/null 2>/dev/null | openssl x509 2>/dev/null) || true;

                        if [[ -z $served ]]; then
                            printf '  %-5s %-9s %-9s %-32s %-22s no TLS answer\n' \
                                LIVE NO-CONN "-" "$name" "$t";
                            continue;
                        fi;

                        live_st=$(return_exp_state <<<"$served");
                        live_end=$(enddate <<<"$served");

                        if [[ $(fp <<<"$served") == "$file_fp" ]]; then
                            printf '  %-5s %-9s %-9s %-32s %-22s exp %s\n' \
                                LIVE MATCH "$live_st" "$name" "$t" "$live_end";
                        else
                            printf '  %-5s %-9s %-9s %-32s %-22s exp %s  served: %s\n' \
                                LIVE MISMATCH "$live_st" "$name" "$t" "$live_end" "$(subject <<<"$served")";
                        fi;
                    done <<<"$names";
                done;
            done > ${tmp_file};
        ;;

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
            if [[ $(echo "show table" | socat stdio ${haproxy_stats_socket} | grep "^# table:" | wc -l) -eq 0 ]];
            then
                if [[ -f "${tmp_file}" ]];
                then
                    rm ${tmp_file};
                fi;
                touch ${tmp_file};
            else
                echo "show table" | socat stdio ${haproxy_stats_socket} | grep "^# table:" > ${tmp_file};
                if [[ $? -gt 0 ]];
                then
                    error "Error while returning stick tables values from socket!";
                fi;             
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

        while IFS= read -r line; do
            tmp_code=0;
            frontend_name=$(echo $line | awk '{print $2}');
            frontend_conn_limit=$(echo $line | awk '{print $6}');
            frontend_conn_actuall=$(echo $line | awk '{print $5}');
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
        done < <(grep -w "FRONTEND" "${tmp_file}")

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

        while IFS= read -r line; do
            tmp_code=0;
            backend_name=$(echo $line | awk '{print $2}');
            backend_conn_limit=$(echo $line | awk '{print $6}');
            backend_conn_actuall=$(echo $line | awk '{print $5}');
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
        done < <(grep -w "BACKEND" "${tmp_file}")

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

        if [[ ${counter_servers_maint} -gt 0 ]];
        then
            end_code=1;
            info_text="${info_text} Some servers are in maintenance state";
        fi;

        if [[ ${counter_servers_drain} -gt 0 ]];
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

        while IFS= read -r line; do
            tmp_code=0;
            server_name=$(echo $line | awk '{print $3}');
            server_conn_limit=$(echo $line | awk '{print $6}');
            server_conn_actuall=$(echo $line | awk '{print $5}');

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
        done < <(grep -vwE "FRONTEND|BACKEND" "${tmp_file}")

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

        if [[ "$(cat ${tmp_file} | wc -l)" -eq 0 ]];
        then
            tmp_code=0;
            info_text="${info_text} None stick tables found";
        else
            while IFS= read -r line; do
                tmp_code=0;
                table_name=$(echo $line | awk '{print $3}' | awk -F "," '{print $1}');
                table_size="$(echo $line | awk -F ":" '{print $4}' | awk -F "," '{print $1}')";
                table_used="$(echo $line | awk -F ":" '{print $5}')";
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
            done < "${tmp_file}";
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

    "ssl")
        info_text="${1}";
        result="";
        end_code=0;

        read_values "${1}";

        if [[ "$(cat ${tmp_file} | wc -l)" -eq 0 ]]       ;
        then
            end_code=0;
            info_text="${info_text} None of SSL found.";
        else
            end_code=0;

            counter_files=$(cat ${tmp_file} | grep "==" | wc -l);
            counter_all=$(cat ${tmp_file} | sed "/==/d" | sed "/^$/d" | wc -l);
            counter_valid=$(cat ${tmp_file} | sed "/==/d" | sed "/^$/d" | grep "VALID" | wc -l);
            counter_expiring=$(cat ${tmp_file} | sed "/==/d" | sed "/^$/d" | grep "EXPIRING" | wc -l);
            counter_expired=$(cat ${tmp_file} | sed "/==/d" | sed "/^$/d" | grep "EXPIRED" | wc -l);

            info_text="${info_text} HAProxy SSL certificates (all/valid/expiring/expired) (${counter_all}/${counter_valid}/${counter_expiring}/${counter_expired})";
            result="${result} haproxy_certs_files=${counter_files};;;0; haproxy_ssl_all=${counter_all};;;0; haproxy_ssl_valid=${counter_valid};;;0;${counter_all} haproxy_ssl_expiring=${counter_expiring};1;;0;${counter_all} haproxy_ssl_expired=${counter_expired};1;1;0;${counter_all}";

            if [[ ${counter_expired} -gt 0 ]];
            then
                expired_certificates="$(cat ${tmp_file} | grep "EXPIRED")";
                info_text="${info_text} Some SSL certificated Expired! (${expired_certificates})";
                end_code=2;
            else
                if [[ ${counter_expiring} -gt 0 ]];
                then
                    expiring_certificates="$(cat ${tmp_file} | grep "EXPIRING")";
                    info_text="${info_text} Some SSL certificated are close to expired (=< ${ssl_warn_days}) (expiring_certificates)";
                    end_code=1;
                fi;
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
esac;

echo ${output};

exit;
