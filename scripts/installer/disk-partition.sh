#!/bin/bash
#
# Disk Partitioning Script

partition_disk() {
    local disk="$1"
    
    log "Partitioning disk: $disk"
    
    # Create partition table
    parted "$disk" mklabel gpt
    
    # Create partitions
    # 1GB EFI, 2GB swap, rest for root
    parted "$disk" mkpart primary fat32 1MiB 1GiB
    parted "$disk" set 1 esp on
    parted "$disk" mkpart primary linux-swap 1GiB 3GiB
    parted "$disk" mkpart primary ext4 3GiB 100%
    
    # Format partitions
    mkfs.fat -F32 "${disk}1"
    mkswap "${disk}2"
    mkfs.ext4 -F "${disk}3"
    
    # Mount partitions
    mount "${disk}3" /mnt
    mkdir -p /mnt/boot/efi
    mount "${disk}1" /mnt/boot/efi
    swapon "${disk}2"
}

install_system() {
    log "Installing system to target..."
    
    # Copy live system to target
    rsync -a --exclude=/proc --exclude=/sys --exclude=/dev --exclude=/tmp --exclude=/run / /mnt/
    
    # Create essential directories
    mkdir -p /mnt/{proc,sys,dev,tmp,run}
}

install_bootloader() {
    local disk="$1"
    
    log "Insting bootloader..."
    
    chroot /mnt grub-install "$disk"
    chroot /mnt update-grub
}
