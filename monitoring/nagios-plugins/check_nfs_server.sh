#!/bin/bash

OK=0
WARNING=1
CRITICAL=2
UNKNOWN=0

for bin in systemctl rpcinfo exportfs; do
  if ! command -v $bin >/dev/null 2>&1; then
    echo "UNKNOWN: command not found '$bin'"
    exit $UNKNOWN
  fi
done

if ! systemctl is-active --quiet rpcbind; then
  echo "CRITICAL: rpcbind not running"
  exit $CRITICAL
fi

if ! systemctl is-active --quiet nfs-server; then
  echo "CRITICAL: nfs-server not running"
  exit $CRITICAL
fi

MISSING_SERVICES=()

REQUIRED_SERVICES=("nfs" "mountd")

for service in "${REQUIRED_SERVICES[@]}"; do
  if ! rpcinfo -p localhost | grep -qw "$service"; then
    MISSING_SERVICES+=("$service")
  fi
done

if [[ ${#MISSING_SERVICES[@]} -gt 0 ]]; then
  echo "CRITICAL: chybí RPC služby: ${MISSING_SERVICES[*]}"
  exit $CRITICAL
fi

echo "OK"
exit $OK

