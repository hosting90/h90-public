#!/bin/bash
#
#   Script for a Apache MPM monitoring (icinga)
#   Author: Filip LANGER
#   Contact: filip.langer@group.one

#   variables
APACHE_STATUS_PAGE="http://localhost/server-status?auto";
APACHE_MPM="";
APACHE_PROCESS_NAME="";
APACHE_CPU_USAGE="";
APACHE_MEM_USAGE=$(ps -C httpd -o rss= | awk '{sum+=$1} END {print sum/1024""}');   # MB
APACHE_BUSY_WORKERS="";
APACHE_IDLE_WORKERS="";
APACHE_MAX_WORKERS="";
APACHE_ACTUALL_WORKERS="";
APACHE_BUSY_THREADS="";
APACHE_IDLE_THREADS="";
APACHE_MAX_THREADS="";
APACHE_ACTUALL_THREADS="";
APACHE_THREADS_PER_CHILD="";
APACHE_MAX_CONN="";
APACHE_ACTUALL_CONN="";
CPU_CORES=$(nproc);
CURL_PAR="-s -L http://localhost/server-status?auto";

#   functions
#       error handling
function error() {
    #   inputs
    #   $1  string  error message

    echo -e "ERR:\t${1}";
    exit 1;
}

#       check MPM type
function check_mpm_type() {
    #   no inputs available

    APACHE_MPM=$(apachectl -V 2>/dev/null | grep -i "mpm" | awk -F ":" '{print $2}' | xargs);
}

#       check process name of Apache WWW server (etc. apache / httpd)
function check_process_name() {
    #   apache
    if [[ "$(pgrep apache | wc -l)" -gt 0 ]];
    then
        APACHE_PROCESS_NAME="apache";
    fi;

    #   httpd
    if [[ "$(pgrep httpd | wc -l)" -gt 0 ]];
    then
        APACHE_PROCESS_NAME="httpd";
    fi;    

    #   unknown
    if [[ -z "${APACHE_PROCESS_NAME}" ]];
    then
        error "Apache process name check (unknown process name / process not running).";
    fi;
}

#       checking MPM prefork
function check_prefork() {
    #   no inputs available

    #   MPM prefork
    #   1 process = 1 server = 1 worker = 1 child

    #   apache_max_workers (ServerLimit) = system limit, max system processes (can't be exceeded)
    #   apache_max_conn (MaxRequestWorkers) = maximum requests in one moment, can't be higher than max_workers    
    #   apache_cpu_usage = CPU usage (calculated with all threads / cores)
    #   apache_busy_workers = sum of procesing workers = servers = processes
    #   apache_idle_workers = sum of idle workers, that can immedeatelly process the request
    #   MPM prefork haven't threads

    #   actuall running servers (processes=workers=thread)
    APACHE_ACTUALL_WORKERS=$(pgrep ${APACHE_PROCESS_NAME} | wc -l);

    #   check for config file with a defined values
    for folder in /usr/local/apache /usr/local/apache2 /etc/apache2 /etc/httpd/; do
        if [[ -d "${folder}" && ! "${folder}" =~ ^/etc/apache2/ssl ]];
        then
            for file in $(grep -ri "${APACHE_MPM}" ${folder} | awk -F ":" '{print $1}'); do
                if [[ "${file}" =~ \.conf$|\.ini$ ]];
                then
                    APACHE_MAX_WORKERS=$(cat ${file} | grep -A 8 ${APACHE_MPM} | grep -i "ServerLimit" | sed '/^#/d' | awk '{print $2}');
                    APACHE_MAX_CONN=$(cat ${file} | grep -A 8 ${APACHE_MPM} | grep -i "MaxRequestWorkers" | sed '/^#/d' | awk '{print $2}');

                    #   if least one variable isn't empty
                    if [[ ! -z "${APACHE_MAX_WORKERS}" || ! -z "${APACHE_MAX_CONN}" ]];
                    then
                        break;
                    fi;
                fi;

            #   if least one variable isn't empty
            if [[ ! -z "${APACHE_MAX_WORKERS}" || ! -z "${APACHE_MAX_CONN}" ]];
            then
                break;
            fi;                
            done;
        fi;
    done;

    #   others values (server-status)
    APACHE_CPU_USAGE=$(curl ${CURL_PAR} | grep -i "CPULoad" | awk '{print $2}');
    APACHE_CPU_USAGE=$(echo "scale=2; ${APACHE_CPU_USAGE} / ${CPU_CORES}" | bc);
    APACHE_BUSY_WORKERS=$(curl ${CURL_PAR} | grep -i "BusyWorkers" | awk '{print $2}');
    APACHE_IDLE_WORKERS=$(curl ${CURL_PAR} | grep -i "IdleWorkers" | awk '{print $2}');
}

