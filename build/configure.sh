#!/bin/bash
# Minimal Firewall System Configuration Script
# This script runs inside chroot to configure the minimal system

set -e

echo "========================================="
echo "  Configuring Minimal Firewall System"
echo "========================================="

### Load configuration variables
if [ -f /tmp/config-vars.sh ]; then
    source /tmp/config-vars.sh
else
    # Default values if not provided
    HOSTNAME="firewall"
    ROOT_PASSWORD="root1234"
fi

### Configure APT sources - MINIMAL repositories only
echo "→ Configuring minimal APT sources..."
cat > /etc/apt/sources.list << 'EOF'
deb http://deb.debian.org/debian bookworm main
deb http://security.debian.org/debian-security bookworm-security main
EOF

# Update package lists
echo "→ Updating package lists..."
apt update

### Install ONLY essential firewall packages
echo "→ Installing minimal essential packages..."
echo "  (This keeps the system as small as possible)"

DEBIAN_FRONTEND=noninteractive apt install -y --no-install-recommends \
    systemd-sysv \
    udev \
    kmod \
    iptables \
    iproute2 \
    iputils-ping \
    openssh-server \
    nano \
    locales

echo "✓ Minimal packages installed"

### Configure locale (minimal - only en_US.UTF-8)
echo "→ Configuring minimal locale..."
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/default/locale

### Set hostname
echo "→ Setting hostname to: $HOSTNAME"
echo "$HOSTNAME" > /etc/hostname

### Configure hosts file
echo "→ Configuring hosts file..."
cat > /etc/hosts << EOF
127.0.0.1   localhost
127.0.1.1   $HOSTNAME
::1         localhost ip6-localhost ip6-loopback
ff02::1     ip6-allnodes
ff02::2     ip6-allrouters
EOF

### Configure minimal networking
echo "→ Configuring minimal networking (DHCP)..."
mkdir -p /etc/network
cat > /etc/network/interfaces << 'EOF'
# Loopback interface
auto lo
iface lo inet loopback

# Primary ethernet - DHCP
auto eth0
iface eth0 inet dhcp

# Alternative interface names
auto enp0s3
iface enp0s3 inet dhcp

auto ens3
iface ens3 inet dhcp
EOF

### Set root password
echo "→ Setting root password..."
echo "root:$ROOT_PASSWORD" | chpasswd

### Enable SSH service
echo "→ Enabling SSH service..."
systemctl enable ssh 2>/dev/null || true

### Configure basic firewall rules
echo "→ Configuring basic firewall rules..."
mkdir -p /etc/iptables

cat > /etc/iptables/rules.v4 << 'EOF'
*filter
# Default policies - DROP everything except OUTPUT
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]

# Allow loopback
-A INPUT -i lo -j ACCEPT

# Allow established and related connections
-A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

# Allow SSH (port 22)
-A INPUT -p tcp --dport 22 -m conntrack --ctstate NEW -j ACCEPT

# Allow ping/ICMP
-A INPUT -p icmp --icmp-type echo-request -j ACCEPT

# Log dropped packets (optional, comment out if not needed)
# -A INPUT -m limit --limit 5/min -j LOG --log-prefix "iptables INPUT denied: " --log-level 7

COMMIT
EOF

echo "✓ Basic firewall rules configured"

### Create iptables restore service
echo "→ Creating iptables restore service..."
cat > /etc/systemd/system/iptables-restore.service << 'EOF'
[Unit]
Description=Restore iptables firewall rules
Before=network-pre.target
Wants=network-pre.target

[Service]
Type=oneshot
ExecStart=/sbin/iptables-restore /etc/iptables/rules.v4
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl enable iptables-restore 2>/dev/null || true

### Enable IP forwarding for firewall/router functionality
echo "→ Enabling IP forwarding..."
cat > /etc/sysctl.d/99-firewall.conf << 'EOF'
# Enable IP forwarding for firewall/router
net.ipv4.ip_forward=1
net.ipv4.conf.all.forwarding=1
net.ipv6.conf.all.forwarding=1

# Security hardening
net.ipv4.conf.default.rp_filter=1
net.ipv4.conf.all.rp_filter=1
net.ipv4.tcp_syncookies=1
net.ipv4.conf.all.accept_redirects=0
net.ipv6.conf.all.accept_redirects=0
net.ipv4.conf.all.send_redirects=0
net.ipv4.conf.all.accept_source_route=0
net.ipv6.conf.all.accept_source_route=0
net.ipv4.conf.all.log_martians=1
EOF

### Create disk installer script
echo "→ Creating disk installer script..."
cat > /usr/local/bin/install-to-disk << 'INSTALL_EOF'
#!/bin/bash
# Minimal Firewall Disk Installer
# This script installs the live system to a hard disk

set -e

clear
cat << 'BANNER_EOF'
╔═══════════════════════════════════════════╗
║   Minimal Firewall Disk Installer         ║
╚═══════════════════════════════════════════╝
BANNER_EOF

