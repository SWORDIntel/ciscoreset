#!/bin/bash

# Cisco ISR 4321 Password Recovery Script

# --- Configuration ---
SERIAL_DEVICE="/dev/ttyS0"
BAUD_RATE="9600"
TIMEOUT=180 # 3-minute timeout for the whole process

# --- TUI Functions ---
function print_header() {
    clear
    echo "==============================================="
    echo "   Cisco ISR 4321 Password Recovery Utility"
    echo "==============================================="
    echo
}

function press_any_key() {
    read -n 1 -s -r -p "Press any key to continue..."
}

# --- Serial Communication Functions ---
# Sends a command and waits for the next prompt
function send_command() {
    local cmd="$1"
    echo "Sending command: $cmd"
    echo "$cmd" >&3
    # Wait for a prompt before proceeding
    while read -t 10 line <&3; do
        if [[ "$line" == *">"* || "$line" == *"#"* ]]; then
            break
        fi
    done
}

# --- Main Logic ---

print_header
echo "--- Hardware Setup ---"
echo "Please follow these steps to connect your USB-to-TTL adapter:"
echo "1. Connect the GND pin of your adapter to a ground point on the router's PCB."
echo "2. Ensure your serial device is correctly set to '$SERIAL_DEVICE'."
echo "3. The script will use a baud rate of $BAUD_RATE."
echo "4. Power on the router ONLY when instructed."
echo "DO NOT connect the VCC pin from your adapter to the router."
echo
press_any_key

print_header
echo "--- Starting Recovery Process ---"
echo "Please power on the Cisco router now."
echo "The script will attempt to send a BREAK signal multiple times."
echo

# Set up the serial port
stty -F "$SERIAL_DEVICE" "$BAUD_RATE" -echo raw
exec 3<> "$SERIAL_DEVICE"

# Send BREAK signals in the background for 20 seconds
(
    for _ in {1..10}; do
        # Use python to send break on the file descriptor
        python -c "import termios, sys; termios.tcsendbreak(sys.stdout.fileno(), 0)" >&3
        sleep 2
    done
) &
BREAK_PID=$!

# State machine variables
in_rommon=false
password_configured=false

# Main loop to read from device
while read -t $TIMEOUT line <&3; do
    line=$(echo "$line" | tr -d '\r')
    echo "[ROUTER] $line"

    # 1. Detect rommon prompt
    if [[ "$line" == *"rommon"* && "$in_rommon" == false ]]; then
        in_rommon=true
        kill $BREAK_PID # Stop sending break signals
        wait $BREAK_PID 2>/dev/null
        echo "ROMMON prompt detected. Sending recovery commands..."
        sleep 1
        echo "confreg 0x2142" >&3
        sleep 1
        echo "reset" >&3
    fi

    # 2. Detect post-recovery boot and configure password
    if [[ "$line" == *"Would you like to enter the initial configuration dialog?"* ]]; then
        echo "System has booted. Bypassing initial config..."
        echo "no" >&3
    fi

    if [[ "$line" == *">"* && "$in_rommon" == true && "$password_configured" == false ]]; then
        echo "Router prompt detected. Configuring new password..."

        # Prompt for new password
        read -sp "Enter the new enable secret: " new_password
        echo

        # Send configuration commands, waiting for prompts
        send_command "enable"
        send_command "copy startup-config running-config"
        send_command "" # Confirm destination filename
        send_command "configure terminal"
        send_command "enable secret $new_password"
        send_command "config-register 0x2102"
        send_command "end"
        send_command "write memory"

        password_configured=true
        echo "Password reset complete. The process is finished."
        break
    fi
done

# Timeout check
if [ $? -ne 0 ]; then
    echo "Error: Timed out waiting for a response from the device."
fi

# --- Cleanup ---
kill $BREAK_PID 2>/dev/null
wait $BREAK_PID 2>/dev/null
exec 3<&-

exit 0
