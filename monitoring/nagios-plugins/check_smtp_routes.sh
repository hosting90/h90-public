#!/bin/bash

exitcode=0

for i in $(cat /etc/exim/routelist |awk {'print $2'} | sort | uniq); do
	retval=$(/usr/lib64/nagios/plugins/check_tcp -H "$i" -p 25 -t1)
	retcode=$?
	if [ $retcode -ne 0 ]; then
		echo -n "$retval; "
		if [ $exitcode -lt $retcode ]; then
			exitcode=$retcode
		fi
	fi
done
echo

exit $exitcode