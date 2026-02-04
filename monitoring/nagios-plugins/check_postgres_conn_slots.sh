#!/bin/bash
#
#   Skript for a check of free max_conn
#   Author: Filip LANGER
#   Contact: filip.langer@group.one

#   CHANGELOG:
#       04.02.2026 - First version

#   variables


#   functions
function check_slots() {
    #   no inputs available

    #   input values from postgres
    in_values=$(su - postgres -c "psql -c \"SELECT max_conn, used, res_for_super, (max_conn - res_for_super - used) AS res_for_normal FROM (SELECT count(*) as used FROM pg_stat_activity) t1, (SELECT setting::int AS res_for_super FROM pg_settings WHERE name='superuser_reserved_connections') t2, (SELECT setting::int AS max_conn FROM pg_settings WHERE name='max_connections') t3;\"" | tail -n 3 | head -n 1);
    max_conn=$(echo ${in_values} | awk -F "|" '{print $1}' | egrep -o "[0-9]*");
    used_conn=$(echo ${in_values} | awk -F "|" '{print $2}' | egrep -o "[0-9]*");
    res_super=$(echo ${in_values} | awk -F "|" '{print $3}' | egrep -o "[0-9]*");
    res_normal=$(echo ${in_values} | awk -F "|" '{print $4}' | egrep -o "[0-9]*");

    #   matematical operations
    total_slots=${max_conn};
    used_slots=$((used_conn + res_super));
    percent_usage=$((used_slots * 100 / total_slots));

    echo "PostgreSQL conn slots: ${used_slots}/${total_slots} used (${percent_usage}%) | used_slots=${used_slots};$((used_slots*80/100));$((used_slots*90/100));0;${total_slots} total_slots=${total_slots};;;0";
  
    exit 0;
}

#   script body
check_slots;

exit;
