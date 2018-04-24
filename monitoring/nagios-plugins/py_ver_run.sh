#!/bin/bash

if [ "$1" == "" ]; then
	echo "No ini file."
	exit 1
fi

if grep -q -i "release 7" /etc/redhat-release; then
	PYTHON=`grep -i "centos7" $1 | egrep -o "python[0-9\.]+"`
elif grep -q -i "release 6" /etc/redhat-release; then
	PYTHON=`grep -i "centos6" $1 | egrep -o "python[0-9\.]+"`
elif grep -q -i "release 5" /etc/redhat-release; then
	PYTHON=`grep -i "centos5" $1 | egrep -o "python[0-9\.]+"`
else
	echo "Error."
	exit 1
fi

SCRIPT=`grep -i "script_path" $1 | cut -d "=" -f2`
eval $PYTHON $SCRIPT $@