echo ""
echo "This will install the minimal firewall system to a hard disk."
echo ""

# Check if running in live environment
if [ ! -d /lib/live ]; then
    echo "Warning: This doesn't appear to be a live system."
    echo "Installation may not work correctly."
    echo ""
fi

# Show available disks
echo "Available disks:"
echo "────────────────────────────────────────"
lsblk -d -n -o NAME,SIZE,TYPE,MODEL | grep disk | awk '{print "  /dev/" $1 " - " $2 " - " $4}'
echo ""

# Get target disk
while true; do
    read -p "Enter target disk (e.g., sda, vda, nvme0n1): " DISK_NAME
    DISK="/dev/$DISK_NAME"
    
    if [ -z "$DISK_NAME" ]; then
        echo "Error: No disk specified"
        continue
    fi
    
    if [ ! -b "$DISK" ]; then
        echo "Error: $DISK is not a valid block device"
        continue
    fi
    
    break
done

# Confirm installation
echo ""
echo "═══════════════════════════════════════════"
echo "WARNING: ALL DATA ON $DISK WILL BE ERASED!"
echo "═══════════════════════════════════════════"
echo ""
read -p "Type 'yes' to continue or anything else to cancel: " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Installation cancelled."
    exit 0
fi

echo ""
echo "Starting installation..."
echo ""

# Unmount if already mounted
umount ${DISK}* 2>/dev/null || true

# Partition disk
echo "→ Creating partition table..."
parted -s $DISK mklabel msdos
parted -s $DISK mkpart primary ext4 1MiB 100%
parted -s $DISK set 1 boot on

# Wait for partition to appear
sleep 2
partprobe $DISK 2>/dev/null || true
sleep 1

# Determine partition name
if [[ $DISK == *"nvme"* ]] || [[ $DISK == *"mmcblk"* ]]; then
    PART="${DISK}p1"
else
    PART="${DISK}1"
fi

# Format partition
echo "→ Formatting partition..."
mkfs.ext4 -F -L "FIREWALL_ROOT" $PART

# Mount partition
echo "→ Mounting partition..."
mkdir -p /mnt/target
mount $PART /mnt/target

