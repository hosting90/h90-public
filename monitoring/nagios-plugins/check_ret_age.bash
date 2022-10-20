#!/bin/bash

#
# Checks file containing return code + it's age
# Accepts pairs: /file_to_check:max_age_in_hours
#
# @author Tomas Henzl (tomas.henzl@webglobe.com)
#
# changelog:
#   2022/10/20 - created
#

function pretty_print() {
	# $1:         delimiter
	# $2, $3 ...: data

	args=( "${@}" )
	delim="${args[0]}"

	out=$(printf "%s${delim}" "${args[@]:1}")

	echo -n "${out%$delim*}"			# (remove last separator)
}

function die() { echo "$1" 1>&2; exit "${2:-1}"; }

for file_age in "$@"; do
    IFS=: read file max_age <<< "$file_age"

	max_age_seconds=$(( max_age * 60 * 60 ))

	# Error conditions
	if [[ ! -f "$file" ]]; then
		ret=2
		msg_status='CRITICAL'
		msg_info_err+=( "File not pressent or readable: $file" )
		continue
	fi

	if ! file_age=$(stat -c%Y "$file"); then
		ret=2
		msg_status='CRITICAL'
		msg_info_err+=( "Stat failed: $file" )
		continue
	fi

	if ! file_ret=$(< "$file"); then
		ret=2
		msg_status='CRITICAL'
		msg_info_err+=( "Can't read file: $file" )
		continue
	fi

	if [[ "$file_ret" != 0 ]]; then
		ret=2
		msg_status='CRITICAL'
		msg_info_err+=( "File does not contain 0: $file" )
		continue
	fi

	now=$(date +%s)

	if (( (now - file_age) > max_age_seconds )); then
		ret=2
		msg_status='CRITICAL'
		msg_info_err+=( "$file is older: $max_age hours" )
		continue
	fi

	msg_info_ok+=( "$file contains 0 and is younger $max_age hours" )

done

[[ -n "$msg_status" ]] && die "${msg_status}: $(pretty_print "<BR>, " "${msg_info_err[@]}")" "$ret"

die "OK: $(pretty_print "<BR>, " "${msg_info_ok[@]}")" 0