#       checking MPM worker
function check_worker() {
    #   no inputs available

    #   MPM worker
    #   1 process = 1 thread inside server process (each server = process can have ThreadsPerChild)

    #   apache_actuall_workers = sum of busy and idle threads
    #   apache_max_conn = MaxRequestWorkers
    #   apache_cpu_usage = CPU usage (calculated with all threads / cores)
    #   apache_busy_workers = sum of procesing workers
    #   apache_idle_workers = sum of idle workers, that can immedeatelly process the reuqest
    #   apache_threads_per_child = worker threads in each server proecess
    #   apache_busy_threads = apache_busy_workers * apache_threads_per_child
    #   apache_idle_threads = apache_idle_workers * apache_threads_per_child

    #   check for config file with a defined values
    for folder in /usr/local/apache /usr/local/apache2 /etc/apache2 /etc/httpd/; do
        if [[ -d "${folder}" && ! "${folder}" =~ ^/etc/apache2/ssl ]];
        then
            for file in $(grep -ri "${APACHE_MPM}" ${folder} | awk -F ":" '{print $1}'); do
                if [[ "${file}" =~ \.conf$|\.ini$ ]];
                then
                    APACHE_MAX_WORKERS=$(cat ${file} | grep -A 8 ${APACHE_MPM} | grep -i "ServerLimit" | sed '/^#/d' | awk '{print $2}');
                    APACHE_MAX_CONN=$(cat ${file} | grep -A 8 ${APACHE_MPM} | grep -i "MaxRequestWorkers" | sed '/^#/d' | awk '{print $2}');
                    APACHE_THREADS_PER_CHILD=$(cat ${file} | grep -A 8 ${APACHE_MPM} | grep -i "ThreadsPerChild" | sed '/^#/d' | awk '{print $2}');

                    #   if least one variable isn't empty
                    if [[ ! -z "${APACHE_MAX_WORKERS}" || ! -z "${APACHE_MAX_CONN}" || ! -z "${APACHE_THREADS_PER_CHILD}" ]];
                    then
                        break;
                    fi;
                fi;

            #   if least one variable isn't empty
            if [[ ! -z "${APACHE_MAX_WORKERS}" || ! -z "${APACHE_MAX_CONN}" || ! -z "${APACHE_THREADS_PER_CHILD}" ]];
            then
                break;
            fi;                
            done;
        fi;
    done;

    #   others values (server-status)
    APACHE_CPU_USAGE=$(curl ${CURL_PAR} | grep -i "CPULoad" | awk '{print $2}');
    APACHE_CPU_USAGE=$(echo "scale=2; ${APACHE_CPU_USAGE} / ${CPU_CORES}" | bc);
    APACHE_BUSY_WORKERS=$(curl ${CURL_PAR} | grep -i "BusyWorkers" | awk '{print $2}');
    APACHE_IDLE_WORKERS=$(curl ${CURL_PAR} | grep -i "IdleWorkers" | awk '{print $2}');
    APACHE_ACTUALL_WORKERS=$((APACHE_BUSY_WORKERS + APACHE_IDLE_WORKERS));
    APACHE_BUSY_THREADS=$((APACHE_BUSY_WORKERS * APACHE_THREADS_PER_CHILD));
    APACHE_IDLE_THREADS=$((APACHE_IDLE_WORKERS * APACHE_THREADS_PER_CHILD));
    APACHE_ACTUALL_THREADS=$((APACHE_BUSY_THREADS + APACHE_IDLE_THREADS));
}

