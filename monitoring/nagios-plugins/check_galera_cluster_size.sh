#!/bin/bash

STATE=`echo "show status like 'wsrep_cluster_size'" | mysql`

echo "$STATE" | grep -q "3"

if [ "$?" -eq 0 ]; then
	echo "OK: Cluster size is 3."
	exit 0
fi

echo "$STATE" | grep -q "2"

if [ "$?" -eq 0 ]; then
        echo "Cluster size is 2."
        exit 1
fi

echo "Cluster size is smaller than 2. Cluster is broken!"
exit 2

