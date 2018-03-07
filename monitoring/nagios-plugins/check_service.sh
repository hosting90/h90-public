#!/bin/bash


ret=$(systemctl is-active "$1")
if [ "$?" -eq 0 ]; then
        echo "$1 is $ret"
        exit 0
else
        echo "$1 is $ret"
        exit 2
fi