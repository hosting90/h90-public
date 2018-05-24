#!/bin/bash

#Takes exclude file as only argiment

if [ "$1" == "" ]; then
	echo "No exclude file."
	exit 2
fi

exitcode=0

for i in $(cat /etc/exim/routelist |awk \{'print $2'\} | sort | uniq); do
	if grep -q -i "$i" "$1"; then
		continue
	fi
	retval=$(/usr/lib64/nagios/plugins/check_tcp -H "$i" -p 25 -t5)
	retcode=$?
	if [ $retcode -ne 0 ]; then
		echo -n "$retval; "
		if [ $exitcode -lt $retcode ]; then
			exitcode=$retcode
		fi
	fi
done
if [ "$exitcode" -eq 0 ]; then
	echo -n "All smtp routes reachable on port 25"
fi
echo
exit $exitcode