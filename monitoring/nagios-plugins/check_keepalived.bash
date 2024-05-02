#!/bin/bash

#
# @author Tomas Henzl (tomas.henzl@webglobe.com)
#
# changelog:
#   2023/12/28 - created
#
#

if ! pidof -q keepalived; then
	echo "CRIT: keepalived not running<br>"
	ret=2
else
	echo "OK: keepalived running<br>"
fi

if [[ -z "$1" ]]; then
	exit "${ret:-0}"
fi

for keepalived_pair in "$@"; do
	hostname_check=${keepalived_pair%%:*}
	ip=${keepalived_pair#*:}

	if [[ -n $(ip addr show to "$ip"/32) ]]; then
		if [[ "$hostname_check" == "$HOSTNAME" ]]; then
			echo "OK: $ip is here<br>"
		else
			echo "CRIT: $ip should be on $hostname_check<br>"
			ret=2
		fi
	else
		if [[ "$hostname_check" == "$HOSTNAME" ]]; then
			echo "CRIT: $ip should be here<br>"
			ret=2
		else
			echo "OK: $ip not here<br>"
		fi
	fi
done

exit "${ret:-0}"
