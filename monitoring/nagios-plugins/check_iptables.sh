#!/bin/bash

ERRORS=$( sudo /sbin/iptables -L -n |grep INPUT |grep ACCEPT )
if [ "$ERRORS" = "" ]; then
	echo "OK: iptables INPUT policy - DROP"
	exit 0
else 
	echo "WARNING: iptables INPUT policy - ACCEPT"
	exit 2
fi
