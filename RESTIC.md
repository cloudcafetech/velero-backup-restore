# Restic 

## Installation

```
yum install yum-plugin-copr
yum copr enable copart/restic
yum install restic
```

## Configure restic

```
export RESTIC_REPOSITORY=s3:http://<minio-host-ip>:9000/local-backups/<PATH OF CONFIG FILE>
export RESTIC_PASSWORD=IgBvE3YPyRn6oS8
export AWS_ACCESS_KEY_ID=admin
export AWS_SECRET_ACCESS_KEY=bappa2675
```

## Listing snapshot

```restic snapshots```

## Restore snapshot
create a directory (/restore)

```restic restore <restic-snap-id> --target /restore```

## Access and restore single files from a restic volume backup
https://docs.syseleven.de/metakube/en/tutorials/create-backup-and-restore#access-and-restore-single-files-from-a-restic-volume-backup

https://github.com/restic/restic

