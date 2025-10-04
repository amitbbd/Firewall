#!/bin/bash
#
# Main Installer Script

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/firewall-installer.log"

# Source common functions
source "$SCRIPT_DIR/functions.sh"

main() {
    log "Starting Firewall Distribution Installer"
    
    # Check if running from live environment
    if ! is_live_environment; then
        error "This installer must be run from the live environment"
    fi
    
    # Display welcome message
    show_welcome
    
    # Gather installation parameters
    local config=$(gather_configuration)
    
    # Confirm installation
    if confirm_installation "$config"; then
        # Perform installation
        partition_disk "$(echo "$config" | jq -r '.disk')"
        install_system
        configure_system "$config"
        install_bootloader "$(echo "$config" | jq -r '.disk')"
        
        log "Installation completed successfully"
        show_success_message
    else
        log "Installation cancelled by user"
    fi
}

# Run main function
main "$@"
