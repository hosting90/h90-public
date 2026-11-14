#!/bin/bash
#
#   Skript for detailed monitoring of PHP FPM
#   Author: Filip LANGER
#   Contact: filip.langer@group.one

#   CHANGELOG:
#       14.11.2026 - Added a deeply monitoring for a PHP ACCESS and PHP SLOW logs
#       04.11.2026 - Change method for checking running (need to exists folder /etc/php/X.X/fpm/pool.d/)
#       22.09.2026 - Added a timeout value for locally socket reached limiting
#       15.09.2026 - Fixed wrong socket value if is listen value inside quotation mark
#       28.08.2026 - Added pool cpu usage monitoring
#       10.08.2026 - Added automatization output file (output for another cron jobs for clients)
#       08.07.2026 - Fixed exit codes for icinga2
#       08.06.2026 - Fixed wrong pool_memory calculating
#       30.03.2026 - First version

#   variables
tmp_file="/tmp/check_php_fpm_detailed_${1}.tmp";  #  $1 used for specified check
automatization_output_file="/tmp/check_php_fpm_detailed_output.txt";
access_delay="${2:-2}";
access_lookback=5;
socket_timeout="5"; # in seconds
output="PHP FPM ${1}";

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
    #   $1  PHP FPM Version (etc. 8.3)

    systemctl is-active php${1}-fpm >/dev/null 2>&1;
    if [[ $? -gt 0 ]];
    then
        return 1;
    else
        return 0;
    fi;
}

