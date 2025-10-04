# Debian Firewall ISO Builder
# Industry Standard Build System

.PHONY: all clean build-iso prepare-env check-deps test-iso distclean help

# Build Configuration
ISO_NAME := firewall-distro-1.0.0
BUILD_DIR := $(CURDIR)/build
CHROOT_DIR := $(BUILD_DIR)/chroot
ISO_DIR := $(BUILD_DIR)/iso
CACHE_DIR := $(BUILD_DIR)/cache
LOG_DIR := $(BUILD_DIR)/logs
TIMESTAMP := $(shell date +%Y%m%d%H%M%S)

# Debian Configuration
DEBIAN_SUITE := bookworm
DEBIAN_MIRROR := http://deb.debian.org/debian
DEBIAN_ARCH := amd64

# Kernel Configuration
KERNEL_PACKAGE := linux-image-amd64
KERNEL_VERSION := 6.1.0-18-amd64

# Color Definitions
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[1;33m
BLUE := \033[0;34m
NC := \033[0m

# Default Target
all: build-iso

# Environment Setup
prepare-env:
	@echo -e "${GREEN}[INFO]${NC} Preparing build environment..."
	@mkdir -p $(BUILD_DIR) $(CHROOT_DIR) $(ISO_DIR) $(CACHE_DIR) $(LOG_DIR)
	@mkdir -p $(ISO_DIR)/boot/grub
	@mkdir -p $(ISO_DIR)/live
	@mkdir -p $(ISO_DIR)/installer

# Dependency Checking
check-deps:
	@echo -e "${GREEN}[INFO]${NC} Checking build dependencies..."
	@for pkg in debootstrap grub-pc-bin grub-efi-amd64-bin mtools xorriso squashfs-tools; do \
		if ! dpkg -l | grep -q "$$pkg"; then \
			echo -e "${YELLOW}[WARN]${NC} Package $$pkg is missing. Installing..."; \
			sudo apt-get install -y $$pkg; \
		fi; \
	done

# Base System Installation
bootstrap-system: prepare-env check-deps
	@echo -e "${GREEN}[INFO]${NC} Bootstrapping Debian base system..."
	@sudo debootstrap --arch=$(DEBIAN_ARCH) --variant=minbase \
		--include=systemd,systemd-sysv,udev,dbus \
		$(DEBIAN_SUITE) $(CHROOT_DIR) $(DEBIAN_MIRROR) \
		> $(LOG_DIR)/bootstrap.log 2>&1

# Copy Configuration Files
copy-configs:
	@echo -e "${GREEN}[INFO]${NC} Copying configuration files..."
	@sudo cp config/sources.list $(CHROOT_DIR)/etc/apt/sources.list
	@sudo cp -r scripts/installer $(CHROOT_DIR)/usr/share/firewall-installer/
	@sudo cp -r scripts/post-install $(CHROOT_DIR)/usr/share/firewall-installer/
	@sudo cp config/grub.cfg $(ISO_DIR)/boot/grub/grub.cfg

# Install Packages
install-packages: bootstrap-system copy-configs
	@echo -e "${GREEN}[INFO]${NC} Installing packages..."
	@sudo cp config/packages.list $(CHROOT_DIR)/tmp/packages.list
	@sudo cp scripts/configure-chroot.sh $(CHROOT_DIR)/tmp/
	@sudo chmod +x $(CHROOT_DIR)/tmp/configure-chroot.sh
	@sudo chroot $(CHROOT_DIR) /tmp/configure-chroot.sh

# Configure System
configure-system: install-packages
	@echo -e "${GREEN}[INFO]${NC} Configuring system..."
	@sudo cp scripts/build-iso.sh $(CHROOT_DIR)/tmp/
	@sudo chmod +x $(CHROOT_DIR)/tmp/build-iso.sh
	@sudo chroot $(CHROOT_DIR) /tmp/build-iso.sh

# Create SquashFS
create-squashfs: configure-system
	@echo -e "${GREEN}[INFO]${NC} Creating SquashFS filesystem..."
	@sudo mksquashfs $(CHROOT_DIR) $(ISO_DIR)/live/filesystem.squashfs \
		-comp xz -e boot \
		> $(LOG_DIR)/squashfs.log 2>&1

# Create ISO Structure
create-iso-structure: create-squashfs
	@echo -e "${GREEN}[INFO]${NC} Creating ISO structure..."
	@sudo cp $(CHROOT_DIR)/boot/vmlinuz-* $(ISO_DIR)/live/vmlinuz
	@sudo cp $(CHROOT_DIR)/boot/initrd.img-* $(ISO_DIR)/live/initrd
	@sudo cp -r $(CHROOT_DIR)/usr/share/firewall-installer/installer/* $(ISO_DIR)/installer/

# Build Final ISO
build-iso: create-iso-structure
	@echo -e "${GREEN}[INFO]${NC} Building ISO image..."
	@grub-mkrescue -o $(ISO_NAME)-$(TIMESTAMP).iso $(ISO_DIR) \
		-volid "FIREWALL_DISTRO" \
		> $(LOG_DIR)/iso-build.log 2>&1
	@echo -e "${GREEN}[SUCCESS]${NC} ISO built: $(ISO_NAME)-$(TIMESTAMP).iso"

# Test ISO (QEMU)
test-iso:
	@echo -e "${GREEN}[INFO]${NC} Testing ISO with QEMU..."
	@if [ -f "$(ISO_NAME)-*.iso" ]; then \
		qemu-system-x86_64 -cdrom $(ISO_NAME)-*.iso -m 2048 -smp 2; \
	else \
		echo -e "${RED}[ERROR]${NC} No ISO found to test"; \
	fi

# Clean Build
clean:
	@echo -e "${YELLOW}[INFO]${NC} Cleaning build directories..."
	@sudo rm -rf $(BUILD_DIR)
	@rm -f firewall-distro-*.iso

# Deep Clean
distclean: clean
	@echo -e "${YELLOW}[INFO]${NC} Deep cleaning..."
	@sudo rm -rf $(CACHE_DIR)
	@sudo rm -f *.log

# Help
help:
	@echo -e "${BLUE}Firewall ISO Builder Targets:${NC}"
	@echo "  all          - Build complete ISO (default)"
	@echo "  build-iso    - Build the ISO image"
	@echo "  test-iso     - Test ISO with QEMU (if available)"
	@echo "  clean        - Remove build artifacts"
	@echo "  distclean    - Remove all generated files"
	@echo "  help         - Show this help message"

# Quick Build (Development)
dev-build: prepare-env check-deps build-iso

# Release Build (Full)
release-build: distclean all
