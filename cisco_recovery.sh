#!/usr/bin/env bash
# Cisco & Generic Embedded Advanced Recovery Tool v2.3
#
# A TUI-based toolkit for automating password recovery, JTAG exploitation,
# and firmware analysis on Cisco and other embedded devices.

# Exit on error, undefined variable, or pipe failure
set -euo pipefail

# --- Global Variables ---
# Configuration and Logging
CONFIG_FILE="~/.config/cisco_recovery/config.ini"
LOG_FILE="/var/log/cisco_recovery.log"
SESSION_DIR=""
VERBOSE=0
OPENOCD_SCRIPT_PATH="/usr/share/openocd/scripts" # Default path, can be overridden in config
# Device-specific settings
PLATFORM="auto" # 'auto', 'isr', 'asa', etc.
JTAG_ADAPTER="auto" # 'auto', 'ftdi', 'jlink', etc.
TARGET_ARCH="auto" # 'auto', 'arm', 'mips', etc.

# --- Functions ---

# Trap for cleaning up temporary files on exit
cleanup() {
    echo "Cleaning up and exiting..."
    if [ -n "$SESSION_DIR" ] && [ -d "$SESSION_DIR" ]; then
        log_message "INFO" "Removing session directory: $SESSION_DIR"
        rm -rf "$SESSION_DIR"
    fi
    # Restore terminal settings on exit
    stty echo
    exit 0
}

# Setup signal traps
trap cleanup SIGINT SIGTERM EXIT

# Load configuration from file
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        echo "Configuration loaded from $CONFIG_FILE"
    else
        echo "No configuration file found at $CONFIG_FILE. Using defaults."
    fi
}

# --- Utility Functions ---

# Prints a standardized header for TUI menus
print_header() {
    clear
    echo "================================================="
    echo "  Cisco & Generic Embedded Advanced Recovery Tool"
    echo "================================================="
    echo
}

# Logs a message to the LOG_FILE with a timestamp
log_message() {
    local type="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$type] $message" | tee -a "$LOG_FILE"
    if [ "$VERBOSE" -eq 1 ] && [ "$type" != "DEBUG" ]; then
        echo "[$timestamp] [$type] $message"
    fi
}

# --- Core Logic & Menus ---

detect_platform_auto() {
    log_message "INFO" "Starting platform auto-detection."
    echo "Analyzing system logs for known serial devices..."

    # Check dmesg for FTDI serial converters, often used for Cisco consoles
    if dmesg | grep -q "FTDI USB Serial Device converter now attached"; then
        # Check for strings that might indicate a specific Cisco device type
        # This is a heuristic and might need to be adjusted
        if dmesg | grep -q "ISR"; then
            PLATFORM="isr"
            log_message "INFO" "Heuristic match: Cisco ISR detected via dmesg."
            echo "Platform detected: Cisco ISR (heuristic)"
        elif dmesg | grep -q "ASA"; then
            PLATFORM="asa"
            log_message "INFO" "Heuristic match: Cisco ASA detected via dmesg."
            echo "Platform detected: Cisco ASA (heuristic)"
        else
            PLATFORM="unknown_cisco"
            log_message "INFO" "Generic Cisco-like serial device detected."
            echo "Generic Cisco serial device detected."
        fi
    else
        log_message "WARN" "No known Cisco serial device was automatically detected."
        echo "No known Cisco device found. Please set it manually."
    fi
    sleep 2
}

detect_platform() {
    while true; do
        print_header
        echo "--- Platform Detection ---"
        echo "  Current Platform: $PLATFORM"
        echo
        echo "  1) Auto-detect Platform"
        echo "  2) Set to Cisco ISR"
        echo "  3) Set to Cisco ASA"
        echo "  4) Set to Nortel Switch"
        echo "  b) Back to Main Menu"
        echo
        read -r -p "Choose an option: " choice

        case "$choice" in
            1) detect_platform_auto ;;
            2) PLATFORM="isr" ;;
            3) PLATFORM="asa" ;;
            4) PLATFORM="nortel" ;;
            b) break ;;
            *) echo "Invalid option." && sleep 1 ;;
        esac
    done
}

