#!/bin/bash

retcode=0
for i in "$@"; do
	active=$(systemctl is-active "$i")
	if [ "$?" -eq 0 ]; then
	        echo -n "$i is $active; "
	else
	        echo -n "$i is $active; "
	        retcode=2
	fi
done
echo
exit $retcode