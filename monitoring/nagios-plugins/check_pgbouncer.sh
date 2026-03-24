#!/bin/bash
#
#   Skript for detailed PGBouncer monitoring
#   Author: Filip LANGER
#   Contact: filip.langer@group.one

#   CHANGELOG:
#       24.03.2026 - Change input data (from direct pgbouncer connect to pgbouncer-exporter)
#                   - added multiple monitoring values
#       23.03.2026 - Fixed pool_size (max value)
#       19.03.2026 - First version

#   variables
tmp_file="/tmp/check_pgbouncer_pools_${1}.tmp";  #  $1 used for specified check
output="PGBouncer ${1}";

#   functions
function error() {
    #   inputs values
    #   $1  string  message

    output="${output} ERROR: ${1}";
    exit 1;
}

function read_values() {
    #   no inputs available

    curl -s -L localhost:9127/metrics | grep -v "#" > ${tmp_file};
    if [[ $? -gt 0 ]];
    then
        error "Can't reach metrics of pgbouncer exporter!";
    fi;
}

function check_running() {
    #   no inputs available

    local running_value=$(cat ${tmp_file} | grep "pgbouncer_up" | awk '{print $2}');

    if [[ "$running_value" != "1" ]];
    then
        output="${output} NOT RUNNING! | pgbouncer_running=0;0;0;0;1";
    else
        output="${output} OK | pgbouncer_running=1;0;0;0;1";
    fi;
}

function return_pools() {
    #   input values
    #   $1  string  type(databases|databases_count|pools|pools_count)

    case ${1} in 
        "databases")
            local databases="";

            i=0;
            for db in $(grep -F "pgbouncer_pools_client_active_cancel_connection" ${tmp_file} | awk -F "\"" '{print $2}' | sort | uniq); do
                if [[ "${i}" -eq 0 ]];
                then
                    local databases="${db}";
                else
                    local databases="${databases} ${db}";
                fi;

                ((i++));
            done;

            echo "$databases";
        ;;

        "databases_count")
            local databases_count=$(cat ${tmp_file} | grep "pgbouncer_databases " | awk '{print $2}');

            echo "${databases_count}";
        ;;

        "pools")
            local pools="";

            i=0;
            for pls in $(grep -F pgbouncer_pools_client_active_cancel_connection ${tmp_file} | awk -F "\"" '{print $2";;"$4}'); do
                if [[ ${i} -eq 0 ]];
                then
                    local pools="${pls}";
                else
                    local pools="${pools} ${pls}";
                fi;

                ((i++));
            done;            

            echo "${pools}";
        ;;

        "pools_count")
            local pools_count=$(cat ${tmp_file} | grep "pgbouncer_pools " | awk '{print $2}');

            echo "${pools_count}";
        ;;
    esac;
}

function check_pool_size() {
    #   no inputs available

    pools_count=$(return_pools "pools_count");
    pools=$(return_pools "pools");

    output="${output} #${pools_count} |";

    for pool in ${pools}; do
        database=$(echo ${pool} | awk -F ";;" '{print $1}');
        user=$(echo ${pool} | awk -F ";;" '{print $2}');
        pool_size=$(cat ${tmp_file} | grep "pgbouncer_databases_pool_size" | grep "name=\"${database}\"" | awk '{print $2}');
        pool_conn=$(cat ${tmp_file} | egrep "pgbouncer_pools_client" | grep "database=\"${database}\"" | grep "user=\"${user}\"" | awk '{sum += $2} END {print sum}');

        output="${output} ${pool}_usage=${pool_conn};$((pool_size*80/100));$((pool_size*90/100));0;${pool_size}";
    done;
}

function check_max_db_connections() {
    #   no inputs available

    databases_count=$(return_pools "databases_count");
    databases=$(return_pools "databases");

    output="${output} #${databases_count} |";

    for database in ${databases}; do
        max_db_conn=$(cat ${tmp_file} | grep "pgbouncer_databases_max_connections" | grep "name=\"${database}\"" | awk '{print $2}');
        db_conn=$(cat ${tmp_file} | grep "pgbouncer_pools_client" | grep "connections" | grep "database=\"${database}\"" | awk '{sum += $2} END {print sum}');

        output="${output} ${database}_usage=${db_conn};$((max_db_conn*80/100));$((max_db_conn*90/100));0;${max_db_conn}";
    done;    
}

function check_max_client_conn() {
    #   no inputs available

    max_client_conn=$(cat ${tmp_file} | grep "pgbouncer_config_max_client_connections " | awk '{print $2}');
    client_conn=$(cat ${tmp_file} | grep "pgbouncer_pools_client" | grep "connections" | awk '{sum += $2} END {print sum}');

    output="${output} [${client_conn}/${max_client_conn}] | client_conn=${client_conn};$((max_client_conn*80/100));$((max_client_conn*90/100));0;${max_client_conn}";
}

function check_client_waiting() {
    #   no inputs available

    pools_count=$(return_pools "pools_count");
    pools=$(return_pools "pools");

    tmp=$(cat ${tmp_file} | egrep "pgbouncer_pools_client_waiting_connections" | awk '{sum += $2} END {print sum}');
    
    output="${output} #${tmp} |";

    for pool in ${pools}; do
        database=$(echo ${pool} | awk -F ";;" '{print $1}');
        user=$(echo ${pool} | awk -F ";;" '{print $2}');
        max_wait=0;
        wait_conn=$(cat ${tmp_file} | egrep "pgbouncer_pools_client_waiting_connections" | grep "database=\"${database}\"" | grep "user=\"${user}\"" | awk '{sum += $2} END {print sum}');

        output="${output} ${pool}_waiting=${wait_conn};1;1;0;1";
    done;    
}

#   script body
read_values;

case ${1} in 
    "running")
        check_running;
    ;;

    "pool_size")
        check_pool_size;
    ;;

    "max_db_connections")
        check_max_db_connections;
    ;;

    "max_client_conn")
        check_max_client_conn;
    ;;

    "clients_waiting")
        check_client_waiting
    ;;
esac;

echo ${output};

exit;
