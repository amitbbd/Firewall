# Debian Minimal OS Builder Makefile
# Build a minimal Debian-based OS from scratch using debootstrap

# Configuration Variables
ARCH := amd64
RELEASE := bookworm
MIRROR := http://deb.debian.org/debian/
VARIANT := minbase
ISO_NAME := debian-minimal.iso
ISO_LABEL := DEBIAN_CUSTOM
WORK_DIR := build
ROOTFS_DIR := $(WORK_DIR)/rootfs
ISO_DIR := $(WORK_DIR)/iso
SQUASHFS_FILE := $(ISO_DIR)/live/filesystem.squashfs

# Package lists
ESSENTIAL_PACKAGES := systemd systemd-sysv linux-image-amd64 grub2-common grub-pc
NETWORK_PACKAGES := network-manager openssh-server net-tools iproute2 iputils-ping
UTIL_PACKAGES := nano sudo locales console-setup keyboard-configuration
LIVE_PACKAGES := live-boot live-boot-initramfs-tools

# User configuration
ROOT_PASSWORD := changeme
USER_NAME := user
USER_PASSWORD := changeme
HOSTNAME := debian-minimal

# Colors for output
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m # No Color

# Check if running as root
SUDO := $(shell [ $$(id -u) -eq 0 ] && echo "" || echo "sudo")

.PHONY: all clean deps rootfs configure-rootfs squashfs iso test help

# Default target
all: iso
        @echo -e "$(GREEN)✓ Build complete! ISO created: $(ISO_NAME)$(NC)"

# Help target
help:
        @echo "Debian Minimal OS Builder"
        @echo "========================="
        @echo "Available targets:"
        @echo "  make all          - Build complete ISO (default)"
        @echo "  make deps         - Install required dependencies"
        @echo "  make rootfs       - Create base root filesystem"
        @echo "  make configure    - Configure the root filesystem"
        @echo "  make squashfs     - Create squashfs filesystem"
        @echo "  make iso          - Create bootable ISO"
        @echo "  make test         - Test ISO with QEMU"
        @echo "  make test-uefi    - Test ISO with QEMU (UEFI)"
        @echo "  make clean        - Remove build directory"
        @echo "  make distclean    - Remove build directory and ISO"
        @echo ""
        @echo "Configuration variables:"
        @echo "  ARCH=$(ARCH)"
        @echo "  RELEASE=$(RELEASE)"
        @echo "  HOSTNAME=$(HOSTNAME)"
        @echo "  ISO_NAME=$(ISO_NAME)"

# Install dependencies
deps:
        @echo -e "$(YELLOW)→ Installing dependencies...$(NC)"
        $(SUDO) apt update
        $(SUDO) apt install -y debootstrap squashfs-tools xorriso \
                isolinux syslinux-efi grub-pc-bin grub-efi-amd64-bin \
                grub-efi-ia32-bin mtools dosfstools genisoimage qemu-system-x86

# Create base root filesystem
rootfs: $(WORK_DIR)
        @echo -e "$(YELLOW)→ Creating base root filesystem with debootstrap...$(NC)"
        @if [ -d "$(ROOTFS_DIR)" ]; then \
                echo -e "$(RED)✗ Root filesystem already exists. Run 'make clean' first.$(NC)"; \
                exit 1; \
        fi
        $(SUDO) debootstrap --arch=$(ARCH) --variant=$(VARIANT) \
                $(RELEASE) $(ROOTFS_DIR) $(MIRROR)
        @echo -e "$(GREEN)✓ Base root filesystem created$(NC)"

