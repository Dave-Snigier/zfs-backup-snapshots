#!/bin/bash

# This script will mount the latest snapshot for each zfs filesytem currently mounted on the system into the below directory
backupDirectory="/networker"

# requirements
# =============================================
# check for GNU version of find
type -P gfind &>/dev/null || { echo "We require the GNU version of find to be installed and aliased as 'gfind'. Aborting script."; exit 1; }

# check to make sure backupDirectory exists
stat "${backupDirectory}" &>/dev/null
if [[ $? == 1 ]]; then
	echo "The backup directory specified does not exist. Please create and try again: ${backupDirectory}"
	exit 1
fi

# cleanup code
# =============================================

# umounts and cleans up the backup directory
# usage: zfs_backup_cleanup backupDirectory
function zfs_backup_cleanup() {
	# get all filesystems mounted within the backup directory
	fs=( $(cat /etc/mnttab | cut -f2 | grep "${1}") )

	# umount said filesystems
	for i in ${fs[@]}; do
		umount "$i"
	done

	# delete empty directories from within the backup directory
	gfind "${1}" -mindepth 1 -maxdepth 1 -type d -empty -delete
}

# creation code
# =============================================

# gets the name of the newest snapshot given a zfs filesystem
# usage: get_latest_snap filesystem
function zfs_latest_snap() {
		snapshot=$(zfs list -H -t snapshot -o name -S creation -d1 "${1}" | head -1 | cut -d '@' -f 2)
		if [[ -z $snapshot ]]; then
				# if there's no snapshot then let's ignore it
				return 1
		fi
		echo "$snapshot"
}


# gets the path of a snapshot given a zfs filesystem and a snapshot name
# usage zfs_snapshot_mountpoint filesystem snapshot
function zfs_snapshot_mountpoint() {
	# get mountpoint for filesystem
	mountpoint=$(zfs list -H -o mountpoint "${1}")

	# exit if filesystem doesn't exist
	if [[ $? == 1 ]]; then
		return 1
	fi

	# build out path
	path="${mountpoint}/.zfs/snapshot/${2}"

	# check to make sure path exists
	if stat "${path}" &> /dev/null; then
		echo "${path}"
		return 0
	else
		return 1
	fi
}


# =======
# cleanup crap from previous runs
zfs_backup_cleanup "${backupDirectory}"

# work on non-root filesystems
# get list of all non-root zfs filesystems on the box not including the ROOT since that has duplicate mountpoints
filesystems=( $(zfs list -H -o name | egrep -v "^rpool/ROOT.*") )

for fs in "${filesystems[@]}"; do

	# get name of latest snapshot
	snapshot=$(zfs_latest_snap "${fs}")
	
	# if there's no snapshot then let's ignore it
	if [[ $? == 1 ]]; then
		echo "No snapshot exists for ${fs}, it will not be backed up."
		continue
	fi

	sourcepath=$(zfs_snapshot_mountpoint "${fs}" "${snapshot}")
	# if the filesystem is not mounted/path doesn't exist then let's ignore as well
	if [[ $? == 1 ]]; then
		echo "Cannot find snapshot ${snapshot} for ${fs}, perhaps it's not mounted? Anyways, it will not be backed up."
		continue
	fi

	# replace filesystem slashes with underscores for use as the mount directory
	mountpath=${backupDirectory}/$(echo ${fs} | tr '/' '_')

	# mount to backup directory using a bind filesystem
	mkdir "${mountpath}"
	mount -F lofs "${sourcepath}" "${mountpath}"
done