detect_jtag_adapter_auto() {
    log_message "INFO" "Starting JTAG adapter auto-detection."
    echo "Scanning USB devices for known JTAG adapters..."

    if lsusb -d 0403:6010; then
        JTAG_ADAPTER="ftdi"
        log_message "INFO" "FTDI adapter (FT2232/FT4232) detected."
        echo "Adapter detected: FTDI"
    elif lsusb -d 1366:0101; then
        JTAG_ADAPTER="jlink"
        log_message "INFO" "SEGGER J-Link adapter detected."
        echo "Adapter detected: J-Link"
    elif lsusb -d 1a86:7523; then
        JTAG_ADAPTER="ch341"
        log_message "INFO" "CH341 adapter detected."
        echo "Adapter detected: CH341"
    else
        log_message "WARN" "No known JTAG adapter was automatically detected."
        echo "No known adapter found. Please set it manually."
    fi
    sleep 2
}

detect_jtag_adapter() {
    while true; do
        print_header
        echo "--- JTAG Adapter Detection ---"
        echo "  Current Adapter: $JTAG_ADAPTER"
        echo
        echo "  1) Auto-detect Adapter"
        echo "  2) Set to FTDI (e.g., FT232H)"
        echo "  3) Set to J-Link"
        echo "  4) Set to CH341"
        echo "  b) Back"
        echo
        read -r -p "Choose an option: " choice

        case "$choice" in
            1) detect_jtag_adapter_auto ;;
            2) JTAG_ADAPTER="ftdi" ;;
            3) JTAG_ADAPTER="jlink" ;;
            4) JTAG_ADAPTER="ch341" ;;
            b) break ;;
            *) echo "Invalid option." && sleep 1 ;;
        esac
    done
}


recover_cisco_password() {
    print_header
    echo "--- Cisco Password Recovery ---"

    if ! command -v expect &> /dev/null; then
        log_message "ERROR" "'expect' command not found. This feature cannot run."
        echo "ERROR: 'expect' is required for this feature but is not installed."
        echo "Please install 'expect' (e.g., 'sudo apt-get install expect') and try again."
        sleep 4
        return
    fi

    local serial_device
    read -r -p "Enter the serial device path (e.g., /dev/ttyUSB0): " serial_device
    if [ ! -c "$serial_device" ]; then
        log_message "ERROR" "Serial device not found at '$serial_device'."
        echo "ERROR: Character device not found at '$serial_device'."
        sleep 2
        return
    fi

    log_message "INFO" "Starting password recovery on $serial_device for platform $PLATFORM."

    local expect_script
    expect_script=$(mktemp)

    # Create the expect script
    cat > "$expect_script" <<- EOL
        #!/usr/bin/expect -f
        set timeout 30
        set serial_port "$serial_device"

        # Configure the serial port
        stty -F \$serial_port 9600 raw -echo

        spawn screen \$serial_port 9600

        puts "---"
        puts "Please power-cycle the target device now."
        puts "The script will send a BREAK signal in 15 seconds."
        puts "---"
        sleep 15

        # In screen, the BREAK signal is Ctrl-A, Ctrl-B
        send "\\001"
        sleep 0.1
        send "b"

        expect {
            "rommon 1 >" {
                send "confreg 0x2142\\r"
            }
            timeout {
                puts "Timed out waiting for rommon prompt. Recovery failed."
                exit 1
            }
        }

        expect "rommon 2 >"
        send "reset\\r"

        expect eof
EOL

    chmod +x "$expect_script"

    echo "Launching recovery script. Please follow the prompts."
    sleep 2

    # Run the expect script in the current terminal
    "$expect_script"

    log_message "INFO" "Password recovery script finished."
    echo "Recovery process complete. The device will reboot and bypass the startup-config."
    echo "You can now configure a new password."

    rm "$expect_script"
    read -r -p "Press Enter to continue..."
}

menu_password_recovery() {
    while true; do
        print_header
        echo "--- Cisco Password Recovery ---"
        echo "  Current Platform: $PLATFORM"
        echo
        echo "  1) Initiate Password Reset (ISR/ASA)"
        echo "  b) Back to Main Menu"
        echo
        read -r -p "Choose an option: " choice

        case "$choice" in
            1) recover_cisco_password ;;
            b) break ;;
            *) echo "Invalid option." && sleep 1 ;;
        esac
    done
}

