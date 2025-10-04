# Minimal Firewall Installer ISO Builder
# Creates the smallest possible installer with only firewall essentials

SHELL := /bin/bash
ARCH := amd64
RELEASE := bookworm
MIRROR := http://deb.debian.org/debian/
VARIANT := minbase
ISO_NAME := firewall.iso
ISO_LABEL := FIREWALL
WORK_DIR := build
ROOTFS_DIR := $(WORK_DIR)/rootfs
ISO_DIR := $(WORK_DIR)/iso
SQUASHFS_FILE := $(ISO_DIR)/live/filesystem.squashfs

# System configuration
HOSTNAME := firewall
ROOT_PASSWORD := root1234

# Colors
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m

# Check if running as root
SUDO := $(shell [ $$(id -u) -eq 0 ] && echo "" || echo "sudo")

.PHONY: all clean deps rootfs configure squashfs iso test help

# Default target
all: iso
	@echo -e "$(GREEN)✓ Minimal installer ISO complete: $(ISO_NAME)$(NC)"
	@echo -e "$(GREEN)  ISO Size: $$(du -h $(ISO_NAME) | cut -f1)$(NC)"
	@echo -e "$(YELLOW)  Estimated installed size: ~200-300MB$(NC)"

help:
	@echo "Minimal Firewall Installer ISO Builder"
	@echo "======================================="
	@echo "Available targets:"
	@echo "  make all          - Build minimal installer ISO (default)"
	@echo "  make deps         - Install required dependencies"
	@echo "  make rootfs       - Create minimal root filesystem"
	@echo "  make configure    - Configure the root filesystem"
	@echo "  make squashfs     - Create squashfs filesystem"
	@echo "  make iso          - Create bootable ISO"
	@echo "  make test         - Test ISO with QEMU"
	@echo "  make clean        - Remove build directory"
	@echo "  make distclean    - Remove build directory and ISO"
	@echo ""
	@echo "Configuration:"
	@echo "  ARCH=$(ARCH)"
	@echo "  RELEASE=$(RELEASE)"
	@echo "  HOSTNAME=$(HOSTNAME)"
	@echo "  ROOT_PASSWORD=$(ROOT_PASSWORD)"
	@echo "  ISO_NAME=$(ISO_NAME)"
	@echo ""
	@echo "Minimal packages only:"
	@echo "  - Linux kernel"
	@echo "  - systemd"
	@echo "  - iptables"
	@echo "  - iproute2"
	@echo "  - openssh-server"
	@echo "  - nano"

# Install dependencies
deps:
	@echo -e "$(YELLOW)→ Installing build dependencies...$(NC)"
	$(SUDO) apt update
	$(SUDO) apt install -y debootstrap squashfs-tools xorriso \
		isolinux syslinux-efi grub-pc-bin grub-efi-amd64-bin \
		mtools qemu-system-x86 genisoimage

# Create work directory
$(WORK_DIR):
	mkdir -p $(WORK_DIR)

# Create minimal root filesystem
rootfs: $(WORK_DIR)
	@echo -e "$(YELLOW)→ Creating minimal root filesystem with debootstrap...$(NC)"
	@echo -e "$(YELLOW)  Using variant: minbase (smallest possible)$(NC)"
	@echo -e "$(YELLOW)  This will take 5-10 minutes...$(NC)"
	@if [ ! -d "$(ROOTFS_DIR)" ]; then \
		$(SUDO) debootstrap \
			--arch=$(ARCH) \
			--variant=$(VARIANT) \
			--include=linux-image-$(ARCH),grub-pc,initramfs-tools,live-boot,busybox \
			$(RELEASE) \
			$(ROOTFS_DIR) \
			$(MIRROR); \
		echo -e "$(GREEN)✓ Minimal root filesystem created$(NC)"; \
	else \
		echo -e "$(YELLOW)→ Root filesystem already exists, skipping...$(NC)"; \
	fi

