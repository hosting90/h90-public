#!/bin/bash

if [ "$1" == "" ]; then
	echo "No ini file."
	exit 1
fi

SCRIPT=`grep -i "script_path" $1 | cut -d "=" -f2`
eval python2 $SCRIPT $@
