#!/usr/bin/env bash
# Unified VLAN Management Tool for Nortel, Cisco ISR, and Cisco ASA
set -euo pipefail
IFS=$'\n\t'

# --- Configuration & Helpers ---
SERIAL_DEVICE=""
CONFIG_FILE=""
TIMEOUT=10
die() { echo "ERROR: $1" >&2; exit 1; }
print_header() { clear; echo "======================================"; echo "  Unified VLAN Management Tool"; echo "======================================"; echo; }

# --- Nortel-Specific Functions ---
nortel_send_cmd() {
    local cmd="$1"; echo " > SEND: [$cmd]"; echo "$cmd" >&3
    while read -t $TIMEOUT line <&3; do line=$(echo "$line"|tr -d '\r'); echo "[SWITCH] $line"; if [[ "$line" == *"->"* ]]; then break; fi; done
}
nortel_go_to_main() { for _ in {1..5}; do nortel_send_cmd "q"; done; }
nortel_provision_vlan() {
    local vlan_id="$1" name="$2"; echo "PROVISIONING VLAN: ID=$vlan_id, Name=$name"
    nortel_go_to_main; nortel_send_cmd "vlan"; nortel_send_cmd "create $vlan_id"
    if [[ -n "$name" ]]; then nortel_send_cmd "name $vlan_id $name"; fi
}
nortel_assign_ports() {
    local vlan_id="$1" ports="$2"; echo "  -> ASSIGNING PORTS: VLAN=$vlan_id, Ports=$ports"
    nortel_go_to_main; nortel_send_cmd "vlan"; nortel_send_cmd "ports $ports"; nortel_send_cmd "pvid $vlan_id"
}
nortel_tag_ports() {
    local vlan_id="$1" ports="$2"; echo "  -> TAGGING PORTS: VLAN=$vlan_id, Ports=$ports"
    nortel_go_to_main; nortel_send_cmd "vlan"; nortel_send_cmd "tagging $vlan_id"
    nortel_send_cmd "ports $ports"; nortel_send_cmd "tag"
}
provision_nortel() {
    local config_file="${CONFIG_FILE:-nortel_vlans.txt}"; [[ ! -f "$config_file" ]] && die "Config file not found: $config_file"

    echo "Connecting..."; stty -F "$SERIAL_DEVICE" 9600 -echo raw; exec 3<> "$SERIAL_DEVICE"

    # --- Improved Login Loop ---
    while true; do
        read -p "Enter Nortel username: " username; read -sp "Enter password: " password; echo

        # Wait for username prompt and send
        while read -t $TIMEOUT line <&3; do if [[ "$line" == *"User Name:"* ]]; then echo "$username" >&3; break; fi; done
        # Wait for password prompt and send
        while read -t $TIMEOUT line <&3; do if [[ "$line" == *"Password:"* ]]; then echo "$password" >&3; break; fi; done

        # Check for success or failure
        local login_success=false
        while read -t 3 line <&3; do
            line=$(echo "$line" | tr -d '\r')
            if [[ "$line" == *"Incorrect"* ]]; then
                echo "Login failed. Please try again."
                break # Breaks inner loop to retry credentials
            elif [[ "$line" == *"->"* ]]; then
                login_success=true
                break
            fi
        done

        if [[ "$login_success" = true ]]; then
            echo "Login successful."
            break # Breaks outer loop to continue with script
        fi
    done

    while IFS= read -r line; do
        [[ "$line" =~ ^# || -z "$line" ]] && continue; local vlan="" name="" ports="" tag=""
        IFS=',' read -r -a pairs <<< "$line"; for p in "${pairs[@]}"; do p=$(echo "$p"|tr -d ' '); k="${p%%=*}"; v="${p#*=}"; case "$k" in VLAN) vlan="$v";; NAME) name="$v";; PORTS) ports="$v";; TAG) tag="$v";; esac; done
        [[ -z "$vlan" || -z "$ports" ]] && { echo "WARNING: Invalid line: $line"; continue; }
        nortel_provision_vlan "$vlan" "$name"; nortel_assign_ports "$vlan" "$ports"
        if [[ -n "$tag" ]]; then nortel_tag_ports "$vlan" "$tag"; fi; echo "---"
    done < "$config_file"
    nortel_go_to_main; nortel_send_cmd "save"; echo "Configuration saved."; exec 3<&-
}

# --- Cisco-Specific Functions ---
cisco_send_cmd() {
    local cmd="$1"; echo " > SEND: [$cmd]"; echo "$cmd" >&3
    while read -t $TIMEOUT line <&3; do line=$(echo "$line"|tr -d '\r'); echo "[CISCO] $line"; if [[ "$line" == *">"* || "$line" == *"#"* ]]; then break; fi; done
}
provision_cisco_device() {
    local config_file="$2"; [[ ! -f "$config_file" ]] && die "Config file not found: $config_file"

    echo "Connecting..."; stty -F "$SERIAL_DEVICE" 9600 -echo raw; exec 3<> "$SERIAL_DEVICE"
    cisco_send_cmd "" # Get a prompt

    # --- Improved Login Loop ---
    while true; do
        read -sp "Enter Cisco enable password: " password; echo
        cisco_send_cmd "enable"
        cisco_send_cmd "$password"

        local login_success=false
        local failure_detected=false
        while read -t 3 line <&3; do
            line=$(echo "$line" | tr -d '\r')
            if [[ "$line" == *"% Bad secrets"* || "$line" == *"% Invalid input"* ]]; then
                failure_detected=true
                break
            elif [[ "$line" == *"#"* ]]; then
                login_success=true
                break
            fi
        done

        if [[ "$login_success" = true ]]; then
            echo "Login successful."
            break
        else
            echo "Login failed. Please try again."
            # Send newline to get back to a stable '>' prompt
            cisco_send_cmd ""
        fi
    done
    cisco_send_cmd "configure terminal"
    echo "Applying config from $config_file..."
    while IFS= read -r cmd; do [[ "$cmd" =~ ^# || -z "$cmd" ]] && continue; cisco_send_cmd "$cmd"; done < "$config_file"
    cisco_send_cmd "end"; cisco_send_cmd "write memory"; echo "Configuration saved."; exec 3<&-
}
provision_cisco_isr() { provision_cisco_device "ISR" "${CONFIG_FILE:-isr_vlans.txt}"; }
provision_cisco_asa() { provision_cisco_device "ASA" "${CONFIG_FILE:-asa_vlans.txt}"; }

# --- Main TUI & Logic ---
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --device) SERIAL_DEVICE="$2"; shift ;;
        --config) CONFIG_FILE="$2"; shift ;;
        *) die "Unknown parameter: $1" ;;
    esac; shift
done
[[ -z "$SERIAL_DEVICE" ]] && die "Usage: $0 --device <path> [--config <file>]"
while true; do
    print_header; echo "Targeting serial device: $SERIAL_DEVICE"
    echo "Select a device to provision: 1) Nortel 5520  2) Cisco ISR  3) Cisco ASA  q) Quit"
    read -p "Enter your choice: " choice
    case $choice in 1) provision_nortel; break;; 2) provision_cisco_isr; break;; 3) provision_cisco_asa; break;; q) break;; *) echo "Invalid option."; sleep 1;; esac
done
echo "Script finished."
exit 0