# Configure the root filesystem
configure: rootfs
        @echo -e "$(YELLOW)→ Configuring root filesystem...$(NC)"
        @# Create configuration script
        @cat > $(WORK_DIR)/configure.sh << 'EOSCRIPT'
        #!/bin/bash
        set -e

        # Configure APT sources
        cat > /etc/apt/sources.list << EOF
        deb $(MIRROR) $(RELEASE) main contrib non-free non-free-firmware
        deb http://security.debian.org/debian-security $(RELEASE)-security main contrib non-free non-free-firmware
        deb $(MIRROR) $(RELEASE)-updates main contrib non-free non-free-firmware
        EOF

        # Update package lists
        apt update

        # Install essential packages
        DEBIAN_FRONTEND=noninteractive apt install -y --no-install-recommends \
                $(ESSENTIAL_PACKAGES) $(NETWORK_PACKAGES) $(UTIL_PACKAGES) $(LIVE_PACKAGES)

        # Configure locales
        echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
        locale-gen
        echo "LANG=en_US.UTF-8" > /etc/locale.conf

        # Set hostname
        echo "$(HOSTNAME)" > /etc/hostname

        # Configure hosts file
        cat > /etc/hosts << EOF
        127.0.0.1   localhost
        127.0.1.1   $(HOSTNAME)
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
        echo "root:$(ROOT_PASSWORD)" | chpasswd

        # Create regular user
        useradd -m -s /bin/bash -G sudo $(USER_NAME) || true
        echo "$(USER_NAME):$(USER_PASSWORD)" | chpasswd

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

        EOSCRIPT

        @# Make script executable
        @chmod +x $(WORK_DIR)/configure.sh

        @# Copy resolv.conf for network access in chroot
        $(SUDO) cp /etc/resolv.conf $(ROOTFS_DIR)/etc/resolv.conf

        @# Mount necessary filesystems
        $(SUDO) mount --bind /dev $(ROOTFS_DIR)/dev
        $(SUDO) mount --bind /dev/pts $(ROOTFS_DIR)/dev/pts
        $(SUDO) mount --bind /proc $(ROOTFS_DIR)/proc
        $(SUDO) mount --bind /sys $(ROOTFS_DIR)/sys

        @# Run configuration script in chroot
        $(SUDO) cp $(WORK_DIR)/configure.sh $(ROOTFS_DIR)/tmp/
        $(SUDO) chroot $(ROOTFS_DIR) /bin/bash /tmp/configure.sh
        $(SUDO) rm $(ROOTFS_DIR)/tmp/configure.sh

        @# Unmount filesystems
        $(SUDO) umount $(ROOTFS_DIR)/dev/pts || true
        $(SUDO) umount $(ROOTFS_DIR)/dev || true
        $(SUDO) umount $(ROOTFS_DIR)/proc || true
        $(SUDO) umount $(ROOTFS_DIR)/sys || true

        @echo -e "$(GREEN)✓ Root filesystem configured$(NC)"

