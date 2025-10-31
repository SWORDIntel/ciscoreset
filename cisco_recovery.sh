#!/bin/bash

# Cisco ISR 4321 Recovery and Management Tool

# --- Default Configuration ---
SERIAL_DEVICE="/dev/ttyS0"
BAUD_RATE="9600"
TIMEOUT=300

# --- TUI & Helper Functions ---

function print_header() {
    clear
    echo "==============================================="
    echo "   Cisco ISR 4321 Recovery & Management Tool"
    echo "==============================================="
    echo
}

function show_help() {
    # ... (Implementation is correct) ...
}

function read_until_prompt() {
    local prompt_char="$1"
    while read -t 10 line <&3; do
        line=$(echo "$line" | tr -d '\r')
        echo "[ROUTER] $line"
        if [[ "$line" == *"$prompt_char"* ]]; then break; fi
    done
}

function send_os_command() {
    # ... (Implementation is correct) ...
}

# --- All Menu Functions ---

# ... (menu_reset_password, menu_load_firmware, etc. are correct) ...

function menu_storage_inspector() {
    print_header; echo "--- Storage Inspector ---"
    echo "Available storage devices:"; echo "dev" >&3; read_until_prompt "rommon"
    read -p "Enter device to inspect (e.g., bootflash:): " device_name
    [[ -z "$device_name" ]] && return
    echo "Listing files on '$device_name'..."; echo "dir $device_name" >&3; read_until_prompt "rommon"
    read -n 1 -s -r -p "Press any key to return..."
}

function menu_manual_boot() {
    print_header; echo "--- Manual Boot from File ---"
    read -p "List files on a storage device first? (y/n) " list_files
    [[ "$list_files" == "y" ]] && menu_storage_inspector
    read -p "Enter full path to bootable image (e.g., bootflash:image.bin): " image_path
    [[ -z "$image_path" ]] && { echo "Error: Path cannot be empty."; sleep 2; return; }
    read -p "This will boot '$image_path' and exit the script. Continue? (y/n) " confirm
    [[ "$confirm" != "y" ]] && return
    echo "Sending boot command..."; echo "boot $image_path" >&3; sleep 5
}

function menu_rommon_upgrade_helper() {
    print_header; echo "--- ROMMON Upgrade Helper ---"
    echo "IMPORTANT: The upgrade itself must be done from the live IOS-XE OS."
    echo "This tool helps you safely PREPARE by setting the BOOT variable."
    read -p "Set the BOOT variable now? (y/n) " set_boot
    [[ "$set_boot" != "y" ]] && return
    menu_storage_inspector
    read -p "Enter the full path to a reliable firmware image: " boot_image_path
    [[ -z "$boot_image_path" ]] && { echo "Error: Path cannot be empty."; sleep 2; return; }
    echo "Setting BOOT variable..."; echo "BOOT=$boot_image_path" >&3; read_until_prompt "rommon"
    echo "Saving to NVRAM..."; echo "sync" >&3; read_until_prompt "rommon"
    echo "BOOT variable has been set and saved."
    read -n 1 -s -r -p "Press any key to return..."
}

function menu_backup_firmware() {
    # ... (Implementation is correct) ...
}


# --- Main Workflows ---

function run_rommon_recovery_mode() {
    # ... (Getting to ROMMON is the same) ...
    while true; do
        print_header; echo "Successfully entered ROMMON mode on $SERIAL_DEVICE"
        echo "Select a ROMMON Recovery option:"
        echo "  1) Reset Password"; echo "  2) Storage Inspector"
        echo "  3) Manual Boot from File"; echo "  4) Load Firmware from TFTP"
        echo "  5) Change Boot Variables"; echo "  6) ROMMON Upgrade Helper"
        echo "  7) Raw Shell"; echo "  q) Quit to Main Menu"
        read -p "Enter your choice: " choice
        case $choice in
            1) menu_reset_password; break ;;
            2) menu_storage_inspector ;;
            3) menu_manual_boot; break ;;
            4) menu_load_firmware; break ;;
            5) menu_change_boot_vars ;;
            6) menu_rommon_upgrade_helper ;;
            7) menu_raw_shell ;;
            q) break ;;
            *) echo "Invalid option."; sleep 1 ;;
        esac
    done
}

function run_live_management_mode() {
    # ... (Implementation is correct) ...
}


# --- Main Logic ---

# ... (Argument parsing and top-level menu are correct) ...
