#!/bin/bash
#
# Firewall ISO Builder - Main Build Script
# Industry Standard Implementation

set -euo pipefail

# Script Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
LOG_FILE="$BUILD_DIR/logs/build-$(date +%Y%m%d%H%M%S).log"

# Color Codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging Functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
    exit 1
}

# Usage Information
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -c, --clean      Clean build directory before building"
    echo "  -d, --debug      Enable debug output"
    echo "  -t, --test       Test ISO after build (requires QEMU)"
    echo "  -h, --help       Show this help message"
}

# Parse Command Line Arguments
CLEAN_BUILD=false
DEBUG_MODE=false
TEST_ISO=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--clean)
            CLEAN_BUILD=true
            shift
            ;;
        -d|--debug)
            DEBUG_MODE=true
            set -x
            shift
            ;;
        -t|--test)
            TEST_ISO=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

# Main Build Function
main() {
    log "Starting Firewall ISO Build Process"
    
    # Clean if requested
    if [ "$CLEAN_BUILD" = true ]; then
        log "Performing clean build..."
        make clean
    fi
    
    # Check dependencies
    log "Checking system dependencies..."
    if ! command -v debootstrap >/dev/null; then
        error "debootstrap is required but not installed. Run: sudo apt-get install debootstrap"
    fi
    
    if ! command -v grub-mkrescue >/dev/null; then
        error "grub-mkrescue is required but not installed. Run: sudo apt-get install grub-pc-bin grub-efi-amd64-bin"
    fi
    
    # Build ISO
    log "Building ISO using Makefile..."
    if make build-iso; then
        log "ISO build completed successfully"
        
        # Test ISO if requested
        if [ "$TEST_ISO" = true ]; then
            log "Testing ISO with QEMU..."
            if command -v qemu-system-x86_64 >/dev/null; then
                make test-iso
            else
                warn "QEMU not available, skipping ISO test"
            fi
        fi
        
        # Display build summary
        log "Build completed successfully!"
        ISO_FILE=$(ls firewall-distro-*.iso 2>/dev/null | head -1)
        if [ -n "$ISO_FILE" ]; then
            echo "----------------------------------------"
            echo "Build Summary:"
            echo "  ISO File: $ISO_FILE"
            echo "  Size: $(du -h "$ISO_FILE" | cut -f1)"
            echo "  Build Log: $LOG_FILE"
            echo "----------------------------------------"
        fi
    else
        error "ISO build failed. Check logs: $LOG_FILE"
    fi
}

# Error Handling
trap 'error "Build failed at line $LINENO"' ERR

# Run Main Function
main "$@"
