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


# functions
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

# mounts latest snapshot in directory
# usage: mount_latest_snap filesystem backupdirectory
function mount_latest_snap() {
	backupDirectory="${2}"
	fs="${1}"

	# get name of latest snapshot
	snapshot=$(zfs_latest_snap "${fs}")
	
	# if there's no snapshot then let's ignore it
	if [[ $? == 1 ]]; then
		echo "No snapshot exists for ${fs}, it will not be backed up."
		return 1
	fi

	sourcepath=$(zfs_snapshot_mountpoint "${fs}" "${snapshot}")
	# if the filesystem is not mounted/path doesn't exist then let's ignore as well
	if [[ $? == 1 ]]; then
		echo "Cannot find snapshot ${snapshot} for ${fs}, perhaps it's not mounted? Anyways, it will not be backed up."
		return 1
	fi

	# replace filesystem slashes with underscores for use as the mount directory
	mountpath=${backupDirectory}/$(echo ${fs} | tr '/' '_')

	# mount to backup directory using a bind filesystem
	mkdir "${mountpath}"
	mount -F lofs "${sourcepath}" "${mountpath}"
	return 0
}


function usage() {
	echo <<-EOF
	The following commands are supported:
	   cleanup: Unmounts everything from the backup directory
	     mount: Mounts the latest snapshot for every ZFS filesystem to the backup directory
	mount-root: Mounts the latest snapshot for the root of the current boot environment
	 mount-all: Performs cleanup, then mounts all filesystems including root to the backup directory
	      help: You're looking at it!
	EOF
	exit 0
}

function cleanup() {
	zfs_backup_cleanup "${backupDirectory}"
	exit 0
}


function mount() {
	# get list of all non-root zfs filesystems on the box not including the ROOT since that has duplicate mountpoints
	filesystems=( $(zfs list -H -o name | egrep -v "^rpool/ROOT.*") )

	for fs in "${filesystems[@]}"; do
		mount_latest_snap "${fs}" "${backupDirectory}"
	done
	return 0
}

function mount-root() {
	# get current root environment filesystem
	rootfs="rpool/ROOT/$(beadm list | perl -nle 'print "$1" if /(solaris.*?)\s+N.*/')"

	mount_latest_snap "${rootfs}" "${backupDirectory}"
	return $?
}

function mount-all() {
	errFlag=false;
	# cleanup crap from previous runs
	cleanup
	if [[ $? != 0 ]]; then
		errFlag=true;
	fi
	mount-root
	if [[ $? != 0 ]]; then
		errFlag=true;
	fi
	mount
	if [[ $? != 0 ]]; then
		errFlag=true;
	fi
	exit ${errFlag}
}

# ==========================================
# arguments parsing

if [[ $1 == "cleanup" ]]; then
	cleanup
elif [[ $1 == "mount" ]]; then
	mount
elif [[ $1 == "mount-root" ]]; then
	mount-root
elif [[ $1 == "mount-all" ]]; then
	mount-all
elif [[ $1 == "help" ]]; then
	usage
else
	echo "missing command"
	echo "For more info, run: zfs_backup_snapshots help"
	exit 1
fi

