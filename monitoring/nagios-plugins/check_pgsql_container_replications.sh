#!/usr/bin/env bash

# Check if the PostgreSQL version is provided as an argument
if [ -z "$1" ]; then
  echo "Usage: $0 <postgresql_version>"
  exit 1
fi

PG_VERSION=$1

# Nagios exit codes
STATE_OK=0
STATE_WARNING=1
STATE_CRITICAL=2
STATE_UNKNOWN=3

# Command to get the replication status
REPLICATION_STATUS=$(sudo docker exec -u postgres -i c-postgres$PG_VERSION psql -A -t -c "SELECT status FROM pg_stat_wal_receiver;")

# Check the replication status and set the appropriate exit code and message
case "$REPLICATION_STATUS" in
    "streaming")
        echo "OK: Replication status is streaming."
        exit $STATE_OK
        ;;
    "catchup")
        echo "WARNING: Replication status is catchup."
        exit $STATE_WARNING
        ;;
    "syncing")
        echo "CRITICAL: Replication status is syncing."
        exit $STATE_CRITICAL
        ;;
    *)
        echo "UNKNOWN: Replication status is $REPLICATION_STATUS."
        exit $STATE_UNKNOWN
        ;;
esac
