#!/bin/bash

#
# Check dmesg output for common errors
#

CFGFILE='check_dmesg.cfg'
REGEX='Hardware Error|I/O error|hard resetting link|DRDY ERR|temperature above threshold|segfault|MEMORY ERROR|dropping packet|This should not happen!! Data will be lost|task abort|No reference found at driver|connect authorization failure'

[[ -f "$(dirname $0)/$CFGFILE" ]] && source "$(dirname $0)/$CFGFILE"

if [ -z "$1" ]; then
  output=$(dmesg -T -l err,crit,alert,emerg 2>/dev/null || dmesg)
else
  output=$(journalctl -kS -"$1hour")
fi

if [ $? -ne 0 ]; then
  exit 3;
fi;

if [[ -n "$output" ]]; then
  filtered_output=$(grep -E -i "$REGEX" <<< "$output")

  if [[ -n "$filtered_output" ]]; then
    echo -n 'ERROR - The dmesg output contain error(s):<br>'
    echo "$filtered_output" | cut -c1-100 | sed 's|$|<br>|g' | tail -n10 | tr -d '\n'
    exit 2
  fi
fi

echo "OK - The dmesg command output doesn't seem contain error."
exit 0

