#!/bin/bash
#
# Chroot Configuration Script

set -euo pipefail

echo "Starting chroot configuration..."

# Mount essential filesystems
mount -t proc proc /proc
mount -t sysfs sys /sys
mount -t devtmpfs dev /dev
mount -t devpts devpts /dev/pts

# Configure APT
apt-get update

# Install packages from list
if [ -f /tmp/packages.list ]; then
    xargs -a /tmp/packages.list apt-get install -y --no-install-recommends
fi

# Install additional essential packages
apt-get install -y \
    live-boot \
    live-config \
    live-tools \
    systemd-container

# Clean up
apt-get autoremove -y
apt-get clean

# Unmount filesystems
umount /dev/pts
umount /dev
umount /sys
umount /proc

echo "Chroot configuration completed!"
