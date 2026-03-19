#!/bin/bash
#
#   Skript for a check of free max_conn
#   Author: Filip LANGER
#   Contact: filip.langer@group.one

#   CHANGELOG:
#       19.03.2026 - First version

#   variables
tmp_file="/tmp/check_pgbouncer_pools.tmp";
output="PGBouncer pools: | ";
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
        max_conn=$(cat ${tmp_file} | egrep "^${pool}" | awk -F "|" '{print $12}');
        curr_conn=$(cat ${tmp_file} | egrep "^${pool}" | awk -F "|" '{print $13}');

        output="${output} ${pool}_usage=${curr_conn};$((max_conn*80/100));$((max_conn*90/100));0;${max_conn}";
    done;

    echo $output;
  
    exit 0;
}

#   script body
read_values;
check_pools;

exit;
