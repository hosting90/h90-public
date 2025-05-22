#!/bin/bash

#
# @author Tomas Henzl (tomas.henzl@webglobe.com)
#
# changelog:
#   2025/05/19 - exclude '/run/docker/*'
#   2024/01/22 - created
#
#

[[ -f /usr/lib64/nagios/plugins/check_disk ]] && CHECK_DISK=/usr/lib64/nagios/plugins/check_disk
[[ -f /usr/lib/nagios/plugins/check_disk   ]] && CHECK_DISK=/usr/lib/nagios/plugins/check_disk

[[ -z "$CHECK_DISK" ]] && echo 'check_disk not found' && exit 3

# search for path excludes (-I) at the bottom
args=(
  -u MB		# units
  -e		# show only errors
  -L		# only check local filesystems
  -X cgroup
  -X configfs
  -X devfs
  -X devtmpfs
  -X fdescfs
  -X fuse.gvfs-fuse-daemon
  -X fuse.gvfsd-fuse
  -X fuse.sshfs
  -X mtmfs
  -X nfs4
  -X none
  -X nsfs
  -X overlay
  -X proc
  -X squashfs
  -X sysfs
  -X tmpfs
  -X tracefs
)

[[ -z "$1" ]] && args+=(-w 10% -c 5% -W 10% -K 5%)

for arg in "$@"; do
	IFS=: read -r disk warn crit warn_i crit_i <<< "$arg"

	warn="${warn:-10%}"
	crit="${crit:-5%}"

	warn_i="${warn_i:-10%}"
	crit_i="${crit_i:-5%}"

	[[ "$DEBUG" ]] && echo "$disk $warn $crit $warn_i $crit_i"

	[[ "$disk" != 'all' ]] && args+=(-C)

	args+=(
		-w "$warn"
		-c "$crit"
		-W "$warn_i"
		-K "$crit_i"
	)

	[[ "$disk" != 'all' ]] && args+=(-p "$disk")

done

test -d /boot/efi && {
  args+=(
    -C -w 50 -c 20 -W 10% -K 5% -p /boot/efi
  )
}

# some hosts without any disk specified (and no /boot/efi) errors with:
# "Paths need to be selected before using -i/-I. Use -A to select all paths explicitly"
# this fixes it:
args+=( -A )

# path excludes have to be here, nagios check requires some paths first
args+=(
	-I '/run/docker/*'
)

[[ "$DEBUG" ]] && set -x
$CHECK_DISK "${args[@]}"