# Configure the root filesystem
configure: rootfs
	@echo -e "$(YELLOW)→ Configuring minimal system...$(NC)"
	
	@# Make configure script executable
	@chmod +x $(WORK_DIR)/configure.sh
	
	@# Copy resolv.conf for network access
	$(SUDO) cp /etc/resolv.conf $(ROOTFS_DIR)/etc/resolv.conf
	
	@# Mount necessary filesystems
	$(SUDO) mount --bind /dev $(ROOTFS_DIR)/dev || true
	$(SUDO) mount --bind /dev/pts $(ROOTFS_DIR)/dev/pts || true
	$(SUDO) mount --bind /proc $(ROOTFS_DIR)/proc || true
	$(SUDO) mount --bind /sys $(ROOTFS_DIR)/sys || true
	
	@# Copy configuration script with variables
	@echo "HOSTNAME='$(HOSTNAME)'" > $(ROOTFS_DIR)/tmp/config-vars.sh
	@echo "ROOT_PASSWORD='$(ROOT_PASSWORD)'" >> $(ROOTFS_DIR)/tmp/config-vars.sh
	$(SUDO) cp $(WORK_DIR)/configure.sh $(ROOTFS_DIR)/tmp/
	
	@# Run configuration in chroot
	@echo -e "$(YELLOW)  Running configuration script in chroot...$(NC)"
	$(SUDO) chroot $(ROOTFS_DIR) /bin/bash /tmp/configure.sh
	
	@# Cleanup
	$(SUDO) rm -f $(ROOTFS_DIR)/tmp/configure.sh
	$(SUDO) rm -f $(ROOTFS_DIR)/tmp/config-vars.sh
	
	@# Unmount filesystems
	$(SUDO) umount $(ROOTFS_DIR)/dev/pts 2>/dev/null || true
	$(SUDO) umount $(ROOTFS_DIR)/dev 2>/dev/null || true
	$(SUDO) umount $(ROOTFS_DIR)/proc 2>/dev/null || true
	$(SUDO) umount $(ROOTFS_DIR)/sys 2>/dev/null || true
	
	@echo -e "$(GREEN)✓ Minimal system configured$(NC)"

# Create ISO directory structure
$(ISO_DIR): configure
	@echo -e "$(YELLOW)→ Creating ISO directory structure...$(NC)"
	mkdir -p $(ISO_DIR)/{live,boot/grub,isolinux,EFI/boot}
	
	@# Copy kernel and initrd
	$(SUDO) cp $(ROOTFS_DIR)/boot/vmlinuz-* $(ISO_DIR)/boot/vmlinuz
	$(SUDO) cp $(ROOTFS_DIR)/boot/initrd.img-* $(ISO_DIR)/boot/initrd.img
	
	@# Copy isolinux files
	$(SUDO) cp /usr/lib/ISOLINUX/isolinux.bin $(ISO_DIR)/isolinux/
	$(SUDO) cp /usr/lib/syslinux/modules/bios/{ldlinux.c32,libcom32.c32,libutil.c32,vesamenu.c32} $(ISO_DIR)/isolinux/ 2>/dev/null || true
	
	@echo -e "$(GREEN)✓ ISO directory structure created$(NC)"

# Create squashfs filesystem
squashfs: $(ISO_DIR)
	@echo -e "$(YELLOW)→ Creating compressed squashfs filesystem...$(NC)"
	@echo -e "$(YELLOW)  This compresses the minimal system...$(NC)"
	$(SUDO) mksquashfs $(ROOTFS_DIR) $(SQUASHFS_FILE) \
		-comp xz -b 1M -Xdict-size 100% \
		-e boot -e proc -e sys -e dev -e run \
		-noappend
	@echo -e "$(GREEN)✓ Squashfs created: $$(du -h $(SQUASHFS_FILE) | cut -f1)$(NC)"

