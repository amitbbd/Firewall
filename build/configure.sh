#!/bin/bash
set -e

### ==============================
### Variable Declarations
### ==============================

# Root filesystem target (adjust if your Makefile uses a different path)
ROOTFS="debian-rootfs"

# Hostname for the OS
HOSTNAME="firewall-os"

# Root password
ROOT_PASSWORD="root1234"

# Regular user details
USER_NAME="admin"
USER_PASSWORD="admin123" 

ESSENTIAL_PACKAGES="systemd systemd-sysv init udev"
NETWORK_PACKAGES="net-tools iproute2 iputils-ping dnsutils network-manager openssh-server"
UTIL_PACKAGES="sudo vim less nano bash-completion locales"
LIVE_PACKAGES="grub-pc linux-image-amd64 live-boot"

echo "deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware" > /etc/apt/sources.list
echo "deb http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware" >> /etc/apt/sources.list
echo "deb http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware" >> /etc/apt/sources.list
#deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware > /etc/apt/sources.list
#deb http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware >> /etc/apt/sources.list
#deb http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware >> /etc/apt/sources.list

# Update package lists
apt update

# Install essential packages
DEBIAN_FRONTEND=noninteractive apt install -y --no-install-recommends \
                $ESSENTIAL_PACKAGES $NETWORK_PACKAGES $UTIL_PACKAGES $LIVE_PACKAGES

# Configure locales
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Set hostname
echo "$HOSTNAME" > /etc/hostname

# Configure hosts file
cat > /etc/hosts << EOF
127.0.0.1   localhost
127.0.1.1   $HOSTNAME
::1         localhost ip6-localhost ip6-loopback
ff02::1     ip6-allnodes
ff02::2     ip6-allrouters
EOF

# Configure networking
cat > /etc/systemd/network/20-wired.network << EOF
[Match]
Name=en*

[Network]
DHCP=yes
EOF

# Set root password
echo "root:$ROOT_PASSWORD" | chpasswd

# Create regular user
useradd -m -s /bin/bash -G sudo $USER_NAME || true
echo "$USER_NAME:$USER_PASSWORD" | chpasswd

# Enable essential services
systemctl enable NetworkManager || true
systemctl enable ssh || true
systemctl enable systemd-networkd || true

# Update initramfs for live boot
update-initramfs -u

# Clean up APT cache
apt clean
rm -rf /var/lib/apt/lists/*

# Remove machine-id (will be generated on boot)
rm -f /etc/machine-id
touch /etc/machine-id
