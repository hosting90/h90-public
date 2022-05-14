#!/bin/bash

check_args=""

while [[ $# -gt 0 ]]; do
  case $1 in
    -w)
      check_args="$check_args -w $2"
      shift
      shift
      ;;
    -c)
      check_args="$check_args -c $2"
      shift
      shift
      ;;
    -e)
      check_args="$check_args $2"
      shift
      shift
      ;;
    *)
      echo "Unknwon parameter $1"
      exit 3
      ;;
  esac
done

CHECK_DISK=""
test -f /usr/lib64/nagios/plugins/check_disk && CHECK_DISK=/usr/lib64/nagios/plugins/check_disk
test -f /usr/lib/nagios/plugins/check_disk && CHECK_DISK=/usr/lib/nagios/plugins/check_disk

if [ "$CHECK_DISK" == "" ]; then
  echo "check_disk not found"
  exit 3
fi;

$CHECK_DISK $check_args \
  -X cgroup \
  -X configfs \
  -X devfs \
  -X devtmpfs \
  -X fdescfs \
  -X fuse.gvfs-fuse-daemon \
  -X fuse.gvfsd-fuse \
  -X fuse.sshfs \
  -X mtmfs \
  -X nfs4 \
  -X none \
  -X nsfs \
  -X overlay \
  -X proc \
  -X squashfs \
  -X sysfs \
  -X tmpfs \
  -X tracefs