# Create bootloader configurations
bootloader: squashfs
	@echo -e "$(YELLOW)→ Configuring bootloaders...$(NC)"
	
	@# Create isolinux configuration
	@printf '%s\n' \
		'UI vesamenu.c32' \
		'TIMEOUT 50' \
		'PROMPT 0' \
		'MENU TITLE Minimal Firewall Installer' \
		'' \
		'LABEL install' \
		'    MENU LABEL Install Minimal Firewall' \
		'    MENU DEFAULT' \
		'    KERNEL /boot/vmlinuz' \
		'    APPEND initrd=/boot/initrd.img boot=live quiet' \
		'' \
		'LABEL live' \
		'    MENU LABEL Boot Live System (No Install)' \
		'    KERNEL /boot/vmlinuz' \
		'    APPEND initrd=/boot/initrd.img boot=live quiet' \
		> $(ISO_DIR)/isolinux/isolinux.cfg
	
	@# Create GRUB configuration
	@printf '%s\n' \
		'set timeout=5' \
		'set default=0' \
		'' \
		'menuentry "Install Minimal Firewall" {' \
		'    linux /boot/vmlinuz boot=live quiet' \
		'    initrd /boot/initrd.img' \
		'}' \
		'' \
		'menuentry "Boot Live System" {' \
		'    linux /boot/vmlinuz boot=live quiet' \
		'    initrd /boot/initrd.img' \
		'}' \
		> $(ISO_DIR)/boot/grub/grub.cfg
	
	@echo -e "$(GREEN)✓ Bootloaders configured$(NC)"

# Create the ISO image
iso: bootloader
	@echo -e "$(YELLOW)→ Creating minimal installer ISO...$(NC)"
	
	@# Create ISO with xorriso
	xorriso -as mkisofs \
		-iso-level 3 \
		-full-iso9660-filenames \
		-volid "$(ISO_LABEL)" \
		-output $(ISO_NAME) \
		-eltorito-boot isolinux/isolinux.bin \
		-eltorito-catalog isolinux/boot.cat \
		-no-emul-boot \
		-boot-load-size 4 \
		-boot-info-table \
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
		isohybrid $(ISO_NAME) 2>/dev/null || true; \
	fi
	
	@echo -e "$(GREEN)✓ Minimal installer ISO created: $(ISO_NAME)$(NC)"

# Test with QEMU
test: iso
	@echo -e "$(YELLOW)→ Testing minimal installer ISO with QEMU...$(NC)"
	@echo -e "$(YELLOW)  Creating test virtual disk (20GB)...$(NC)"
	@qemu-img create -f qcow2 $(WORK_DIR)/test-disk.qcow2 20G 2>/dev/null || true
	@echo -e "$(YELLOW)  Starting VM...$(NC)"
	@echo -e "$(YELLOW)  After boot, login as root and run: install-to-disk$(NC)"
	qemu-system-x86_64 \
		-m 1024 \
		-cdrom $(ISO_NAME) \
		-hda $(WORK_DIR)/test-disk.qcow2 \
		-boot d \
		-enable-kvm 2>/dev/null || \
	qemu-system-x86_64 \
		-m 1024 \
		-cdrom $(ISO_NAME) \
		-hda $(WORK_DIR)/test-disk.qcow2 \
		-boot d

# Test installed system
test-installed:
	@echo -e "$(YELLOW)→ Testing installed system...$(NC)"
	@if [ ! -f "$(WORK_DIR)/test-disk.qcow2" ]; then \
		echo -e "$(RED)✗ No installed system found. Run 'make test' and install first.$(NC)"; \
		exit 1; \
	fi
	qemu-system-x86_64 \
		-m 1024 \
		-hda $(WORK_DIR)/test-disk.qcow2 \
		-enable-kvm 2>/dev/null || \
	qemu-system-x86_64 \
		-m 1024 \
		-hda $(WORK_DIR)/test-disk.qcow2

