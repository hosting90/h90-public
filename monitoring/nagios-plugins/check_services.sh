#!/bin/bash

if ! command -v systemctl; then
	echo -n "Alpine host"
	exit 0
fi

retcode=0
running_in_chroot=0
for i in "$@"; do
	active=$(systemctl is-active "$i" 2>&1)
	if [[ "$active" == *"Running in chroot"* ]]; then
		running_in_chroot=1
		active=$(pgrep "$i")
	fi
	if [ "$?" -ne 0 ]; then
		if [ "$running_in_chroot" -eq 1 ]; then
			active="dead"
		fi
        echo -n "$i is $active; "
        retcode=2
	fi
done

if [ "$retcode" -eq 0 ]; then
	echo -n "all services are active"
fi
echo
exit $retcode