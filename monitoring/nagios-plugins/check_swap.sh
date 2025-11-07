#!/bin/bash
#
#   Skript for a check of swap utilization
#   Author: Filip LANGER
#   Contact: filip.langer@group.one

#   variables

#   functions
function check_swap() {
    #   no inputs available

    local actuall_values=$(free -m | grep -i "swap" | awk '{print $2";"$3";"$4}');
    local total_swap=$(echo ${actuall_values} | awk -F ";" '{print $1}');
    local used_swap=$(echo ${actuall_values} | awk -F ";" '{print $2}');
    local free_swap=$(echo ${actuall_values} | awk -F ";" '{print $3}');

    if [[ $total_swap -eq 0 ]];
    then
        local percent_usage=0;
    else
        local percent_usage=$((used_swap * 100 / total_swap));
    fi;

    #   format 
    #   label=value[UOM];warn;crit;min;max

    echo "Swap usage: ${used_swap}MB/${total_swap}MB used (${percent_usage}%) | free_swap=${free_swap};$((total_swap - total_swap*80/100));$((total_swap - total_swap*90/100));0;${total_swap} percent_usage=${percent_usage};80;90;0;100";

    
    exit 0;
}

#   script body
check_swap;

exit;