# Write ISO to USB
usb: iso
	@echo -e "$(YELLOW)→ Available USB devices:$(NC)"
	@lsblk -d -o NAME,SIZE,MODEL | grep -E "^sd" || echo "No USB devices found"
	@echo ""
	@echo -e "$(RED)WARNING: This will destroy all data on the target device!$(NC)"
	@echo -n "Enter device name (e.g., sdb): "
	@read device; \
	if [ -z "$$device" ]; then \
		echo -e "$(RED)✗ No device specified$(NC)"; \
		exit 1; \
	fi; \
	echo -n "Are you sure you want to write to /dev/$$device? [yes/no]: "; \
	read confirm; \
	if [ "$$confirm" = "yes" ]; then \
		echo -e "$(YELLOW)→ Writing ISO to /dev/$$device...$(NC)"; \
		$(SUDO) dd if=$(ISO_NAME) of=/dev/$$device bs=4M status=progress conv=fdatasync; \
		$(SUDO) sync; \
		echo -e "$(GREEN)✓ ISO written to /dev/$$device$(NC)"; \
	else \
		echo -e "$(YELLOW)→ Operation cancelled$(NC)"; \
	fi

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

# Show size information
size-info:
	@echo -e "$(YELLOW)Size Information:$(NC)"
	@if [ -d "$(ROOTFS_DIR)" ]; then \
		echo "Root filesystem: $$($(SUDO) du -sh $(ROOTFS_DIR) 2>/dev/null | cut -f1 || echo 'N/A')"; \
	fi
	@if [ -f "$(SQUASHFS_FILE)" ]; then \
		echo "Squashfs file: $$(du -h $(SQUASHFS_FILE) 2>/dev/null | cut -f1 || echo 'N/A')"; \
	fi
	@if [ -f "$(ISO_NAME)" ]; then \
		echo "ISO file: $$(du -h $(ISO_NAME) | cut -f1)"; \
	fi

# List installed packages
list-packages:
	@echo -e "$(YELLOW)Minimal packages in rootfs:$(NC)"
	@if [ -d "$(ROOTFS_DIR)" ]; then \
		$(SUDO) chroot $(ROOTFS_DIR) dpkg -l 2>/dev/null | grep "^ii" | wc -l | xargs echo "Total packages:"; \
		echo ""; \
		echo "Essential packages:"; \
		$(SUDO) chroot $(ROOTFS_DIR) dpkg -l 2>/dev/null | grep "^ii" | awk '{print "  " $$2}' | head -20; \
	else \
		echo -e "$(RED)✗ Root filesystem not found. Run 'make rootfs' first.$(NC)"; \
	fi

# Development shell - chroot for manual configuration
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
	@$(SUDO) umount $(ROOTFS_DIR)/dev/pts 2>/dev/null || true
	@$(SUDO) umount $(ROOTFS_DIR)/dev 2>/dev/null || true
	@$(SUDO) umount $(ROOTFS_DIR)/proc 2>/dev/null || true
	@$(SUDO) umount $(ROOTFS_DIR)/sys 2>/dev/null || true
	@echo -e "$(GREEN)✓ Exited chroot$(NC)"

# Show info
info:
	@echo -e "$(YELLOW)Minimal Firewall Installer Configuration:$(NC)"
	@echo "  Architecture: $(ARCH)"
	@echo "  Release: $(RELEASE)"
	@echo "  Variant: $(VARIANT) (smallest)"
	@echo "  Hostname: $(HOSTNAME)"
	@echo "  Root Password: $(ROOT_PASSWORD)"
	@echo "  ISO Name: $(ISO_NAME)"
	@echo ""
	@echo -e "$(YELLOW)Minimal Packages Only:$(NC)"
	@echo "  ✓ Linux kernel"
	@echo "  ✓ systemd"
	@echo "  ✓ iptables (firewall)"
	@echo "  ✓ iproute2 (networking)"
	@echo "  ✓ openssh-server"
	@echo "  ✓ nano (text editor)"
	@echo ""
	@echo -e "$(YELLOW)Expected Sizes:$(NC)"
	@echo "  ISO: ~150-200MB"
	@echo "  Installed: ~200-300MB"

.PHONY: usb size-info list-packages shell info test-installed
