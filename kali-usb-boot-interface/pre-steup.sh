#!/bin/bash

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

list_drives_lsblk() {
  echo "Listing drives and partitions using lsblk:"
  lsblk -o NAME,SIZE,TYPE,MOUNTPOINT
  echo
}

list_drives_fdisk() {
  echo "Listing drives using fdisk:"
  fdisk -l | grep -E 'Disk /dev/sd|Disk /dev/nvme|^Partition|^Device' || echo "No drives found"
  echo
}

list_drives_lsblk
list_drives_fdisk