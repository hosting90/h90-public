#!/bin/bash
#
#   Skript for a check of free max_conn
#   Author: Filip LANGER
#   Contact: filip.langer@group.one

#   CHANGELOG:
#       23.03.2026 - Fixed pool_size (max value)
#       19.03.2026 - First version

#   variables
tmp_file="/tmp/check_pgbouncer_pools.tmp";
output="PGBouncer pools | ";
password="${1}";

#   functions
function read_values() {
    #   no inputs available

    PGPASSWORD="${password}" psql -h 127.0.0.1 -p 6432 -U nagios pgbouncer -c "SHOW DATABASES;" -t -A > ${tmp_file};
    if [[ $? -gt 0 ]];
    then
        exit 1;
    fi;
}

function check_pools() {
    #   no inputs available

    for pool in $(cat ${tmp_file} | awk -F "|" '{print $1}'); do
        pool_size=$(cat ${tmp_file} | egrep "^${pool}" | awk -F "|" '{print $6}');
        curr_conn=$(cat ${tmp_file} | egrep "^${pool}" | awk -F "|" '{print $13}');

        output="${output} ${pool}_usage=${curr_conn};$((pool_size*80/100));$((pool_size*90/100));0;${pool_size}";
    done;

    echo $output;
  
    exit 0;
}

#   script body
read_values;
check_pools;

exit;
