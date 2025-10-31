#!/bin/bash

# Cisco ISR 4321 Recovery and Management Tool

# --- Default Configuration ---
SERIAL_DEVICE="/dev/ttyS0"
BAUD_RATE="9600"
TIMEOUT=300 # 5-minute timeout for lengthy operations like TFTP

# --- TUI & Helper Functions ---

function print_header() {
    clear
    echo "==============================================="
    echo "   Cisco ISR 4321 Recovery & Management Tool"
    echo "==============================================="
    echo
}

function show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  --device <path>   Path to the serial device (default: /dev/ttyS0)"
    echo "  --baud <rate>     Baud rate for the serial connection (default: 9600)"
    echo "  --help            Display this help message"
}

# Reads from the serial port until a rommon prompt is detected
function read_until_prompt() {
    while read -t 5 line <&3; do
        line=$(echo "$line" | tr -d '\r')
        echo "[ROUTER] $line"
        if [[ "$line" == *"rommon"* ]]; then
            break
        fi
    done
}

# Sends a command to the router OS (not rommon) and waits for a prompt
function send_command() {
    local cmd="$1"
    echo "$cmd" >&3
    while read -t 10 line <&3; do
        if [[ "$line" == *">"* || "$line" == *"#"* ]]; then
            break
        fi
    done
}

# --- Menu Functions ---

function menu_reset_password() {
    print_header
    echo "--- Starting Password Reset ---"
    read -p "This will reset the router. Are you sure? (y/n) " confirm
    [[ "$confirm" != "y" ]] && return

    echo "Setting config register to 0x2142 and resetting..."
    echo "confreg 0x2142" >&3; sleep 1
    echo "reset" >&3

    echo "Waiting for router to reboot..."
    local password_configured=false
    while read -t $TIMEOUT line <&3; do
        line=$(echo "$line" | tr -d '\r'); echo "[ROUTER] $line"
        if [[ "$line" == *"Would you like to enter the initial configuration dialog?"* ]]; then
            echo "Bypassing initial config..."
            echo "no" >&3
        fi
        if [[ "$line" == *">"* && "$password_configured" == false ]]; then
            echo "Router prompt detected. Configuring new password..."
            read -sp "Enter the new enable secret: " new_password; echo
            send_command "enable"
            send_command "copy startup-config running-config"; send_command ""
            send_command "configure terminal"
            send_command "enable secret $new_password"
            send_command "config-register 0x2102"
            send_command "end"; send_command "write memory"
            password_configured=true
            echo "Password reset complete. Please manually reset the router to return to ROMMON."
            read -n 1 -s -r -p "Press any key to continue..."
            return
        fi
    done
}

function menu_change_boot_vars() {
    print_header
    echo "--- Change Boot Variables ---"
    echo "Current ROMMON environment variables:"; echo "set" >&3; read_until_prompt
    read -p "Enter variable to set (or Enter to return): " var_name
    [[ -z "$var_name" ]] && return
    read -p "Enter new value for $var_name: " var_value
    echo "Setting $var_name to $var_value..."; echo "$var_name $var_value" >&3; read_until_prompt
    echo "Saving changes..."; echo "sync" >&3; read_until_prompt
    echo "Variable '$var_name' has been set. A 'reset' may be required."
    read -n 1 -s -r -p "Press any key to return..."
}

function menu_load_firmware() {
    print_header
    echo "--- Load Firmware from TFTP ---"
    read -p "Enter TFTP Server IP: " tftp_server
    read -p "Enter Router Management IP: " router_ip
    read -p "Enter Router Subnet Mask: " subnet_mask
    read -p "Enter Default Gateway IP: " gateway_ip
    read -p "Enter Firmware Filename: " firmware_file
    [[ -z "$tftp_server" || -z "$router_ip" || -z "$firmware_file" ]] && { echo "Error: Required fields missing."; sleep 2; return; }

    echo "Configuring network variables...";
    echo "IP_ADDRESS=$router_ip" >&3; read_until_prompt
    echo "IP_SUBNET_MASK=$subnet_mask" >&3; read_until_prompt
    echo "DEFAULT_GATEWAY=$gateway_ip" >&3; read_until_prompt
    echo "TFTP_SERVER=$tftp_server" >&3; read_until_prompt
    echo "TFTP_FILE=$firmware_file" >&3; read_until_prompt

    read -n 1 -s -r -p "Press any key to start the TFTP download..."
    echo "Starting TFTP download..."; echo "tftpdnld -r" >&3

    while read -t 20 line <&3; do
        echo "[ROUTER] $line"
        if [[ "$line" == *"Invoke this command for"* ]]; then
            echo "Confirmation prompt detected. Sending 'y'..."; echo "y" >&3
            break
        fi
    done
    echo "Firmware download is in progress. The router will reboot if successful."
    read -n 1 -s -r -p "Press any key once complete..."
}

function menu_raw_shell() {
    print_header
    echo "--- Raw Shell Mode ---"; echo "Type 'exit' to return."
    cat <&3 & CAT_PID=$!
    while read -p "rommon> " user_cmd; do
        [[ "$user_cmd" == "exit" ]] && break
        echo "$user_cmd" >&3
    done
    kill $CAT_PID; wait $CAT_PID 2>/dev/null
}

# --- Main Logic ---

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --device) SERIAL_DEVICE="$2"; shift ;;
        --baud) BAUD_RATE="$2"; shift ;;
        --help) show_help; exit 0 ;;
        *) echo "Unknown parameter: $1"; show_help; exit 1 ;;
    esac
    shift
done

print_header
echo "--- Hardware Setup ---"; echo "Device: $SERIAL_DEVICE | Baud: $BAUD_RATE"
read -n 1 -s -r -p "Connect serial adapter and press any key to begin..."

print_header
echo "--- Initializing Connection ---"; echo "Please power on the Cisco router now."
stty -F "$SERIAL_DEVICE" "$BAUD_RATE" -echo raw; exec 3<> "$SERIAL_DEVICE"

(for _ in {1..15}; do python -c "import termios, sys; termios.tcsendbreak(sys.stdout.fileno(), 0)" >&3; sleep 2; done) & BREAK_PID=$!

in_rommon=false
while read -t $TIMEOUT line <&3; do
    line=$(echo "$line" | tr -d '\r'); echo "[ROUTER] $line"
    if [[ "$line" == *"rommon"* ]]; then
        in_rommon=true; kill $BREAK_PID; wait $BREAK_PID 2>/dev/null
        echo "ROMMON prompt detected."; sleep 1; break
    fi
done

kill $BREAK_PID 2>/dev/null
if [ "$in_rommon" = false ]; then
    echo "Error: Timed out waiting for ROMMON prompt."; exec 3<&-; exit 1
fi

while true; do
    print_header
    echo "Successfully entered ROMMON mode on $SERIAL_DEVICE"
    echo "Select an option:"
    echo "  1) Reset Password"; echo "  2) Change Boot Variables"
    echo "  3) Load Firmware from TFTP"; echo "  4) Raw Shell"
    echo "  q) Quit"
    read -p "Enter your choice: " choice
    case $choice in
        1) menu_reset_password; break ;;
        2) menu_change_boot_vars ;;
        3) menu_load_firmware; break ;;
        4) menu_raw_shell ;;
        q) break ;;
        *) echo "Invalid option."; sleep 1 ;;
    esac
done

echo "Exiting."; exec 3<&-; exit 0