function read_values() {
    #   inputs values
    #   $1  string  type (etc. pool_process)
    #   $2  string  PHP FPM Version (etc. 8.3)
    #   $3  string  PHP FPM pool name (etc. www.conf)

    local type="${1}";
    local version="${2}";
    local pool_name="${3}";

    local script_name=$(cat /etc/php/${version}/fpm/pool.d/${pool_name} | sed "/^;/d" | grep "pm.status_path" | awk '{print $3}');
    local socket=$(cat /etc/php/${version}/fpm/pool.d/${pool_name} | sed "/^;/d" | grep "listen" | grep sock | awk '{print $3}' | sed 's/"//g');
    local pool_access=$(cat /etc/php/${version}/fpm/pool.d/${pool_name} | sed "/^;/d" | grep -i "access.log" | awk -F "\"" '{print $2}' | sed "s/\$pool/${pool_name}/g" | sed "s/\.conf//g");
    local pool_slow=$(cat /etc/php/${version}/fpm/pool.d/${pool_name} | sed "/^;/d" | grep -i "slowlog =" | awk -F "\"" '{print $2}' | sed "s/\$pool/${pool_name}/g" | sed "s/\.conf//g");

    case "${type}" in 
        "pool_access")
            if [[ -f "${pool_access}" ]];
            then
                target=$(date -d "${access_delay} minutes ago" +%Y%m%d%H%M);
                stop=$(date -d "$(( access_delay + access_lookback )) minutes ago" +%Y%m%d%H%M);
                label=$(date -d "${access_delay} minutes ago" +%H:%M);

                read -r req e5 e4 cpu_max < <(
    tac "${pool_access}" | LC_ALL=C awk -v target="$target" -v stop="$stop" '
    BEGIN { split("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec", m, " ")
            for (i = 1; i <= 12; i++) mon[m[i]] = sprintf("%02d", i) }
    function val(label,   p, s) { p = index($0, label " "); if (!p) return ""
        s = substr($0, p + length(label) + 1); sub(/ .*/, "", s); return s }
    {
        # line starts with: 14/Nov/2026:14:35:01 +0100
        split($1, t, /[\/:]/)                     # t[1]=dd t[2]=Mon t[3]=yyyy t[4]=HH t[5]=MM
        key = t[3] mon[t[2]] t[1] t[4] t[5]
        if (key < stop) exit                      # far enough back, done
        if (key != target) next
        n++
        st = val("Status") + 0
        if (st >= 500) e5++; else if (st >= 400) e4++
        cpu = val("Cpu usage") + 0; if (cpu > cmax) cmax = cpu
    }
    END { printf "%d %d %d %.2f\n", n, e5, e4, cmax }'
);

                echo -e "req_per_min ${req}\nstatus_5xx_per_min ${e5}\nstatus_4xx_per_min ${e4}\ncpu_max ${cpu_max}" > ${tmp_file}_${pool_name};
            fi;
        ;;

        "pool_slow")
            if [[ -f "${pool_slow}" ]];
            then
                target=$(date -d "${access_delay} minutes ago" +%Y%m%d%H%M);

                read -r total ext db sess slp fs other < <(
  tac "${pool_slow}" | LC_ALL=C awk -v target="$target" '
    BEGIN { split("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec", m, " ")
            for (i = 1; i <= 12; i++) mon[m[i]] = sprintf("%02d", i) }
 
    /^\[0x/ { frame = $2; next }                  # last one seen before script_filename = top frame
 
    /^script_filename = / {
        f = frame
        if      (f ~ /^(curl_|file_get_contents|fsockopen|stream_socket|SoapClient)/) cat = "ext"
        else if (f ~ /^(execute|query|prepare|exec)\(/ || f ~ /^(mysqli|pg_|PDO)/)    cat = "db"
        else if (f ~ /^session_/)                                    cat = "sess"
        else if (f ~ /^(sleep|usleep|time_nanosleep)\(/)             cat = "sleep"
        else if (f ~ /^(flock|fopen|fread|fwrite|file_put_contents)\(/) cat = "fs"
        else                                                         cat = "other"
        frame = ""; next
    }
 
    /^\[[0-9]+-[A-Za-z]+-[0-9]+ / {               # entry header = end of entry (reading backwards)
        split($1, d, /[\[-]/)                     # d[2]=dd d[3]=Mon d[4]=yyyy
        split($2, t, ":")                         # t[1]=HH t[2]=MM
        key = d[4] mon[d[3]] d[2] t[1] t[2]
        if (key < target) exit                    # entries are in time order: done
        if (key == target) { n++; c[cat == "" ? "other" : cat]++ }
        cat = ""; next
    }
 
    END { printf "%d %d %d %d %d %d %d\n", n, c["ext"], c["db"], c["sess"], c["sleep"], c["fs"], c["other"] }'
);

                echo -e "total ${total}\nexternal ${ext}\ndatabase ${db}\nsession_lock ${sess}\nsleep ${slp}\nfilesystem ${fs}\nother ${other}" > ${tmp_file}_${pool_name};
            fi;
        ;;

        "*")
            if [[ ! -z "${script_name}" ]] && [[ ! -z "${socket}" ]];
            then
                timeout ${socket_timeout} env SCRIPT_NAME=${script_name} SCRIPT_FILENAME=${script_name} REQUEST_METHOD=GET QUERY_STRING="" cgi-fcgi -bind -connect ${socket} > ${tmp_file}_${pool_name};
                if [[ $? -gt 0 ]];
                then
                    error "Can't reach pool [${pool_name}] stats!";
                    exit 1;
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
        for version in $(ls /etc/php/); do
            if [[ -d "/etc/php/${version}/fpm/pool.d" ]];
            then
                if check_running "${version}";
                then
                    result="${result} php_fpm_${version}=1;0;0;0;1";
                else
                    end_code=1;
                    result="${result} php_fpm_${version}=0;0;0;0;1";
                fi;
            fi;
        done;

        if [[ $end_code -eq 0 ]];
        then
            output="${output} OK | ${result}";
        else
            error "${output} PROBLEM | ${result}";
        fi;
    ;;

    "pool_process")
        info_text="info (idle/total)";
        result="";
        end_code=0;

        for version in $(ps aux | grep php | grep master | awk '{print $14}' | egrep -o "[0-9]\.[0-9]*"); do
            for pool in $(ls /etc/php/${version}/fpm/pool.d/); do
                read_values "${1}" "${version}" "${pool}";

                pool_file="${tmp_file}_${pool}";

                if [[ -f "${pool_file}" ]];
                then
                    pool_name=$(cat ${pool_file} | grep "pool:" | awk '{print $2}');
                    total_children=$(cat /etc/php/${version}/fpm/pool.d/${pool} | egrep "^pm.max_children" | awk '{print $3}' | egrep -o "[0-9]*");
                    total_processes=$(cat ${pool_file} | grep "total processes:" | awk '{print $3}');
                    idle_processes=$(( total_children - total_processes ));

                    info_text="${info_text} ${pool_name}_${version} (${idle_processes}/${total_children})";
                    result="${result} ${pool_name}_${version}_pool_free=${idle_processes};$(( total_children - (total_children*80/100) ));$(( total_children - (total_children*90/100) ));0;${total_children}";

                    if [[ ${idle_processes} -eq 0 ]];
                    then
                        end_code=1;
                    fi;
                fi;

                echo "${result}" > ${automatization_output_file};
            done;
        done;

        #   return info
        if [[ ${end_code} -eq 0 ]];
        then
            output="${output} OK: ${info_text} | ${result}";
        else
            error "${output} NOT ENOUGH POOLS: ${info_text} | ${result}";        
        fi;
    ;;

    "pool_memory")
        output="${output} MEMORY INFO (MB) |";

        for version in $(ps aux | grep php | grep master | awk '{print $14}' | egrep -o "[0-9]\.[0-9]*"); do
            for pool in $(ls /etc/php/${version}/fpm/pool.d/); do
                read_values "${1}" "${version}" "${pool}";

                pool_file="${tmp_file}_${pool}";

                if [[ -f "${pool_file}" ]];
                then
                    pool_name=$(cat ${pool_file} | grep "pool:" | awk '{print $2}');
                    mem_total_mb=$(free -m | grep "Mem:" | awk '{print $2}');
                    mem_used_percent=$(ps aux | egrep "php-fpm: pool ${pool_name}$" | awk '{sum += $4} END {print sum}');
                    mem_used_mb=$(printf "%.2f" $(echo "$mem_total_mb * $mem_used_percent / 100" | bc -l));

                    output="${output} ${pool_name}_${version}_memory_usage=${mem_used_mb};;;;";
                fi;
            done;
        done;
    ;;

    "pool_cpu")
        output="${output} CPU INFO (% of full CPU usage) |";

        for version in $(ps aux | grep php | grep master | awk '{print $14}' | egrep -o "[0-9]\.[0-9]*"); do
            for pool in $(ls /etc/php/${version}/fpm/pool.d/); do
                read_values "${1}" "${version}" "${pool}";

                pool_file="${tmp_file}_${pool}";

                if [[ -f "${pool_file}" ]];
                then
                    pool_name=$(cat ${pool_file} | grep "pool:" | awk '{print $2}');
                    cored_total=$(nproc);
                    cpu_used_percent=$(ps aux | egrep "php-fpm: pool ${pool_name}$" | awk -v cores="$cored_total" '{sum+=$3} END {printf "%.2f%%\n", sum/cores}');

                    output="${output} ${pool_name}_${version}_cpu_usage=${cpu_used_percent};50;80;0;100";
                fi;
            done;
        done;    
    ;;

    "max_memory")
        mem_total_gb=$(free -g | grep "Mem:" | awk '{print $2}');
        mem_used_percent=$(ps aux | grep "php-fpm: pool" | awk '{sum += $4} END {print sum}');
        mem_used_gb=$(printf "%.2f" $(echo "$mem_total_gb * $mem_used_percent / 100" | bc -l));

        output="${output} PHP FPM total RAM use (${mem_used_gb}/${mem_total_gb}GB) | total_fpm_mem_used=${mem_used_gb};$((mem_total_gb*80/100));$((mem_total_gb*90/100));0;${mem_total_gb} system_total_mem=${mem_total_gb};;;;";
    ;;

    "pool_access")
        output="${output} PHP ACCESS LOG DETAILS [/min] %STATUS%";

        i=0;
        for version in $(ps aux | grep php | grep master | awk '{print $14}' | egrep -o "[0-9]\.[0-9]*"); do
            for pool in $(ls /etc/php/${version}/fpm/pool.d/); do
                read_values "${1}" "${version}" "${pool}";

                pool_file="${tmp_file}_${pool}";

                if [[ -f "${pool_file}" ]];
                then
                    ((i++));
                    req_per_min=$(cat ${pool_file} | grep "req_per_min" | awk '{print $2}');
                    status_5xx_per_min=$(cat ${pool_file} | grep "status_5xx_per_min" | awk '{print $2}');
                    status_4xx_per_min=$(cat ${pool_file} | grep "status_4xx_per_min" | awk '{print $2}');
                    cpu_max=$(cat ${pool_file} | grep "cpu_max" | awk '{print $2}');

                    output="${output} ${pool}_${version}_req_per_min=${req_per_min};;;0; ${pool}_${version}_status_5xx_per_min=${status_5xx_per_min};;;0; ${pool}_${version}_status_4xx_per_min=${status_4xx_per_min};;;0; ${pool}_${version}_cpu_max=${cpu_max}%;;;0;";
                fi;
            done;
        done;

        if [[ $i -gt 0 ]];
        then
            output="$(echo $output | sed "s/%STATUS%/(Values successfuly loaded) |/g")";
        else
            output="$(echo $output | sed "s/%STATUS%/(No values found)/g")";
        fi;
    ;;

    "pool_slow")
        output="${output} PHP SLOW LOG DETAILS [/min] %STATUS%";

        i=0;
        for version in $(ps aux | grep php | grep master | awk '{print $14}' | egrep -o "[0-9]\.[0-9]*"); do
            for pool in $(ls /etc/php/${version}/fpm/pool.d/); do
                read_values "${1}" "${version}" "${pool}";

                pool_file="${tmp_file}_${pool}";