# Copy system files
echo "→ Installing system files (this may take 2-5 minutes)..."
rsync -a --info=progress2 \
    --exclude=/dev/* \
    --exclude=/proc/* \
    --exclude=/sys/* \
    --exclude=/tmp/* \
    --exclude=/run/* \
    --exclude=/mnt/* \
    --exclude=/media/* \
    --exclude=/lib/live \
    --exclude=/lost+found \
    / /mnt/target/

# Create necessary directories
echo "→ Creating system directories..."
mkdir -p /mnt/target/{dev,proc,sys,tmp,run,mnt,media}
chmod 1777 /mnt/target/tmp

# Mount filesystems for chroot
echo "→ Preparing for bootloader installation..."
mount --bind /dev /mnt/target/dev
mount --bind /proc /mnt/target/proc
mount --bind /sys /mnt/target/sys

# Install GRUB bootloader
echo "→ Installing GRUB bootloader..."
chroot /mnt/target grub-install --target=i386-pc $DISK
chroot /mnt/target update-grub

# Update fstab
echo "→ Configuring fstab..."
UUID=$(blkid -s UUID -o value $PART)
cat > /mnt/target/etc/fstab << FSTAB_EOF
# /etc/fstab: static file system information
UUID=$UUID  /  ext4  errors=remount-ro  0  1
FSTAB_EOF

# Remove live-boot packages
echo "→ Removing live-boot packages..."
chroot /mnt/target apt remove --purge -y live-boot live-boot-initramfs-tools 2>/dev/null || true
chroot /mnt/target apt autoremove -y 2>/dev/null || true

# Update initramfs
echo "→ Updating initramfs..."
chroot /mnt/target update-initramfs -u

# Disable auto-login
echo "→ Disabling auto-login..."
rm -f /mnt/target/etc/systemd/system/getty@tty1.service.d/autologin.conf 2>/dev/null || true
rmdir /mnt/target/etc/systemd/system/getty@tty1.service.d 2>/dev/null || true

# Update bashrc
cat > /mnt/target/root/.bashrc << 'BASHRC_EOF'
# ~/.bashrc

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# Basic aliases
alias ll='ls -lh'
alias la='ls -lAh'

# Show welcome message
cat << 'WELCOME_EOF'
╔══════════════════════════════════════════╗
║   Minimal Firewall System                ║
╚══════════════════════════════════════════╝

Firewall commands:
  iptables -L              View firewall rules
  iptables -A INPUT ...    Add firewall rule
  ip addr                  Show network interfaces
  ip route                 Show routing table

Configuration files:
  /etc/iptables/rules.v4   Firewall rules
  /etc/network/interfaces  Network config
  /etc/sysctl.d/           Kernel parameters

WELCOME_EOF
BASHRC_EOF

# Cleanup chroot mounts
echo "→ Cleaning up..."
umount /mnt/target/dev 2>/dev/null || true
umount /mnt/target/proc 2>/dev/null || true
umount /mnt/target/sys 2>/dev/null || true
umount /mnt/target 2>/dev/null || true

# Final message
echo ""
echo "╔═══════════════════════════════════════════╗"
echo "║   Installation Complete!                  ║"
echo "╚═══════════════════════════════════════════╝"
echo ""
echo "System installed to: $DISK"
echo "Root password: (as configured)"
echo ""
echo "Next steps:"
echo "  1. Remove the installation media"
echo "  2. Reboot the system"
echo "  3. Login as root"
echo "  4. Configure your firewall rules"
echo ""
read -p "Reboot now? (yes/no): " REBOOT
if [ "$REBOOT" = "yes" ]; then
    reboot
fi
INSTALL_EOF

chmod +x /usr/local/bin/install-to-disk
echo "✓ Disk installer script created"

### Configure auto-login for live system
echo "→ Configuring auto-login for installer..."
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf << 'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I $TERM
EOF

### Create welcome message for live boot
echo "→ Creating welcome message..."
cat > /root/.bashrc << 'BASHRC_EOF'
# ~/.bashrc for Minimal Firewall Installer

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# Check if this is the installer environment
if [ -f /usr/local/bin/install-to-disk ]; then
    clear
    cat << 'WELCOME_EOF'
╔═══════════════════════════════════════════╗
║   Minimal Firewall Installer              ║
╚═══════════════════════════════════════════╝

Welcome to the Minimal Firewall Installer!

This is a live system running from ISO/USB.
To install to hard disk, run:

    install-to-disk

Manual installation steps:
  1. Partition disk:     fdisk /dev/sda
  2. Format partition:   mkfs.ext4 /dev/sda1
  3. Mount:             mount /dev/sda1 /mnt
  4. Copy system:       rsync -a / /mnt/
  5. Install GRUB:      grub-install /dev/sda
  6. Update fstab:      nano /mnt/etc/fstab

Network commands:
  ip addr               Show network interfaces
  ip link set eth0 up   Bring interface up
  dhclient eth0         Get DHCP address

WELCOME_EOF
else
    # Installed system welcome
    cat << 'WELCOME_EOF'
╔══════════════════════════════════════════╗
║   Minimal Firewall System                ║
╚══════════════════════════════════════════╝

Firewall Management:
  iptables -L               View current rules
  iptables -A INPUT ...     Add rule
  iptables-save > file      Save rules
  iptables-restore < file   Restore rules
  
  Rules file: /etc/iptables/rules.v4
  (Edit this file and reboot to apply)

Network Configuration:
  ip addr                   Show interfaces
  ip link set eth0 up       Enable interface
  ip route                  Show routes
  nano /etc/network/interfaces

System Information:
  df -h                     Disk usage
  free -h                   Memory usage
  systemctl status          Service status

WELCOME_EOF
fi

# Basic aliases
alias ll='ls -lh'
alias la='ls -lAh'
alias fw='iptables -L -n -v'
alias fwsave='iptables-save > /etc/iptables/rules.v4'
alias fwrestore='iptables-restore < /etc/iptables/rules.v4'
BASHRC_EOF

### Create system information file
echo "→ Creating system info..."
cat > /etc/issue << 'EOF'
Minimal Firewall System \n \l

EOF

cat > /etc/motd << 'EOF'

╔══════════════════════════════════════════╗
║   Minimal Firewall System                ║
╚══════════════════════════════════════════╝

System: Debian Bookworm (Minimal)
Purpose: Firewall / Router Appliance

EOF

### Clean up APT cache and unnecessary files
echo "→ Cleaning up to minimize size..."
apt clean
rm -rf /var/lib/apt/lists/*
rm -rf /tmp/*
rm -rf /var/tmp/*
rm -rf /var/log/*.log
rm -rf /var/log/*.gz

### Remove machine-id (will be generated on first boot)
echo "→ Removing machine-id..."
rm -f /etc/machine-id
touch /etc/machine-id

### Update initramfs for live-boot
echo "→ Updating initramfs..."
update-initramfs -u

### Show installed package count
echo ""
echo "========================================="
echo "  Configuration Complete!"
echo "========================================="
PACKAGE_COUNT=$(dpkg -l | grep "^ii" | wc -l)
echo "Total packages installed: $PACKAGE_COUNT"
echo "Hostname: $HOSTNAME"
echo "Root password: $ROOT_PASSWORD"
echo ""
echo "Minimal system configured successfully!"
echo ""

# List essential packages
echo "Essential packages installed:"
dpkg -l | grep "^ii" | awk '{print "  - " $2}' | head -15
echo "  ..."
echo ""
