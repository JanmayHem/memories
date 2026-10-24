#!/usr/bin/env bash
# Mount the Oracle block volume that holds photos and the database at /srv/photos.
#
# Attach the volume in the OCI console first (Paravirtualized, with
# "Use consistent device paths" so it appears as /dev/oracleoci/oraclevdb).
#
#   sudo ./mount-data-volume.sh                 mount an existing filesystem
#   sudo ./mount-data-volume.sh --format        first time only: create ext4
#   sudo DEVICE=/dev/sdb ./mount-data-volume.sh other device path
#
# It never formats a device that already has a filesystem.
set -euo pipefail

DEVICE="${DEVICE:-/dev/oracleoci/oraclevdb}"
MOUNT_POINT=/srv/photos
LABEL=memories-data

die() { echo "mount-data-volume: $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "run with sudo"
[[ -b "$DEVICE" ]] || die "$DEVICE is not a block device. Is the volume attached?"

fstype=$(blkid -o value -s TYPE "$DEVICE" || true)
if [[ -z "$fstype" ]]; then
  [[ "${1:-}" == "--format" ]] || die "$DEVICE has no filesystem. Re-run with --format to create one."
  echo "Creating ext4 on $DEVICE"
  mkfs.ext4 -L "$LABEL" "$DEVICE"
elif [[ "${1:-}" == "--format" ]]; then
  die "$DEVICE already has a $fstype filesystem. Refusing to format."
fi

uuid=$(blkid -o value -s UUID "$DEVICE")
[[ -n "$uuid" ]] || die "could not read UUID of $DEVICE"

mkdir -p "$MOUNT_POINT"
if ! grep -q "UUID=$uuid" /etc/fstab; then
  # _netdev,nofail: Oracle's guidance for block volumes, so a missing volume
  # does not stop the VM from booting (SSH still works to fix it).
  echo "UUID=$uuid $MOUNT_POINT ext4 defaults,_netdev,nofail 0 2" >> /etc/fstab
  systemctl daemon-reload
fi

mountpoint -q "$MOUNT_POINT" || mount "$MOUNT_POINT"
df -h "$MOUNT_POINT"
