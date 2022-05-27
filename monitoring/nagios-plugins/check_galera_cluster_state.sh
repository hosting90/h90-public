#!/bin/bash

STATE=`echo "show status like 'wsrep_local_state_comment'" | mysql`

echo "$STATE" | grep -q "Synced"

if [ "$?" -eq 0 ]; then
	echo "OK: MySQL node state is SYNCED."
	exit 0
fi

echo "$STATE" | grep -q "Donor"

if [ "$?" -eq 0 ]; then
        echo "MySQL node state is Donor/Desynced."
        exit 1
fi

echo "MySQL node state is Desynced!"
exit 2