#       checking MPM event
function check_event() {
    #   no inputs available

    #   MPM event
    #   1 process = 1 thread inside server process (each server = process can have ThreadsPerChild)

    #   MAX THREADS is limited by MaxRequestWorkers (but that a at same time), other limit is ServerLimit * ThreadsPerChild

    #   apache_actuall_workers = sum of busy and idle threads
    #   apache_max_conn = MaxRequestWorkers
    #   apache_cpu_usage = CPU usage (calculated with all threads / cores)
    #   apache_busy_workers = sum of procesing workers
    #   apache_idle_workers = sum of idle workers, that can immedeatelly process the reuqest
    #   apache_threads_per_child = worker threads in each server proecess
    #   apache_busy_threads = apache_busy_workers * apache_threads_per_child
    #   apache_idle_threads = apache_idle_workers * apache_threads_per_child

    #   check for config file with a defined values
    for folder in /usr/local/apache /usr/local/apache2 /etc/apache2 /etc/httpd/; do
        if [[ -d "${folder}" && ! "${folder}" =~ ^/etc/apache2/ssl ]];
        then
            for file in $(grep -ri "${APACHE_MPM}" ${folder} | awk -F ":" '{print $1}'); do
                if [[ "${file}" =~ \.conf$|\.ini$ ]];
                then
                    APACHE_MAX_WORKERS=$(cat ${file} | grep -A 8 ${APACHE_MPM} | grep -i "ServerLimit" | sed '/^#/d' | awk '{print $2}');
                    APACHE_MAX_CONN=$(cat ${file} | grep -A 8 ${APACHE_MPM} | grep -i "MaxRequestWorkers" | sed '/^#/d' | awk '{print $2}');
                    APACHE_THREADS_PER_CHILD=$(cat ${file} | grep -A 8 ${APACHE_MPM} | grep -i "ThreadsPerChild" | sed '/^#/d' | awk '{print $2}');
                fi;
            done;
        fi;
    done;

    #   others values (server-status)
    APACHE_CPU_USAGE=$(curl ${CURL_PAR} | grep -i "CPULoad" | awk '{print $2}');
    APACHE_CPU_USAGE=$(echo "scale=2; ${APACHE_CPU_USAGE} / ${CPU_CORES}" | bc);
    APACHE_BUSY_WORKERS=$(curl ${CURL_PAR} | grep -i "BusyWorkers" | awk '{print $2}');
    APACHE_IDLE_WORKERS=$(curl ${CURL_PAR} | grep -i "IdleWorkers" | awk '{print $2}');
    APACHE_ACTUALL_WORKERS=$((APACHE_BUSY_WORKERS + APACHE_IDLE_WORKERS));
    APACHE_BUSY_THREADS=$((APACHE_BUSY_WORKERS * APACHE_THREADS_PER_CHILD));
    APACHE_IDLE_THREADS=$((APACHE_IDLE_WORKERS * APACHE_THREADS_PER_CHILD));
    APACHE_ACTUALL_THREADS=$((APACHE_BUSY_THREADS + APACHE_IDLE_THREADS));
}

#       calculating values
function calculate_others() {
    #   no inputs available

    #   if ServerLimit isn't defined
    if [[ -z "${APACHE_MAX_WORKERS}" ]];
    then
        case "${APACHE_MPM}" in 
            "prefork")
                APACHE_MAX_WORKERS="${APACHE_MAX_CONN}";
            ;;

            "worker"|"event")
                APACHE_MAX_WORKERS=$((APACHE_MAX_CONN / APACHE_THREADS_PER_CHILD));
            ;;
        esac;
    fi;

    #   percentage values
    percent_workers_usage=$((APACHE_ACTUALL_WORKERS * 100 / APACHE_MAX_WORKERS));

    if [[ "${APACHE_MPM}" == "worker" || "${APACHE_MPM}" == "event" ]];
    then
        APACHE_MAX_THREADS=$((APACHE_MAX_WORKERS * APACHE_THREADS_PER_CHILD));
        percent_threads_usage=$((APACHE_ACTUALL_THREADS * 100 / APACHE_MAX_THREADS ));
    fi;
}

#       printing values
function print_values() {
    #   no inputs available

    case "${APACHE_MPM}" in
        "prefork")
            echo "Apache MPM ${APACHE_MPM}: ${APACHE_ACTUALL_WORKERS}/${APACHE_MAX_WORKERS} used (${percent_workers_usage}%) | apache_workers=${APACHE_ACTUALL_WORKERS};$((APACHE_MAX_WORKERS*80/100));$((APACHE_MAX_WORKERS*90/100));0;${APACHE_MAX_WORKERS} apache_workers_percent=${percent_workers_usage};80;90;0;100 apache_cpu_load=${APACHE_CPU_USAGE};80;90;0;100";
        ;;

        "worker"|"event")
            echo "Apache MPM ${APACHE_MPM}: ${APACHE_ACTUALL_WORKERS}/${APACHE_MAX_WORKERS} used (${percent_workers_usage}%) | apache_workers=${APACHE_ACTUALL_WORKERS};$((APACHE_MAX_WORKERS*80/100));$((APACHE_MAX_WORKERS*90/100));0;${APACHE_MAX_WORKERS} apache_workers_percent=${percent_workers_usage};80;90;0;100 apache_threads=${APACHE_ACTUALL_THREADS};$((APACHE_MAX_THREADS*80/100));$((APACHE_MAX_THREADS*90/100));0;${APACHE_MAX_THREADS} apache_threads_percent=${percent_threads_usage};80;90;0;100 apache_cpu_load=${APACHE_CPU_USAGE};80;90;0;100";        
        ;;
    esac;
}

#   script body
check_mpm_type;

check_process_name;

case ${APACHE_MPM} in
    "prefork")
        check_prefork;
    ;;

    "worker")
        check_worker;
    ;;

    "event")
        check_event;
    ;;

    *)
        error "Apache MPM check (uknown MPM [${APACHE_MPM}])";
    ;;
esac;

calculate_others;

print_values;

exit;
