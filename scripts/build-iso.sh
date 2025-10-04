#!/bin/bash
#
# ISO Building Script - Runs inside chroot

set -euo pipefail

# Configuration
LOG_FILE="/var/log/iso-build.log"
INSTALLER_DIR="/usr/share/firewall-installer"

# Logging
exec > >(tee -a "$LOG_FILE") 2>&1

echo "Starting ISO build configuration..."

# Configure Systemd Services
systemctl enable ssh
systemctl enable systemd-networkd
systemctl enable systemd-resolved
systemctl mask systemd-timesyncd  # We'll use chrony instead

# Install and configure chrony
apt-get install -y chrony
systemctl enable chrony

# Configure Network
cat > /etc/systemd/network/80-ethernet.network << 'EOF'
[Match]
Name=eth* en*

[Network]
DHCP=yes
IPv6PrivacyExtensions=yes
EOF

# Create Live System Configuration
cat > /etc/systemd/system/live-setup.service << 'EOF'
[Unit]
Description=Live System Setup
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/share/firewall-installer/installer/main-installer.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Make installer scripts executable
chmod +x "$INSTALLER_DIR"/installer/*.sh
chmod +x "$INSTALLER_DIR"/post-install/*.sh

# Create Live User
useradd -m -s /bin/bash liveuser
echo 'liveuser:live' | chpasswd
usermod -aG sudo liveuser

# Set root password
echo 'root:firewall' | chpasswd

# Configure sudoers
echo 'liveuser ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers.d/liveuser

# Update initramfs
echo "Updating initramfs..."
update-initramfs -c -k all

# Clean package cache to reduce ISO size
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

echo "ISO build configuration completed successfully!"
