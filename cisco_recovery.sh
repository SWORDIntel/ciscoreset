#!/usr/bin/env bash
# Cisco ISR & ASA Advanced Recovery Tool v2.1
# ... (Header and other functions remain the same) ...

# ============================================================================
# DEVICE DETECTION
# ============================================================================
detect_serial_devices() {
    local -a devices=()
    for device in /dev/ttyUSB* /dev/ttyACM*; do
        [[ -e "$device" ]] && devices+=("$device")
    done
    printf '%s\n' "${devices[@]}"
}

# ============================================================================
# CORE LOGIC & MENUS
# ============================================================================
password_recovery_isr() {
    print_header; echo "--- ISR Password Recovery ---"
    send_command "confreg 0x2142" "rommon"; send_command "reset" "rommon"
    wait_for_prompt ">" 120
    send_command "enable" "#"
    send_command "copy startup-config running-config" "#"; send_command "" "#"
    read -sp "Enter new enable secret: " new_pass; echo
    send_command "configure terminal" "(config)#"
    send_command "enable secret $new_pass" "(config)#"
    send_command "config-register 0x2102" "(config)#"
    send_command "end" "#"
    send_command "write memory" "#"
    echo "ISR Password Recovery Complete."
}

password_recovery_asa() {
    print_header; echo "--- ASA Password Recovery ---"
    send_command "confreg 0x41" "rommon"; send_command "boot" "rommon"
    wait_for_prompt "ciscoasa>" 120
    send_command "enable" "#"; send_command "" "Confirm" # No password, just press enter
    send_command "rename flash:/startup-config flash:/startup-config.bak" "#"
    send_command "reload" "confirm"; send_command "" "Reload"
    wait_for_prompt "password:" 120
    read -sp "Enter new enable password: " new_pass; echo
    send_command "$new_pass" "Confirm"; send_command "$new_pass" "#"
    send_command "rename flash:/startup-config.bak flash:/startup-config" "#"
    send_command "copy startup-config running-config" "#"
    send_command "configure terminal" "(config)#"
    send_command "enable secret $new_pass" "(config)#"
    send_command "config-register 0x01" "(config)#"
    send_command "end" "#"; send_command "write memory" "#"
    echo "ASA Password Recovery Complete."
}

menu_configuration_dump() {
    print_header; echo "--- Configuration Auditor ---"
    local output_dir="/tmp/config_audit_$(date +%s)"
    mkdir -p "$output_dir"; echo "Audit report will be in: $output_dir"
    send_command "terminal length 0"
    echo "show running-config" >&${SERIAL_FD}
    # ... (Full config capture and analysis logic) ...
    send_command "terminal length 24"
    echo "Configuration Audit Complete."
}

# ... (Rest of the script remains the same) ...