# Create ISO directory structure
$(ISO_DIR): configure
        @echo -e "$(YELLOW)→ Creating ISO directory structure...$(NC)"
        mkdir -p $(ISO_DIR)/{boot/grub,live,isolinux,EFI/boot}

        @# Copy kernel and initrd
        $(SUDO) cp $(ROOTFS_DIR)/boot/vmlinuz-* $(ISO_DIR)/boot/vmlinuz
        $(SUDO) cp $(ROOTFS_DIR)/boot/initrd.img-* $(ISO_DIR)/boot/initrd.img

        @# Copy isolinux files
        $(SUDO) cp /usr/lib/ISOLINUX/isolinux.bin $(ISO_DIR)/isolinux/ || true
        $(SUDO) cp /usr/lib/syslinux/modules/bios/*.c32 $(ISO_DIR)/isolinux/ || true

        @echo -e "$(GREEN)✓ ISO directory structure created$(NC)"

# Create squashfs filesystem
squashfs: $(ISO_DIR)
        @echo -e "$(YELLOW)→ Creating squashfs filesystem...$(NC)"
        $(SUDO) mksquashfs $(ROOTFS_DIR) $(SQUASHFS_FILE) \
                -comp xz -b 1024k -e boot
        @echo -e "$(GREEN)✓ Squashfs filesystem created$(NC)"

# Create bootloader configurations
bootloader: squashfs
        @echo -e "$(YELLOW)→ Configuring bootloaders...$(NC)"

        @# Create GRUB configuration
        @cat > $(ISO_DIR)/boot/grub/grub.cfg << 'EOF'
        set default=0
        set timeout=10

        insmod efi_gop
        insmod efi_uga
        insmod video_bochs
        insmod video_cirrus
        insmod all_video

        menuentry "$(ISO_LABEL) Live" {
            linux /boot/vmlinuz boot=live quiet splash
            initrd /boot/initrd.img
        }

        menuentry "$(ISO_LABEL) Live (Safe Mode)" {
            linux /boot/vmlinuz boot=live quiet splash nomodeset
            initrd /boot/initrd.img
        }

        menuentry "$(ISO_LABEL) Live (Debug Mode)" {
            linux /boot/vmlinuz boot=live debug
            initrd /boot/initrd.img
        }
        EOF

        @# Create isolinux configuration
        @cat > $(ISO_DIR)/isolinux/isolinux.cfg << 'EOF'
        UI menu.c32
        PROMPT 0
        MENU TITLE $(ISO_LABEL) Boot Menu
        TIMEOUT 100

        LABEL live
            MENU LABEL ^$(ISO_LABEL) Live
            MENU DEFAULT
            KERNEL /boot/vmlinuz
            APPEND initrd=/boot/initrd.img boot=live quiet splash

        LABEL live-safe
            MENU LABEL $(ISO_LABEL) Live (^Safe Mode)
            KERNEL /boot/vmlinuz
            APPEND initrd=/boot/initrd.img boot=live quiet splash nomodeset

        LABEL live-debug
            MENU LABEL $(ISO_LABEL) Live (^Debug Mode)
            KERNEL /boot/vmlinuz
            APPEND initrd=/boot/initrd.img boot=live debug
        EOF

        @echo -e "$(GREEN)✓ Bootloaders configured$(NC)"

# Create the ISO image
iso: bootloader
        @echo -e "$(YELLOW)→ Creating ISO image...$(NC)"

        @# Create ISO with xorriso (supports BIOS and UEFI)
        xorriso -as mkisofs \
                -iso-level 3 \
                -full-iso9660-filenames \
                -volid "$(ISO_LABEL)" \
                -output $(ISO_NAME) \
                -eltorito-boot isolinux/isolinux.bin \
                -no-emul-boot \
                -boot-load-size 4 \
                -boot-info-table \
                -eltorito-catalog isolinux/boot.cat \
                -no-emul-boot \
                -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
                $(ISO_DIR) 2>/dev/null || \
        genisoimage -rational-rock \
                -volid "$(ISO_LABEL)" \
                -cache-inodes \
                -joliet \
                -full-iso9660-filenames \
                -b isolinux/isolinux.bin \
                -c isolinux/boot.cat \
                -no-emul-boot \
                -boot-load-size 4 \
                -boot-info-table \
                -output $(ISO_NAME) \
                $(ISO_DIR)

        @# Make ISO hybrid for USB boot
        @if command -v isohybrid >/dev/null 2>&1; then \
                isohybrid $(ISO_NAME) || true; \
        fi

        @echo -e "$(GREEN)✓ ISO image created: $(ISO_NAME)$(NC)"
        @echo -e "$(GREEN)  Size: $$(du -h $(ISO_NAME) | cut -f1)$(NC)"

# Test with QEMU (BIOS)
test: iso
        @echo -e "$(YELLOW)→ Testing ISO with QEMU (BIOS)...$(NC)"
        qemu-system-x86_64 -m 2048 -cdrom $(ISO_NAME) -boot d

# Test with QEMU (UEFI)
test-uefi: iso
        @echo -e "$(YELLOW)→ Testing ISO with QEMU (UEFI)...$(NC)"
        @if [ -f /usr/share/ovmf/OVMF.fd ]; then \
                qemu-system-x86_64 -m 2048 -cdrom $(ISO_NAME) -boot d \
                        -bios /usr/share/ovmf/OVMF.fd; \
        else \
                echo -e "$(RED)✗ OVMF not found. Install ovmf package.$(NC)"; \
        fi

# Write ISO to USB device
usb: iso
        @echo -e "$(YELLOW)→ Available USB devices:$(NC)"
        @lsblk -d -o NAME,SIZE,MODEL | grep -E "^sd"
        @echo ""
        @echo -e "$(RED)WARNING: This will destroy all data on the target device!$(NC)"
        @echo -n "Enter device name (e.g., sdb): "
        @read device; \
        if [ -z "$$device" ]; then \
                echo -e "$(RED)✗ No device specified$(NC)"; \
                exit 1; \
        fi; \
        echo -n "Are you sure you want to write to /dev/$$device? [y/N]: "; \
        read confirm; \
        if [ "$$confirm" = "y" ] || [ "$$confirm" = "Y" ]; then \
                echo -e "$(YELLOW)→ Writing ISO to /dev/$$device...$(NC)"; \
                $(SUDO) dd if=$(ISO_NAME) of=/dev/$$device bs=4M status=progress conv=fdatasync; \
                echo -e "$(GREEN)✓ ISO written to /dev/$$device$(NC)"; \
        else \
                echo -e "$(YELLOW)→ Operation cancelled$(NC)"; \
        fi

# Create work directory
$(WORK_DIR):
        mkdir -p $(WORK_DIR)

# Clean build directory
clean:
        @echo -e "$(YELLOW)→ Cleaning build directory...$(NC)"
        @if [ -d "$(ROOTFS_DIR)" ]; then \
                $(SUDO) umount $(ROOTFS_DIR)/dev/pts 2>/dev/null || true; \
                $(SUDO) umount $(ROOTFS_DIR)/dev 2>/dev/null || true; \
                $(SUDO) umount $(ROOTFS_DIR)/proc 2>/dev/null || true; \
                $(SUDO) umount $(ROOTFS_DIR)/sys 2>/dev/null || true; \
        fi
        $(SUDO) rm -rf $(WORK_DIR)
        @echo -e "$(GREEN)✓ Build directory cleaned$(NC)"

# Clean everything including ISO
distclean: clean
        @echo -e "$(YELLOW)→ Removing ISO file...$(NC)"
        rm -f $(ISO_NAME)
        @echo -e "$(GREEN)✓ All files cleaned$(NC)"

# Package list management
list-packages:
        @echo -e "$(YELLOW)Installed packages in rootfs:$(NC)"
        @if [ -d "$(ROOTFS_DIR)" ]; then \
                $(SUDO) chroot $(ROOTFS_DIR) dpkg -l | grep "^ii" | awk '{print $$2, $$3}' | column -t; \
        else \
                echo -e "$(RED)✗ Root filesystem not found. Run 'make rootfs' first.$(NC)"; \
        fi

# Size information
size-info:
        @echo -e "$(YELLOW)Size Information:$(NC)"
        @if [ -d "$(ROOTFS_DIR)" ]; then \
                echo "Root filesystem: $$($(SUDO) du -sh $(ROOTFS_DIR) | cut -f1)"; \
        fi
        @if [ -f "$(SQUASHFS_FILE)" ]; then \
                echo "Squashfs file: $$(du -h $(SQUASHFS_FILE) | cut -f1)"; \
        fi
        @if [ -f "$(ISO_NAME)" ]; then \
                echo "ISO file: $$(du -h $(ISO_NAME) | cut -f1)"; \
        fi

# Advanced customization - add custom files
customize:
        @echo -e "$(YELLOW)→ Customization directory: $(WORK_DIR)/custom$(NC)"
        @mkdir -p $(WORK_DIR)/custom
        @echo "Place files to be added to the rootfs in $(WORK_DIR)/custom/"
        @echo "They will be copied maintaining the directory structure"
        @if [ -d "$(WORK_DIR)/custom" ] && [ "$$(ls -A $(WORK_DIR)/custom)" ]; then \
                echo -e "$(YELLOW)→ Copying custom files...$(NC)"; \
                $(SUDO) cp -r $(WORK_DIR)/custom/* $(ROOTFS_DIR)/; \
                echo -e "$(GREEN)✓ Custom files copied$(NC)"; \
        fi

# Development shell - chroot into the rootfs for manual configuration
shell:
        @if [ ! -d "$(ROOTFS_DIR)" ]; then \
                echo -e "$(RED)✗ Root filesystem not found. Run 'make rootfs' first.$(NC)"; \
                exit 1; \
        fi
        @echo -e "$(YELLOW)→ Entering chroot shell...$(NC)"
        @echo -e "$(YELLOW)  Type 'exit' to leave the chroot$(NC)"
        @$(SUDO) mount --bind /dev $(ROOTFS_DIR)/dev || true
        @$(SUDO) mount --bind /dev/pts $(ROOTFS_DIR)/dev/pts || true
        @$(SUDO) mount --bind /proc $(ROOTFS_DIR)/proc || true
        @$(SUDO) mount --bind /sys $(ROOTFS_DIR)/sys || true
        @$(SUDO) cp /etc/resolv.conf $(ROOTFS_DIR)/etc/resolv.conf
        @$(SUDO) chroot $(ROOTFS_DIR) /bin/bash
        @$(SUDO) umount $(ROOTFS_DIR)/dev/pts || true
        @$(SUDO) umount $(ROOTFS_DIR)/dev || true
        @$(SUDO) umount $(ROOTFS_DIR)/proc || true
        @$(SUDO) umount $(ROOTFS_DIR)/sys || true
        @echo -e "$(GREEN)✓ Exited chroot$(NC)"

.PHONY: usb list-packages size-info customize shell