exploit_via_jtag() {
    local action="$1"
    print_header
    echo "--- JTAG Exploitation: ${action} ---"

    if ! command -v openocd &> /dev/null; then
        log_message "ERROR" "'openocd' not found, which is required for JTAG."
        echo "ERROR: 'openocd' is not installed. Please install it to use this feature."
        sleep 3
        return
    fi
    if [ "$JTAG_ADAPTER" == "auto" ] || [ "$TARGET_ARCH" == "auto" ]; then
        log_message "ERROR" "JTAG adapter or target architecture not set."
        echo "ERROR: Please configure the JTAG adapter and target architecture first."
        sleep 3
        return
    fi

    local ocd_interface_cfg="${OPENOCD_SCRIPT_PATH}/interface/${JTAG_ADAPTER}.cfg"
    # NOTE: This is a simplification. Real-world targets often need highly specific scripts.
    local ocd_target_cfg="${OPENOCD_SCRIPT_PATH}/target/swj-dp.cfg"

    local output_file
    local openocd_cmd

    case "$action" in
        "scan")
            openocd_cmd=("openocd" "-f" "$ocd_interface_cfg" "-f" "$ocd_target_cfg" "-c" "init" "-c" "jtag_scan" "-c" "exit")
            ;;
        "dump_ram")
            read -r -p "Enter output file path for RAM dump (e.g., /tmp/ram.bin): " output_file
            read -r -p "Enter memory address to dump from (hex): " mem_addr
            read -r -p "Enter size to dump (bytes): " mem_size
            openocd_cmd=("openocd" "-f" "$ocd_interface_cfg" "-f" "$ocd_target_cfg" "-c" "init" "-c" "halt" "-c" "dump_image \"$output_file\" $mem_addr $mem_size" "-c" "resume" "-c" "exit")
            ;;
        "extract_flash")
            read -r -p "Enter output file path for flash dump (e.g., /tmp/flash.bin): " output_file
            # This is highly target-specific. The command below is a generic example.
            openocd_cmd=("openocd" "-f" "$ocd_interface_cfg" "-f" "$ocd_target_cfg" "-c" "init" "-c" "halt" "-c" "flash read_bank 0 \"$output_file\" 0 0" "-c" "resume" "-c" "exit")
            ;;
        *)
            log_message "ERROR" "Unknown JTAG action requested: $action"
            echo "Internal error: Unknown action '$action'."
            sleep 2
            return
            ;;
    esac

    log_message "INFO" "Executing JTAG action: $action"
    echo "Executing OpenOCD command... Check log for detailed output."
    log_message "CMD" "${openocd_cmd[*]}"

    if ! output=$("${openocd_cmd[@]}" 2>&1); then
        log_message "ERROR" "OpenOCD command failed. Output: $output"
        echo "ERROR: OpenOCD command failed. See log at $LOG_FILE for details."
        sleep 3
    else
        log_message "INFO" "OpenOCD action '$action' successful. Output: $output"
        echo "SUCCESS: JTAG action '$action' completed."
        sleep 3
    fi
}

