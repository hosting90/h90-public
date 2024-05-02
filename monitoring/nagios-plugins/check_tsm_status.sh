#!/bin/sh

source /etc/profile.d/tableau_server.sh

out=$(tsm status)

echo $out

echo $out | grep 'Status: RUNNING' >/dev/null && exit 0

exit 1

