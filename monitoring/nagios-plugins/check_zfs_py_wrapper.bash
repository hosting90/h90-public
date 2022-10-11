#!/bin/bash

#
# Checks zfs pools, wrapper around check_zfs.py which does not allow
# checking multiple pools.
#
# Combines status and performace data into one output.
#
# @author Tomas Henzl (tomas.henzl@webglobe.com)
#
# changelog:
#   2022/10/11 - created
#

function pretty_print() {
	# $1:         delimiter
	# $2, $3 ...: data

	args=( "${@}" )
	delim="${args[0]}"

	out=$(printf "%s${delim}" "${args[@]:1}")

	echo -n "${out%$delim*}"			# (remove last separator)
}

args=( "${@}" )

#
# parse args for check_zfs.py to separate args from pools
#
for (( x=0; x < ${#args[@]}; x++ )); do
	case "${args[$x]}" in
		--nosudo)   cmd_params+=( "${args[$x]}" );;
		--capacity) cmd_params+=( "${args[@]:$x:3}" ); (( x+=2 ));;
		*)          pools+=( "${args[$x]}" )
	esac
done

#
# run check_zfs.py on each pool with all args
#
exit_status_worst=0
for (( x=0; x < ${#pools[@]}; x++ )); do
	cmd=( "$(dirname "$0")/check_zfs.py" "${cmd_params[@]}" "${pools[$x]}" )

	out=( $("${cmd[@]}") )
	exit_status[$x]=$?

	# track worst exit status
	(( ${exit_status[$x]} > exit_status_worst )) && exit_status_worst="${exit_status[$x]}"


	# parse output data into text and perf_data arrays
	perf_data_toggle[$x]='false'
	for (( i=0; i < ${#out[@]}; i++ )); do
		[[ "${out[$i]}" == '|' ]] && { perf_data_toggle[$x]='true'; continue; }	# separate info from perf_data, see below

		if ${perf_data_toggle[$x]}; then
			perf_data_data[$x]+="${pools[$x]}_${out[$i]} "
		else
			text_data[$x]+="${out[$i]} "
		fi
	done
done

#
# choose what to print, in case of an error, only errors
#
for (( x=0; x < ${#exit_status[@]}; x++ )); do
	perf_final+=( "${perf_data_data[$x]}" )

	# in case of an error, skip non error messages
	if (( exit_status_worst > 0 && ${exit_status[$x]} == 0 )); then
		continue
	else
		text_final+=( "${text_data[$x]}" )
	fi
done

pretty_print '<br>' "${text_final[@]}"
echo " | ${perf_final[@]}"
exit "${exit_status_worst:-0}"