echo -e "total ${total}\nexternal ${ext}\ndatabase ${db}\nsession_lock ${sess}\nsleep ${slp}\nfilesystem ${fs}\nother ${other}" > ${tmp_file}_${pool_name};

                if [[ -f "${pool_file}" ]];
                then
                    ((i++));
                    total=$(cat ${pool_file} | grep "total" | awk '{print $2}');
                    external=$(cat ${pool_file} | grep "external" | awk '{print $2}');
                    database=$(cat ${pool_file} | grep "database" | awk '{print $2}');
                    session=$(cat ${pool_file} | grep "session" | awk '{print $2}');
                    sleep=$(cat ${pool_file} | grep "sleep" | awk '{print $2}');
                    filesystem=$(cat ${pool_file} | grep "filesystem" | awk '{print $2}');
                    other=$(cat ${pool_file} | grep "other" | awk '{print $2}');

                    output="${output} ${pool}_${version}_total_per_min=${total};;;0; ${pool}_${version}_external_per_min=${external};;;0; ${pool}_${version}_database_per_min=${database};;;0; ${pool}_${version}_session_per_min=${session};;;0; ${pool}_${version}_sleep_per_min=${sleep};;;0; ${pool}_${version}_filesystem_per_min=${filesystem};;;0; ${pool}_${version}_other_per_min=${other};;;0;";
                fi;
            done;
        done;

        if [[ $i -gt 0 ]];
        then
            output="$(echo $output | sed "s/%STATUS%/(Values successfuly loaded) |/g")";
        else
            output="$(echo $output | sed "s/%STATUS%/(No values found)/g")";
        fi;    
    ;;
esac;

echo ${output};

exit;