menu_jtag_exploitation() {
    while true; do
        print_header
        echo "--- JTAG Exploitation ---"
        echo "  Current Adapter: $JTAG_ADAPTER"
        echo "  Current Architecture: $TARGET_ARCH"
        echo
        echo "  1) Scan JTAG Chain"
        echo "  2) Dump Memory (RAM)"
        echo "  3) Extract Firmware (Flash)"
        echo "  b) Back to Main Menu"
        echo
        read -r -p "Choose an option: " choice

        case "$choice" in
            1) exploit_via_jtag "scan" ;;
            2) exploit_via_jtag "dump_ram" ;;
            3) exploit_via_jtag "extract_flash" ;;
            b) break ;;
            *) echo "Invalid option." && sleep 1 ;;
        esac
    done
}
analyze_memory_dump() {
    local action="$1"
    print_header
    echo "--- Memory Dump Analysis: ${action} ---"

    read -r -p "Enter the path to the memory dump file: " dump_file
    if [ ! -f "$dump_file" ]; then
        log_message "ERROR" "Memory dump file not found at '$dump_file'."
        echo "ERROR: File not found at '$dump_file'."
        sleep 2
        return
    fi

    log_message "INFO" "Starting memory analysis ('$action') on file $dump_file."
    echo "Analyzing file... This may take a moment."

    local report_file="${SESSION_DIR}/memory_analysis_report.txt"
    echo "Analysis Report for $dump_file" > "$report_file"
    echo "Type: $action" >> "$report_file"
    echo "========================================" >> "$report_file"

    case "$action" in
        "credentials")
            echo "Searching for potential credentials (passwords, keys, etc.)..."
            {
                echo -e "\n--- Potential Credentials ---\n"
                strings "$dump_file" | grep -iE 'password|secret|apikey|privatekey|token'
            } >> "$report_file"
            ;;
        "bootloader")
            echo "Scanning for common bootloader signatures..."
            {
                echo -e "\n--- Bootloader Signatures ---\n"
                # U-Boot
                if hexdump -C "$dump_file" | grep -q '27 05 19 56'; then
                    echo "U-Boot signature (27 05 19 56) found."
                fi
                # CFE
                if strings "$dump_file" | grep -q "CFE boot loader"; then
                    echo "CFE bootloader string found."
                fi
            } >> "$report_file"
            ;;
        *)
            log_message "ERROR" "Unknown memory analysis action: $action"
            echo "Internal error: Unknown action '$action'."
            sleep 2
            return
            ;;
    esac

    log_message "INFO" "Memory analysis complete. Report generated at $report_file."
    echo "Analysis complete. Displaying report:"
    echo "---------------------------------------"
    cat "$report_file"
    echo "---------------------------------------"
    echo "Full report saved to $report_file"
    read -r -p "Press Enter to continue..."
}

menu_memory_analysis() {
    while true; do
        print_header
        echo "--- Memory Analysis ---"
        echo "  1) Analyze Memory Dump for Credentials"
        echo "  2) Scan for Bootloader Signatures"
        echo "  b) Back to Main Menu"
        echo
        read -r -p "Choose an option: " choice

        case "$choice" in
            1) analyze_memory_dump "credentials" ;;
            2) analyze_memory_dump "bootloader" ;;
            b) break ;;
            *) echo "Invalid option." && sleep 1 ;;
        esac
    done
}

jtag_flash_write() {
    print_header
    echo "--- JTAG Flash Write (DANGEROUS) ---"
    echo
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "  WARNING: THIS IS AN EXTREMELY DANGEROUS OPERATION."
    echo "  Writing the wrong firmware can permanently brick your device."
    echo "  You assume all risk. Double-check your settings."
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo
    echo "  - Target Platform: $PLATFORM"
    echo "  - JTAG Adapter:    $JTAG_ADAPTER"
    echo "  - Target Arch:     $TARGET_ARCH"
    echo

    read -r -p "Type 'confirm' to proceed: " confirmation
    if [[ "$confirmation" != "confirm" ]]; then
        log_message "INFO" "JTAG flash write cancelled by user."
        echo "Flash write cancelled."
        sleep 2
        return
    fi

    read -r -p "Enter the full path to the firmware image (.bin): " firmware_path
    if [ ! -f "$firmware_path" ]; then
        log_message "ERROR" "JTAG flash write failed: file not found at '$firmware_path'."
        echo "ERROR: Firmware file not found at '$firmware_path'."
        sleep 2
        return
    fi

    log_message "INFO" "Starting JTAG flash write for firmware: $firmware_path."
    echo "Preparing to flash. This is your final chance to abort."
    echo "Press Ctrl+C to cancel, or Enter to continue..."
    read -r

    local ocd_interface_cfg="${OPENOCD_SCRIPT_PATH}/interface/${JTAG_ADAPTER}.cfg"
    # This is still a simplification; a real target may need a more specific file.
    local ocd_target_cfg="${OPENOCD_SCRIPT_PATH}/target/swj-dp.cfg"

    if [ ! -f "$ocd_interface_cfg" ] || [ ! -f "$ocd_target_cfg" ]; then
        log_message "ERROR" "OpenOCD config files not found. Check OPENOCD_SCRIPT_PATH."
        echo "ERROR: OpenOCD config files not found. Searched in '$OPENOCD_SCRIPT_PATH'."
        sleep 3
        return
    fi

    local openocd_cmd=(
        "openocd"
        "-f" "$ocd_interface_cfg"
        "-f" "$ocd_target_cfg"
        "-c" "init"
        "-c" "halt"
        # The 'program' command is a high-level abstraction that handles erasing, writing, and verifying.
        "-c" "program \"$firmware_path\" verify reset exit"
    )

    log_message "CMD" "${openocd_cmd[*]}"
    echo "Executing OpenOCD. The device will be flashed and reset. See log for details."

    if ! output=$("${openocd_cmd[@]}" 2>&1); then
        log_message "ERROR" "OpenOCD flash write failed. Output: $output"
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        echo "   ERROR: OPENOCD COMMAND FAILED."
        echo "   The device may be in an inconsistent state."
        echo "   See log at $LOG_FILE for details."
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        read -r -p "Press Enter to return to the menu..."
    else
        log_message "INFO" "OpenOCD flash write successful. Output: $output"
        echo "---"
        echo " SUCCESS: Flash write completed and verified."
        echo " The device has been reset."
        echo "---"
        read -r -p "Press Enter to continue..."
    fi
}

