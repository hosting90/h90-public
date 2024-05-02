#!/bin/bash

ips=$(wg show | awk '/^  allowed ips:.*\/32/ {print $3}' | awk -F '/' '{ print $1 }')

if [ "$ips" == "" ]; then
  echo "No peers to check."
  exit 3
fi;

rt=0

for ip in $ips; do

  ping -c 1 $ip &> /dev/null
  if [ $? -eq 0 ]; then
    echo "Peer $ip is alive."
  else
    echo "Peer $ip down!"
    rt=1
  fi;

done;

exit $rt
