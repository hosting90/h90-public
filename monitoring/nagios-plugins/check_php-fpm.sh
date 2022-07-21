#!/bin/bash

#
# @author Tomas Henzl (tomas.henzl@webglobe.com)
#
# changelog:
#   2022/07/21 - created
#

function die() { echo "$1" 1>&2; exit "${2:-1}"; }

#
# lets get data from each socket:uri
#

for fpm_connection_info in "$@"; do
    IFS=: read socket uri <<< "$fpm_connection_info"

    _result=$(
        SCRIPT_NAME="$uri" \
        SCRIPT_FILENAME="$uri" \
        REQUEST_METHOD=GET \
        cgi-fcgi -bind -connect "$socket" 2>/dev/null
    )

    result_rets+=( $? )
    result_values+=( "$_result" )
    result_sockets+=( "$socket" )
    result_uris+=( "$uri" )
done


#
# parse performace data
#

for (( i=0; i < ${#result_values[@]}; i++ )); do
    while IFS=: read name value; do
        [[ -z "$value" ]] && continue

        value="${value// /}"
        #echo "$name - $value"

        case "$name" in
            pool) pool="$value"; pools+=( "$pool" );;

            'idle processes')       performace_data+=" ${pool}_idle_procs=${value:-0}";;
            'active processes')     performace_data+=" ${pool}_active_procs=${value:-0}"; pools_active_procs+=( $value );;
            'total processes')      performace_data+=" ${pool}_total_procs=${value:-0}";;
            'max active processes') performace_data+=" ${pool}_max_active_procs=${value:-0}";;
        esac
    done <<< "${result_values[$i]}"

    # some pool did not return zero, hard error
    if [[  "${result_rets[$i]}" != "0" ]]; then
        msg_status='CRITICAL'
        msg_details="${result_sockets[$i]}:${result_uris[$i]} command returned non zero"
        ret=2
    fi

    # some pool did not provided data, hard error
    if [[ -z "${pools[$i]}" ]]; then
        msg_status='CRITICAL'
        msg_details+="; ${result_sockets[$i]}:${result_uris[$i]} returned invalid value"
        ret=2
    fi
done

#
# print all info
#

echo -n "${msg_status:-OK}: "

# exit immediatelly on this error
[[ -n "$msg_details" ]] && die "$msg_details" "$ret"

# or print status & performace_data
echo -n "All pools running: "
for (( i=0; i < ${#pools[@]}; i++ )); do
    echo -n "${pools[$i]} (${pools_active_procs[$i]} working)"

    (( i+1 < ${#pools[@]} )) && echo -n ', '
done

echo "|$performace_data"

