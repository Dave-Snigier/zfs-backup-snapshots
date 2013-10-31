zfs-backup-snapshots
====================

Mounts the latest snapshot for each filesystem into a directory so it can be backed up by a traditional backup system

```
$ zfs_backup_snapshots help
The following commands are supported:
   cleanup: Unmounts everything from the backup directory
     mount: Mounts the latest snapshot for every ZFS filesystem to the backup directory
mount-root: Mounts the latest snapshot for the root of the current boot environment
 mount-all: Performs cleanup, then mounts all filesystems including root to the backup directory
      help: You're looking at it!
```
