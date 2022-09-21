#!/bin/bash

#
# Checks if directory is mounted, see USAGE
#
# @author Tomas Henzl (tomas.henzl@webglobe.com)
#
# changelog:
#   2022/09/21 - created
#

USAGE="$(basename $0) /mnt /mnt2 /mnt3 ..."

function die() { echo "$1"; exit "${2:-1}"; }

if [[ -z "$1" || "$1" == '-h' || "$1" == '--help' ]]; then
	die "$USAGE" 3
fi

parameters=("$@")

for mount in ${parameters[@]}; do
	if ! mountpoint -q "$mount"; then
		msg_preffix='ERROR:'
		msg_fail+="$mount not mounted; "
		ret=2
	else
		msg_ok+="$mount is mounted; "
	fi
done

# show only errors in case of error
if [[ -n "$ret" ]]; then
	msg="$msg_fail"
else
	msg="$msg_ok"
fi

die "${msg_preffix:-OK:} $(sed 's|; $||g' <<< "$msg")" "${ret:-0}"
