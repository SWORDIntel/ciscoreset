#!/usr/bin/env bash
# Nortel 5520 Automated VLAN Provisioner
set -euo pipefail
IFS=$'\n\t'

# --- Configuration & Helpers ---
SERIAL_DEVICE=""
TIMEOUT=10
die() { echo "ERROR: $1" >&2; exit 1; }

# --- Menu Navigation ---
send_menu_command() {
    local cmd="$1"
    echo " > SEND: [$cmd]"; echo "$cmd" >&3
    while read -t $TIMEOUT line <&3; do
        line=$(echo "$line" | tr -d '\r')
        echo "[SWITCH] $line"
        if [[ "$line" == *"->"* ]]; then break; fi
    done
}
go_to_main_menu() { for _ in {1..5}; do send_menu_command "q"; done; }

# --- Action Functions ---
provision_vlan() {
    local vlan_id="$1"; local vlan_name="$2"
    echo "PROVISIONING VLAN: ID=$vlan_id, Name=$vlan_name"
    go_to_main_menu; send_menu_command "vlan"; send_menu_command "create $vlan_id"
    if [[ -n "$vlan_name" ]]; then send_menu_command "name $vlan_id $vlan_name"; fi
}
assign_ports_to_vlan() {
    local vlan_id="$1"; local port_range="$2"
    echo "  -> ASSIGNING PORTS: VLAN=$vlan_id, Ports=$port_range"
    go_to_main_menu; send_menu_command "vlan"; send_menu_command "ports $port_range"
    send_menu_command "pvid $vlan_id"
}
tag_ports_for_vlan() {
    local vlan_id="$1"; local port_range="$2"
    echo "  -> TAGGING PORTS: VLAN=$vlan_id, Ports=$port_range"
    go_to_main_menu; send_menu_command "vlan"; send_menu_command "tagging $vlan_id"
    send_menu_command "ports $port_range"; send_menu_command "tag"
}

# --- Parser ---
parse_vlan_config() {
    local config_file="vlan_config.txt"
    [[ ! -f "$config_file" ]] && die "Config file not found: $config_file"
    echo "Parsing $config_file..."
    while IFS= read -r line; do
        [[ "$line" =~ ^# || -z "$line" ]] && continue
        local vlan="" name="" ports="" tag=""
        IFS=',' read -r -a pairs <<< "$line"
        for pair in "${pairs[@]}"; do
            pair=$(echo "$pair" | tr -d ' '); key="${pair%%=*}"; value="${pair#*=}"
            case "$key" in
                VLAN) vlan="$value" ;; NAME) name="$value" ;;
                PORTS) ports="$value" ;; TAG) tag="$value" ;;
            esac
        done
        if [[ -z "$vlan" || -z "$ports" ]]; then echo "WARNING: Invalid line: $line"; continue; fi
        provision_vlan "$vlan" "$name"; assign_ports_to_vlan "$vlan" "$ports"
        if [[ -n "$tag" ]]; then tag_ports_for_vlan "$vlan" "$tag"; fi; echo "---"
    done < "$config_file"
}

# --- Main Logic ---
while [[ "$#" -gt 0 ]]; do
    case $1 in --device) SERIAL_DEVICE="$2"; shift ;; *) die "Unknown parameter: $1" ;; esac; shift
done
[[ -z "$SERIAL_DEVICE" ]] && die "Usage: $0 --device <path>"

read -p "Enter switch username: " username; read -sp "Enter switch password: " password; echo
echo "Initializing serial connection to $SERIAL_DEVICE..."; stty -F "$SERIAL_DEVICE" 9600 -echo raw; exec 3<> "$SERIAL_DEVICE"

echo "Waiting for login prompt..."
while read -t $TIMEOUT line <&3; do
    line=$(echo "$line" | tr -d '\r'); echo "[SWITCH] $line"
    if [[ "$line" == *"User Name:"* ]]; then echo "Sending username..."; echo "$username" >&3; break; fi
done
while read -t $TIMEOUT line <&3; do
    line=$(echo "$line" | tr -d '\r'); echo "[SWITCH] $line"
    if [[ "$line" == *"Password:"* ]]; then echo "Sending password..."; echo "$password" >&3; break; fi
done
while read -t $TIMEOUT line <&3; do
    line=$(echo "$line" | tr -d '\r'); echo "[SWITCH] $line"
    if [[ "$line" == *"->"* ]]; then echo "Login successful."; break; fi
done

echo "Proceeding with VLAN provisioning..."
parse_vlan_config

go_to_main_menu; send_menu_command "save"; echo "Configuration saved."
echo "Script finished."; exec 3<&-
exit 0
