#!/bin/bash

if ! command -v systemctl; then
	echo -n "Alpine host"
	exit 0
fi

retcode=0
for i in "$@"; do
	active=$(systemctl is-active "$i")
	if [ "$?" -ne 0 ]; then
	        echo -n "$i is $active; "
	        retcode=2
	fi
done

if [ "$retcode" -eq 0 ]; then
	echo -n "all services are active"
fi
echo
exit $retcode