menu_firmware_manipulation() {
    while true; do
        print_header
        echo "--- Firmware Manipulation ---"
        echo "  1) Extract Firmware (JTAG)"
        echo "  2) Flash Image to Device (DANGEROUS)"
        echo "  b) Back to Main Menu"
        echo
        read -r -p "Choose an option: " choice

        case "$choice" in
            1) exploit_via_jtag "extract_flash" ;;
            2) jtag_flash_write ;;
            b) break ;;
            *) echo "Invalid option." && sleep 1 ;;
        esac
    done
}

menu_set_architecture() {
    while true; do
        print_header
        echo "--- Set Target Architecture ---"
        echo "  Current Architecture: $TARGET_ARCH"
        echo
        echo "  1) Set to ARM"
        echo "  2) Set to MIPS"
        echo "  b) Back"
        echo
        read -r -p "Choose an option: " choice

        case "$choice" in
            1) TARGET_ARCH="arm" ;;
            2) TARGET_ARCH="mips" ;;
            b) break ;;
            *) echo "Invalid option." && sleep 1 ;;
        esac
    done
}

menu_platform_jtag_config() {
    while true; do
        print_header
        echo "--- Platform and JTAG Configuration ---"
        echo "  Current Platform: $PLATFORM"
        echo "  Current JTAG Adapter: $JTAG_ADAPTER"
        echo "  Current Architecture: $TARGET_ARCH"
        echo
        echo "  1) Detect Platform"
        echo "  2) Detect JTAG Adapter"
        echo "  3) Set Target Architecture"
        echo "  b) Back to Main Menu"
        echo
        read -r -p "Choose an option: " choice

        case "$choice" in
            1) detect_platform ;;
            2) detect_jtag_adapter ;;
            3) menu_set_architecture ;;
            b) break ;;
            *) echo "Invalid option." && sleep 1 ;;
        esac
    done
}

# Main menu for the TUI
main_menu() {
    while true; do
        print_header
        echo "--- Main Menu ---"
        echo "  1) Platform and JTAG Configuration"
        echo "  2) Cisco Password Recovery"
        echo "  3) JTAG Exploitation"
        echo "  4) Memory Analysis"
        echo "  5) Firmware Manipulation"
        echo "  b) Exit"
        echo
        read -r -p "Choose an option: " choice

        case "$choice" in
            1) menu_platform_jtag_config ;;
            2) menu_password_recovery ;;
            3) menu_jtag_exploitation ;;
            4) menu_memory_analysis ;;
            5) menu_firmware_manipulation ;;
            b) break ;;
            *) echo "Invalid option. Please try again." && sleep 1 ;;
        esac
    done
}

# --- Main Execution ---

# Entry point of the script
main() {
    # Create log file if it doesn't exist
    touch "$LOG_FILE" || { echo "ERROR: Cannot create log file at $LOG_FILE. Exiting."; exit 1; }
    log_message "INFO" "Script started."

    # Create session directory
    SESSION_DIR=$(mktemp -d)
    log_message "INFO" "Session directory created at $SESSION_DIR."

    load_config
    main_menu
}

# Call the main function with all script arguments
main "$@"
