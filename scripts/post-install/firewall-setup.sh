#!/bin/bash
#
# Firewall Setup Script

configure_firewall() {
    log "Configuring firewall..."
    
    # Enable and start firewalld
    systemctl enable firewalld
    systemctl start firewalld
    
    # Configure default zone
    firewall-cmd --set-default-zone=drop
    firewall-cmd --permanent --set-default-zone=drop
    
    # Allow SSH
    firewall-cmd --add-service=ssh --permanent
    firewall-cmd --reload
    
    # Configure nftables backend
    cat > /etc/firewalld/firewalld.conf << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<config>
  <default-zone>drop</default-zone>
  <minimal-mark>100</minimal-mark>
  <cleanup-on-exit>yes</cleanup-on-exit>
  <lockdown>no</lockdown>
  <ipv6>yes</ipv6>
  <log-denied>all</log-denied>
</config>
EOF
}
