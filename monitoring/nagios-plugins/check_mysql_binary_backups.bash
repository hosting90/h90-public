#!/bin/bash

#
# @author Tomas Henzl (tomas.henzl@webglobe.com)
#
# changelog:
#   2022/09/16 - created
#   2022/09/20 - fix: running backup no longer triggers error
#

ITALIC=$'\e[3m'
     R=$'\e[0m'

USAGE="Checks ${ITALIC}age${R} of binary backups in ${ITALIC}directory${R}

Example usage:

	$(basename "$0")
	(uses default /home/backupSQLbinary:24)

	$(basename "$0") '/some/directory/backups:11' '/some/other/backups:6'
	checks multiple directories with age, age is in hours
"

function die() { echo "$1"; exit "${2:-1}"; }

pidof -xq mariadb-backup xtrabackup && running=1		# we'll use that later

if [[ "$1" == '-h' || "$1" == '--help' ]]; then
	die "$USAGE" 0
fi

if [[ -z "$1" ]]; then
	to_check=( '/home/backupSQLbinary:24' )
else
	to_check=( "$@" )
fi

for item in "${to_check[@]}"; do
	IFS=: read path age <<< "$item"
	backups=$(find "$path"/* -mindepth 1 -maxdepth 1 -type f -name 'xtrabackup_info*' -mmin -"$(( age * 60 ))" 2> /dev/null)

	# check backup dirs
	if [[ -z "$backups" ]]; then
		msg_preffix='ERROR:'
		msg_fail+="No backup younger $age hours found in: $path; "
		[[ "$running" ]] && msg_fail+="Backup is now running; "
		ret='2'
	else
		msg_ok+="$path contains backup(s) younger $age hours; "
	fi

	# check backup logs
	log=$(find "$path" -mindepth 1 -maxdepth 1 -type f -name '*.log' -mmin -$(( age * 60 )) -printf "%T@\t%p\n" 2> /dev/null | sort -nr | head -n1 | cut -f2-)

	if [[ -z "$log" ]]; then
		msg_preffix='ERROR:'
		msg_fail+="No backup log younger $age hours found in $path; "
		[[ "$running" ]] && msg_fail+="Backup is now running; "
		ret='2'
	elif [[ "$running" ]]; then
		msg_ok+="Backup is now running; "
	elif ! grep -Fq 'completed OK!' "$log"; then
		msg_preffix='ERROR:'
		msg_fail+="Last backup log does not contain OK"
		ret='2'
	fi
done

# show only errors in case of error
if [[ -n "$ret" ]]; then
	msg="$msg_fail"
else
	msg="$msg_ok"
fi

die "${msg_preffix:-OK:} $(sed 's|; $||g' <<< "$msg")" "${ret:-0}"
