#!/usr/bin/env bash
# Cisco & Generic Embedded Advanced Recovery Tool v2.6
#
# A TUI-based toolkit for automating password recovery, JTAG exploitation,
# JTAG cable assisted recovery, and firmware analysis on Cisco and other embedded devices.

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

# --- JTAG Cable Assisted Recovery Functions ---

jtag_test_connection() {
    print_header
    echo "--- JTAG Cable Connection Test ---"
    echo

    if ! command -v openocd &> /dev/null; then
        log_message "ERROR" "'openocd' not found."
        echo "ERROR: 'openocd' is not installed. Please install it to use this feature."
        sleep 3
        return
    fi

    if [ "$JTAG_ADAPTER" == "auto" ]; then
        log_message "ERROR" "JTAG adapter not set."
        echo "ERROR: Please configure the JTAG adapter first."
        sleep 3
        return
    fi

    local ocd_interface_cfg="${OPENOCD_SCRIPT_PATH}/interface/${JTAG_ADAPTER}.cfg"

    if [ ! -f "$ocd_interface_cfg" ]; then
        log_message "ERROR" "OpenOCD interface config not found: $ocd_interface_cfg"
        echo "ERROR: Interface config file not found. Check OPENOCD_SCRIPT_PATH."
        sleep 3
        return
    fi

    echo "Testing JTAG cable connection..."
    echo "Adapter: $JTAG_ADAPTER"
    echo

    local openocd_cmd=(
        "openocd"
        "-f" "$ocd_interface_cfg"
        "-c" "adapter speed 1000"
        "-c" "init"
        "-c" "scan_chain"
        "-c" "exit"
    )

    log_message "INFO" "Running JTAG connection test..."
    log_message "CMD" "${openocd_cmd[*]}"

    local test_output
    if test_output=$("${openocd_cmd[@]}" 2>&1); then
        log_message "INFO" "JTAG connection test output: $test_output"
        echo "------- Connection Test Results -------"
        echo "$test_output" | grep -E "(Info|Error|Warn|JTAG|TAP)" || echo "$test_output"
        echo "---------------------------------------"

        if echo "$test_output" | grep -q "JTAG tap:"; then
            echo
            echo "SUCCESS: JTAG TAP detected! Cable connection is working."
        else
            echo
            echo "WARNING: No JTAG TAP detected. Check your connections."
        fi
    else
        log_message "ERROR" "JTAG connection test failed: $test_output"
        echo "ERROR: Connection test failed. Output:"
        echo "$test_output"
    fi

    echo
    read -r -p "Press Enter to continue..."
}

jtag_detect_taps() {
    print_header
    echo "--- JTAG TAP Detection & Diagnostics ---"
    echo

    if ! command -v openocd &> /dev/null; then
        log_message "ERROR" "'openocd' not found."
        echo "ERROR: 'openocd' is not installed."
        sleep 3
        return
    fi

    if [ "$JTAG_ADAPTER" == "auto" ]; then
        log_message "ERROR" "JTAG adapter not set."
        echo "ERROR: Please configure the JTAG adapter first."
        sleep 3
        return
    fi

    local ocd_interface_cfg="${OPENOCD_SCRIPT_PATH}/interface/${JTAG_ADAPTER}.cfg"

    echo "Detecting JTAG TAPs in the chain..."
    echo "This will scan for all devices on the JTAG chain."
    echo

    local openocd_cmd=(
        "openocd"
        "-f" "$ocd_interface_cfg"
        "-c" "adapter speed 100"
        "-c" "transport select jtag"
        "-c" "jtag newtap auto0 tap -irlen 4 -expected-id 0"
        "-c" "init"
        "-c" "scan_chain"
        "-c" "exit"
    )

    log_message "INFO" "Running JTAG TAP detection..."
    log_message "CMD" "${openocd_cmd[*]}"

    local tap_output
    if tap_output=$("${openocd_cmd[@]}" 2>&1); then
        log_message "INFO" "TAP detection output: $tap_output"
        echo "------- TAP Detection Results -------"
        echo "$tap_output" | grep -E "(Info|TapName|IR length|IDCODE)" || echo "$tap_output"
        echo "-------------------------------------"

        # Extract and display IDCODE if found
        if echo "$tap_output" | grep -q "IDCODE"; then
            echo
            echo "Device IDCODE(s) detected:"
            echo "$tap_output" | grep "IDCODE"
        fi
    else
        log_message "ERROR" "TAP detection failed: $tap_output"
        echo "ERROR: TAP detection failed."
        echo "$tap_output"
    fi

    echo
    read -r -p "Press Enter to continue..."
}

jtag_interactive_console() {
    print_header
    echo "--- Interactive OpenOCD Console ---"
    echo

    if ! command -v openocd &> /dev/null; then
        log_message "ERROR" "'openocd' not found."
        echo "ERROR: 'openocd' is not installed."
        sleep 3
        return
    fi

    if [ "$JTAG_ADAPTER" == "auto" ] || [ "$TARGET_ARCH" == "auto" ]; then
        log_message "ERROR" "JTAG adapter or target architecture not set."
        echo "ERROR: Please configure both JTAG adapter and target architecture."
        sleep 3
        return
    fi

    local ocd_interface_cfg="${OPENOCD_SCRIPT_PATH}/interface/${JTAG_ADAPTER}.cfg"
    local ocd_target_cfg="${OPENOCD_SCRIPT_PATH}/target/swj-dp.cfg"

    echo "Starting OpenOCD server..."
    echo "Once started, you can connect via telnet on port 4444"
    echo
    echo "Useful commands:"
    echo "  halt              - Halt the target"
    echo "  resume            - Resume execution"
    echo "  reset halt        - Reset and halt"
    echo "  mdw <addr> <count> - Read memory (word)"
    echo "  mww <addr> <value> - Write memory (word)"
    echo "  reg               - Display registers"
    echo "  shutdown          - Exit OpenOCD"
    echo
    echo "Press Ctrl+C to stop the OpenOCD server."
    echo
    read -r -p "Press Enter to start OpenOCD server..."

    log_message "INFO" "Starting interactive OpenOCD console"

    # Start OpenOCD in the foreground
    openocd -f "$ocd_interface_cfg" -f "$ocd_target_cfg" 2>&1 | tee -a "$LOG_FILE"

    echo
    echo "OpenOCD server stopped."
    read -r -p "Press Enter to continue..."
}

jtag_password_recovery() {
    print_header
    echo "--- JTAG-Based Password Recovery ---"
    echo
    echo "This feature attempts to recover or reset device passwords"
    echo "by manipulating configuration memory via JTAG."
    echo

    if ! command -v openocd &> /dev/null; then
        log_message "ERROR" "'openocd' not found."
        echo "ERROR: 'openocd' is not installed."
        sleep 3
        return
    fi

    if [ "$JTAG_ADAPTER" == "auto" ] || [ "$TARGET_ARCH" == "auto" ]; then
        log_message "ERROR" "JTAG adapter or target architecture not set."
        echo "ERROR: Please configure JTAG adapter and target architecture."
        sleep 3
        return
    fi

    echo "Select recovery method:"
    echo "  1) Extract and analyze NVRAM for credentials"
    echo "  2) Patch configuration register (confreg method)"
    echo "  3) Extract full flash and search for passwords"
    echo "  b) Back"
    echo
    read -r -p "Choose an option: " recovery_choice

    case "$recovery_choice" in
        1)
            echo
            read -r -p "Enter NVRAM base address (hex, e.g., 0x1e000000): " nvram_addr
            read -r -p "Enter NVRAM size (bytes, e.g., 65536): " nvram_size
            local nvram_file="${SESSION_DIR}/nvram_dump.bin"

            local ocd_interface_cfg="${OPENOCD_SCRIPT_PATH}/interface/${JTAG_ADAPTER}.cfg"
            local ocd_target_cfg="${OPENOCD_SCRIPT_PATH}/target/swj-dp.cfg"

            echo "Dumping NVRAM via JTAG..."
            local openocd_cmd=(
                "openocd"
                "-f" "$ocd_interface_cfg"
                "-f" "$ocd_target_cfg"
                "-c" "init"
                "-c" "halt"
                "-c" "dump_image \"$nvram_file\" $nvram_addr $nvram_size"
                "-c" "resume"
                "-c" "exit"
            )

            log_message "CMD" "${openocd_cmd[*]}"

            if output=$("${openocd_cmd[@]}" 2>&1); then
                log_message "INFO" "NVRAM dump successful"
                echo "SUCCESS: NVRAM dumped to $nvram_file"
                echo
                echo "Searching for credentials..."
                echo "------- Potential Credentials -------"
                strings "$nvram_file" | grep -iE 'password|secret|user|admin|enable' | head -20
                echo "-------------------------------------"
                echo
                echo "Full NVRAM dump saved to: $nvram_file"
            else
                log_message "ERROR" "NVRAM dump failed: $output"
                echo "ERROR: Failed to dump NVRAM."
            fi
            ;;
        2)
            echo
            echo "This will attempt to set the configuration register to bypass startup-config."
            read -r -p "Enter config register address (hex, e.g., 0x1e000008): " confreg_addr
            read -r -p "Enter bypass value (hex, e.g., 0x2142): " bypass_value

            echo
            echo "WARNING: Writing incorrect values can brick the device!"
            read -r -p "Type 'confirm' to proceed: " confirm

            if [[ "$confirm" != "confirm" ]]; then
                echo "Operation cancelled."
                sleep 2
                return
            fi

            local ocd_interface_cfg="${OPENOCD_SCRIPT_PATH}/interface/${JTAG_ADAPTER}.cfg"
            local ocd_target_cfg="${OPENOCD_SCRIPT_PATH}/target/swj-dp.cfg"

            echo "Writing configuration register..."
            local openocd_cmd=(
                "openocd"
                "-f" "$ocd_interface_cfg"
                "-f" "$ocd_target_cfg"
                "-c" "init"
                "-c" "halt"
                "-c" "mww $confreg_addr $bypass_value"
                "-c" "resume"
                "-c" "reset"
                "-c" "exit"
            )

            log_message "CMD" "${openocd_cmd[*]}"

            if output=$("${openocd_cmd[@]}" 2>&1); then
                log_message "INFO" "Config register write successful"
                echo "SUCCESS: Configuration register updated."
                echo "Device will now boot bypassing startup-config."
                echo "You can configure a new password after reboot."
            else
                log_message "ERROR" "Config register write failed: $output"
                echo "ERROR: Failed to write configuration register."
            fi
            ;;
        3)
            echo
            read -r -p "Enter output file for flash dump: " flash_file

            local ocd_interface_cfg="${OPENOCD_SCRIPT_PATH}/interface/${JTAG_ADAPTER}.cfg"
            local ocd_target_cfg="${OPENOCD_SCRIPT_PATH}/target/swj-dp.cfg"

            echo "Dumping flash memory..."
            local openocd_cmd=(
                "openocd"
                "-f" "$ocd_interface_cfg"
                "-f" "$ocd_target_cfg"
                "-c" "init"
                "-c" "halt"
                "-c" "flash read_bank 0 \"$flash_file\" 0 0"
                "-c" "resume"
                "-c" "exit"
            )

            log_message "CMD" "${openocd_cmd[*]}"

            if output=$("${openocd_cmd[@]}" 2>&1); then
                log_message "INFO" "Flash dump successful"
                echo "SUCCESS: Flash dumped to $flash_file"
                echo
                echo "Searching for passwords in flash..."
                echo "------- Potential Credentials -------"
                strings "$flash_file" | grep -iE 'password|secret|enable|username' | head -30
                echo "-------------------------------------"
            else
                log_message "ERROR" "Flash dump failed: $output"
                echo "ERROR: Failed to dump flash memory."
            fi
            ;;
        b)
            return
            ;;
        *)
            echo "Invalid option."
            sleep 1
            ;;
    esac

    echo
    read -r -p "Press Enter to continue..."
}

jtag_bootloader_recovery() {
    print_header
    echo "--- JTAG Bootloader Recovery ---"
    echo
    echo "This feature helps recover devices with corrupted bootloaders"
    echo "by writing a new bootloader image via JTAG."
    echo

    if ! command -v openocd &> /dev/null; then
        log_message "ERROR" "'openocd' not found."
        echo "ERROR: 'openocd' is not installed."
        sleep 3
        return
    fi

    if [ "$JTAG_ADAPTER" == "auto" ] || [ "$TARGET_ARCH" == "auto" ]; then
        log_message "ERROR" "JTAG adapter or target architecture not set."
        echo "ERROR: Please configure JTAG adapter and target architecture."
        sleep 3
        return
    fi

    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "  WARNING: THIS IS AN EXTREMELY DANGEROUS OPERATION."
    echo "  Writing an incorrect bootloader WILL brick your device."
    echo "  You assume all risk. Ensure you have the correct image."
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo

    read -r -p "Enter the path to the bootloader image (.bin): " bootloader_file

    if [ ! -f "$bootloader_file" ]; then
        log_message "ERROR" "Bootloader file not found: $bootloader_file"
        echo "ERROR: File not found at '$bootloader_file'."
        sleep 2
        return
    fi

    read -r -p "Enter bootloader flash address (hex, e.g., 0x0): " boot_addr

    echo
    echo "Bootloader file: $bootloader_file"
    echo "Target address: $boot_addr"
    echo "Target arch: $TARGET_ARCH"
    echo "JTAG adapter: $JTAG_ADAPTER"
    echo

    read -r -p "Type 'RECOVER' to proceed with bootloader write: " confirm

    if [[ "$confirm" != "RECOVER" ]]; then
        log_message "INFO" "Bootloader recovery cancelled by user."
        echo "Operation cancelled."
        sleep 2
        return
    fi

    local ocd_interface_cfg="${OPENOCD_SCRIPT_PATH}/interface/${JTAG_ADAPTER}.cfg"
    local ocd_target_cfg="${OPENOCD_SCRIPT_PATH}/target/swj-dp.cfg"

    echo
    echo "Preparing to write bootloader..."
    echo "This will erase the flash sector and write the new bootloader."
    echo
    read -r -p "Press Enter to continue or Ctrl+C to abort..."

    local openocd_cmd=(
        "openocd"
        "-f" "$ocd_interface_cfg"
        "-f" "$ocd_target_cfg"
        "-c" "init"
        "-c" "halt"
        "-c" "flash erase_sector 0 0 0"
        "-c" "flash write_bank 0 \"$bootloader_file\" $boot_addr"
        "-c" "verify_image \"$bootloader_file\" $boot_addr"
        "-c" "reset run"
        "-c" "exit"
    )

    log_message "CMD" "${openocd_cmd[*]}"
    echo "Writing bootloader via JTAG..."

    if output=$("${openocd_cmd[@]}" 2>&1); then
        log_message "INFO" "Bootloader write successful: $output"
        echo "---"
        echo " SUCCESS: Bootloader written and verified."
        echo " The device has been reset."
        echo " Monitor the serial console for boot messages."
        echo "---"
    else
        log_message "ERROR" "Bootloader write failed: $output"
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        echo "   ERROR: BOOTLOADER WRITE FAILED."
        echo "   The device may be bricked."
        echo "   See log at $LOG_FILE for details."
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    fi

    echo
    read -r -p "Press Enter to continue..."
}

jtag_memory_patch() {
    print_header
    echo "--- JTAG Memory Patching ---"
    echo
    echo "This feature allows you to patch memory or flash via JTAG"
    echo "for recovery purposes (e.g., fixing corrupted data, patching configs)."
    echo

    if ! command -v openocd &> /dev/null; then
        log_message "ERROR" "'openocd' not found."
        echo "ERROR: 'openocd' is not installed."
        sleep 3
        return
    fi

    if [ "$JTAG_ADAPTER" == "auto" ] || [ "$TARGET_ARCH" == "auto" ]; then
        log_message "ERROR" "JTAG adapter or target architecture not set."
        echo "ERROR: Please configure JTAG adapter and target architecture."
        sleep 3
        return
    fi

    echo "Select patch operation:"
    echo "  1) Write single word to memory"
    echo "  2) Write binary patch to memory"
    echo "  3) Fill memory region with pattern"
    echo "  b) Back"
    echo
    read -r -p "Choose an option: " patch_choice

    local ocd_interface_cfg="${OPENOCD_SCRIPT_PATH}/interface/${JTAG_ADAPTER}.cfg"
    local ocd_target_cfg="${OPENOCD_SCRIPT_PATH}/target/swj-dp.cfg"

    case "$patch_choice" in
        1)
            echo
            read -r -p "Enter memory address (hex, e.g., 0x80000000): " mem_addr
            read -r -p "Enter value to write (hex, e.g., 0x12345678): " mem_value

            echo "Writing word $mem_value to address $mem_addr..."

            local openocd_cmd=(
                "openocd"
                "-f" "$ocd_interface_cfg"
                "-f" "$ocd_target_cfg"
                "-c" "init"
                "-c" "halt"
                "-c" "mww $mem_addr $mem_value"
                "-c" "resume"
                "-c" "exit"
            )

            log_message "CMD" "${openocd_cmd[*]}"

            if output=$("${openocd_cmd[@]}" 2>&1); then
                log_message "INFO" "Memory write successful"
                echo "SUCCESS: Memory patched."
            else
                log_message "ERROR" "Memory write failed: $output"
                echo "ERROR: Memory patch failed."
            fi
            ;;
        2)
            echo
            read -r -p "Enter binary patch file path: " patch_file

            if [ ! -f "$patch_file" ]; then
                echo "ERROR: File not found."
                sleep 2
                return
            fi

            read -r -p "Enter target address (hex, e.g., 0x80000000): " target_addr

            echo "Writing binary patch to $target_addr..."

            local openocd_cmd=(
                "openocd"
                "-f" "$ocd_interface_cfg"
                "-f" "$ocd_target_cfg"
                "-c" "init"
                "-c" "halt"
                "-c" "load_image \"$patch_file\" $target_addr"
                "-c" "resume"
                "-c" "exit"
            )

            log_message "CMD" "${openocd_cmd[*]}"

            if output=$("${openocd_cmd[@]}" 2>&1); then
                log_message "INFO" "Binary patch successful"
                echo "SUCCESS: Binary patch applied."
            else
                log_message "ERROR" "Binary patch failed: $output"
                echo "ERROR: Binary patch failed."
            fi
            ;;
        3)
            echo
            read -r -p "Enter start address (hex, e.g., 0x80000000): " start_addr
            read -r -p "Enter size in bytes: " fill_size
            read -r -p "Enter fill pattern (hex, e.g., 0xFF): " fill_pattern

            echo "WARNING: This will overwrite $fill_size bytes of memory!"
            read -r -p "Type 'confirm' to proceed: " confirm

            if [[ "$confirm" != "confirm" ]]; then
                echo "Operation cancelled."
                sleep 2
                return
            fi

            # Create a temporary file with the pattern
            local pattern_file="${SESSION_DIR}/fill_pattern.bin"
            dd if=/dev/zero bs=1 count="$fill_size" 2>/dev/null | tr '\0' "\x${fill_pattern}" > "$pattern_file"

            echo "Filling memory region..."

            local openocd_cmd=(
                "openocd"
                "-f" "$ocd_interface_cfg"
                "-f" "$ocd_target_cfg"
                "-c" "init"
                "-c" "halt"
                "-c" "load_image \"$pattern_file\" $start_addr"
                "-c" "resume"
                "-c" "exit"
            )

            log_message "CMD" "${openocd_cmd[*]}"

            if output=$("${openocd_cmd[@]}" 2>&1); then
                log_message "INFO" "Memory fill successful"
                echo "SUCCESS: Memory region filled."
            else
                log_message "ERROR" "Memory fill failed: $output"
                echo "ERROR: Memory fill failed."
            fi

            rm -f "$pattern_file"
            ;;
        b)
            return
            ;;
        *)
            echo "Invalid option."
            sleep 1
            ;;
    esac

    echo
    read -r -p "Press Enter to continue..."
}

jtag_recovery_wizard() {
    print_header
    echo "--- Guided JTAG Recovery Wizard ---"
    echo
    echo "This wizard will guide you through common JTAG recovery scenarios."
    echo

    if ! command -v openocd &> /dev/null; then
        log_message "ERROR" "'openocd' not found."
        echo "ERROR: 'openocd' is not installed."
        sleep 3
        return
    fi

    echo "What is your recovery scenario?"
    echo "  1) Device won't boot (soft-brick recovery)"
    echo "  2) Forgot password (JTAG password reset)"
    echo "  3) Corrupted bootloader"
    echo "  4) Need to extract firmware/config"
    echo "  b) Back"
    echo
    read -r -p "Choose your scenario: " scenario

    case "$scenario" in
        1)
            print_header
            echo "--- Soft-Brick Recovery Wizard ---"
            echo
            echo "Steps for recovering a non-booting device:"
            echo
            echo "1. First, let's verify JTAG connectivity..."
            read -r -p "Press Enter to test connection..."
            jtag_test_connection

            echo
            echo "2. Next, we'll try to halt the CPU and examine the state..."
            echo "   You can use the interactive console for this."
            read -r -p "Launch interactive console? (y/n): " launch_console
            if [[ "$launch_console" == "y" ]]; then
                jtag_interactive_console
            fi

            echo
            echo "3. Common recovery steps:"
            echo "   - Extract current flash/bootloader for analysis"
            echo "   - Check if bootloader is corrupted"
            echo "   - Re-flash known-good firmware"
            echo
            read -r -p "Would you like to extract the current flash? (y/n): " extract_flash
            if [[ "$extract_flash" == "y" ]]; then
                exploit_via_jtag "extract_flash"
            fi
            ;;
        2)
            print_header
            echo "--- JTAG Password Reset Wizard ---"
            echo
            echo "We'll attempt to reset/recover passwords via JTAG."
            echo
            read -r -p "Press Enter to start password recovery..."
            jtag_password_recovery
            ;;
        3)
            print_header
            echo "--- Bootloader Recovery Wizard ---"
            echo
            echo "WARNING: Bootloader recovery is dangerous!"
            echo "Make sure you have:"
            echo "  - The correct bootloader image for your device"
            echo "  - Verified JTAG connectivity"
            echo "  - Backed up existing flash (if possible)"
            echo
            read -r -p "Continue with bootloader recovery? (y/n): " continue_boot
            if [[ "$continue_boot" == "y" ]]; then
                jtag_bootloader_recovery
            fi
            ;;
        4)
            print_header
            echo "--- Firmware/Config Extraction Wizard ---"
            echo
            echo "What would you like to extract?"
            echo "  1) Full flash memory"
            echo "  2) RAM dump"
            echo "  3) NVRAM (configuration)"
            echo
            read -r -p "Choose option: " extract_option

            case "$extract_option" in
                1) exploit_via_jtag "extract_flash" ;;
                2) exploit_via_jtag "dump_ram" ;;
                3)
                    read -r -p "Enter NVRAM address (hex): " nvram_addr
                    read -r -p "Enter NVRAM size (bytes): " nvram_size
                    # This would call a custom extraction
                    echo "Extracting NVRAM..."
                    ;;
            esac
            ;;
        b)
            return
            ;;
        *)
            echo "Invalid option."
            sleep 1
            ;;
    esac

    echo
    read -r -p "Press Enter to return to menu..."
}

jtag_auto_boot_interrupt() {
    print_header
    echo "--- Automated Boot Interception ---"
    echo
    echo "This module will monitor the device and automatically interrupt"
    echo "the boot process, then guide you through recovery options."
    echo

    if ! command -v openocd &> /dev/null; then
        log_message "ERROR" "'openocd' not found."
        echo "ERROR: 'openocd' is not installed."
        sleep 3
        return
    fi

    if [ "$JTAG_ADAPTER" == "auto" ] || [ "$TARGET_ARCH" == "auto" ]; then
        log_message "ERROR" "JTAG adapter or target architecture not set."
        echo "ERROR: Please configure JTAG adapter and target architecture first."
        sleep 3
        return
    fi

    echo "Configuration:"
    echo "  Platform: $PLATFORM"
    echo "  JTAG Adapter: $JTAG_ADAPTER"
    echo "  Architecture: $TARGET_ARCH"
    echo
    echo "This will:"
    echo "  1. Start OpenOCD and connect to the device"
    echo "  2. Wait for boot activity (or power cycle if needed)"
    echo "  3. Automatically halt the CPU early in boot"
    echo "  4. Present recovery options"
    echo
    read -r -p "Continue? (y/n): " continue_choice

    if [[ "$continue_choice" != "y" ]]; then
        echo "Operation cancelled."
        sleep 1
        return
    fi

    local ocd_interface_cfg="${OPENOCD_SCRIPT_PATH}/interface/${JTAG_ADAPTER}.cfg"
    local ocd_target_cfg="${OPENOCD_SCRIPT_PATH}/target/swj-dp.cfg"

    # Create temporary OpenOCD script for boot interception
    local ocd_script="${SESSION_DIR}/boot_intercept.cfg"
    cat > "$ocd_script" <<- 'OCDEOF'
# Boot interception script
proc boot_intercept {} {
    echo "=== Boot Interception Active ==="
    echo "Waiting for device to start booting..."
    echo "Power cycle the device now if it's not already running."
    echo ""

    # Try to connect and halt
    if {[catch {init} err]} {
        echo "Init failed: $err"
        echo "Retrying in 2 seconds..."
        after 2000
        if {[catch {init} err2]} {
            echo "Second init attempt failed: $err2"
            return
        }
    }

    echo "Connected to device via JTAG."
    echo "Waiting 3 seconds for boot to start..."
    after 3000

    # Attempt to halt the CPU
    echo "Attempting to halt CPU..."
    if {[catch {halt} err]} {
        echo "First halt attempt failed: $err"
        echo "Retrying..."
        after 1000
        if {[catch {halt 1000} err2]} {
            echo "Second halt attempt failed: $err2"
        } else {
            echo "*** CPU HALTED ***"
        }
    } else {
        echo "*** CPU HALTED ***"
    }

    # Display CPU state
    echo ""
    echo "=== Current CPU State ==="
    if {[catch {reg} err]} {
        echo "Could not read registers: $err"
    }

    echo ""
    echo "=== Boot Intercepted Successfully ==="
    echo "The device is now halted and ready for recovery operations."
    echo "OpenOCD telnet server is running on port 4444"
    echo "Use 'telnet localhost 4444' to access the console."
    echo ""
}

# Run the interception
boot_intercept
OCDEOF

    echo
    echo "Starting OpenOCD with boot interception..."
    echo "==================================================="
    log_message "INFO" "Starting automated boot interception"

    # Start OpenOCD in the background
    local openocd_log="${SESSION_DIR}/openocd_boot_intercept.log"
    openocd -f "$ocd_interface_cfg" -f "$ocd_target_cfg" -f "$ocd_script" > "$openocd_log" 2>&1 &
    local openocd_pid=$!

    echo "OpenOCD started (PID: $openocd_pid)"
    echo "Monitoring boot process..."
    echo
    echo "*** POWER CYCLE THE DEVICE NOW ***"
    echo
    echo "Waiting for boot interception (timeout: 30 seconds)..."

    # Wait and monitor the log
    local timeout=30
    local elapsed=0
    local halted=0

    while [ $elapsed -lt $timeout ]; do
        if grep -q "CPU HALTED" "$openocd_log" 2>/dev/null; then
            halted=1
            break
        fi

        if ! kill -0 $openocd_pid 2>/dev/null; then
            echo "ERROR: OpenOCD process died unexpectedly."
            log_message "ERROR" "OpenOCD process terminated during boot interception"
            cat "$openocd_log"
            read -r -p "Press Enter to continue..."
            return
        fi

        sleep 1
        elapsed=$((elapsed + 1))

        # Show progress
        if [ $((elapsed % 5)) -eq 0 ]; then
            echo "Still waiting... ($elapsed seconds elapsed)"
        fi
    done

    if [ $halted -eq 1 ]; then
        echo
        echo "==================================================="
        echo "*** BOOT SUCCESSFULLY INTERCEPTED ***"
        echo "==================================================="
        echo
        log_message "INFO" "Boot interception successful"

        # Show the boot intercept menu
        jtag_post_interrupt_menu "$openocd_pid"
    else
        echo
        echo "==================================================="
        echo "WARNING: Boot interception timed out."
        echo "The device may not have booted or JTAG connection failed."
        echo "==================================================="
        log_message "WARN" "Boot interception timeout"
        echo
        echo "OpenOCD is still running. Check the log:"
        tail -20 "$openocd_log"
        echo
        read -r -p "Kill OpenOCD? (y/n): " kill_choice
        if [[ "$kill_choice" == "y" ]]; then
            kill $openocd_pid 2>/dev/null
            echo "OpenOCD terminated."
        fi
    fi

    read -r -p "Press Enter to continue..."
}

jtag_post_interrupt_menu() {
    local openocd_pid="$1"

    while true; do
        print_header
        echo "--- Post-Interrupt Recovery Menu ---"
        echo
        echo "  Device Status: HALTED via JTAG"
        echo "  OpenOCD PID: $openocd_pid (telnet port 4444)"
        echo "  Platform: $PLATFORM"
        echo
        echo "=== Recovery Options ==="
        echo "  1) Password Reset (NVRAM Method)"
        echo "  2) Password Reset (Config Register Method)"
        echo "  3) Dump Firmware/Flash"
        echo "  4) Dump RAM"
        echo "  5) Extract NVRAM Configuration"
        echo "  6) Manual OpenOCD Console (telnet)"
        echo "  7) Examine Registers & Memory"
        echo "  8) Resume Boot (Exit Recovery)"
        echo "  9) Power Off Device (Keep Halted)"
        echo "  b) Kill OpenOCD & Return"
        echo
        read -r -p "Choose an option: " choice

        case "$choice" in
            1)
                # Password reset via NVRAM
                print_header
                echo "--- Password Reset: NVRAM Method ---"
                echo
                echo "This will dump NVRAM and search for credentials."
                echo
                read -r -p "Enter NVRAM base address (hex, e.g., 0x1e000000): " nvram_addr
                read -r -p "Enter NVRAM size (bytes, e.g., 65536): " nvram_size
                local nvram_file="${SESSION_DIR}/nvram_boot_intercept.bin"

                echo
                echo "Dumping NVRAM via telnet to OpenOCD..."

                # Use telnet to send commands to OpenOCD
                {
                    sleep 1
                    echo "halt"
                    sleep 1
                    echo "dump_image \"$nvram_file\" $nvram_addr $nvram_size"
                    sleep 2
                    echo "exit"
                } | telnet localhost 4444 2>&1 | tee "${SESSION_DIR}/nvram_dump_output.log"

                if [ -f "$nvram_file" ]; then
                    echo
                    echo "SUCCESS: NVRAM dumped to $nvram_file"
                    echo
                    echo "Searching for credentials..."
                    echo "------- Potential Credentials -------"
                    strings "$nvram_file" | grep -iE 'password|secret|user|admin|enable|cisco' | head -30
                    echo "-------------------------------------"
                    log_message "INFO" "NVRAM dump successful via boot intercept"
                else
                    echo "ERROR: NVRAM dump failed. Check OpenOCD output."
                fi

                read -r -p "Press Enter to continue..."
                ;;
            2)
                # Password reset via config register
                print_header
                echo "--- Password Reset: Config Register Method ---"
                echo
                echo "This will modify the configuration register to bypass"
                echo "the startup-config on next boot (confreg 0x2142)."
                echo
                read -r -p "Enter config register address (hex, e.g., 0x2102000): " confreg_addr
                echo
                echo "Common bypass values:"
                echo "  Cisco ISR/Router: 0x2142"
                echo "  Other: Check device documentation"
                echo
                read -r -p "Enter bypass value (hex, e.g., 0x2142): " bypass_value

                echo
                echo "WARNING: Writing incorrect values can brick the device!"
                read -r -p "Type 'CONFIRM' to proceed: " confirm

                if [[ "$confirm" != "CONFIRM" ]]; then
                    echo "Operation cancelled."
                    sleep 2
                    continue
                fi

                echo
                echo "Writing configuration register via OpenOCD..."

                {
                    sleep 1
                    echo "halt"
                    sleep 1
                    echo "mww $confreg_addr $bypass_value"
                    sleep 1
                    echo "mdw $confreg_addr 1"
                    sleep 1
                    echo "exit"
                } | telnet localhost 4444 2>&1 | tee "${SESSION_DIR}/confreg_output.log"

                echo
                echo "Configuration register write completed."
                echo "You can now resume boot (option 8) and the device"
                echo "will bypass startup-config, allowing password reset."

                log_message "INFO" "Config register modified via boot intercept"
                read -r -p "Press Enter to continue..."
                ;;
            3)
                # Dump firmware/flash
                print_header
                echo "--- Dump Firmware/Flash ---"
                echo
                read -r -p "Enter output file path: " flash_file
                read -r -p "Enter flash base address (hex, e.g., 0x0): " flash_addr
                read -r -p "Enter size to dump (bytes, e.g., 16777216): " flash_size

                echo
                echo "Dumping flash memory..."

                {
                    sleep 1
                    echo "halt"
                    sleep 1
                    echo "dump_image \"$flash_file\" $flash_addr $flash_size"
                    sleep 5
                    echo "exit"
                } | telnet localhost 4444 2>&1 | tee "${SESSION_DIR}/flash_dump_output.log"

                if [ -f "$flash_file" ]; then
                    echo
                    echo "SUCCESS: Flash dumped to $flash_file"
                    echo "File size: $(du -h "$flash_file" | cut -f1)"
                    log_message "INFO" "Flash dump successful via boot intercept: $flash_file"
                else
                    echo "ERROR: Flash dump failed."
                fi

                read -r -p "Press Enter to continue..."
                ;;
            4)
                # Dump RAM
                print_header
                echo "--- Dump RAM ---"
                echo
                read -r -p "Enter output file path: " ram_file
                read -r -p "Enter RAM base address (hex, e.g., 0x80000000): " ram_addr
                read -r -p "Enter size to dump (bytes, e.g., 134217728): " ram_size

                echo
                echo "Dumping RAM..."

                {
                    sleep 1
                    echo "halt"
                    sleep 1
                    echo "dump_image \"$ram_file\" $ram_addr $ram_size"
                    sleep 3
                    echo "exit"
                } | telnet localhost 4444 2>&1 | tee "${SESSION_DIR}/ram_dump_output.log"

                if [ -f "$ram_file" ]; then
                    echo
                    echo "SUCCESS: RAM dumped to $ram_file"
                    echo "File size: $(du -h "$ram_file" | cut -f1)"
                    log_message "INFO" "RAM dump successful via boot intercept: $ram_file"
                else
                    echo "ERROR: RAM dump failed."
                fi

                read -r -p "Press Enter to continue..."
                ;;
            5)
                # Extract NVRAM configuration
                print_header
                echo "--- Extract NVRAM Configuration ---"
                echo
                echo "This extracts the full NVRAM including startup-config."
                echo
                read -r -p "Enter NVRAM base address (hex, e.g., 0x1e000000): " nvram_addr
                read -r -p "Enter NVRAM size (bytes, e.g., 131072): " nvram_size
                local nvram_file="${SESSION_DIR}/nvram_full_config.bin"

                echo
                echo "Extracting NVRAM configuration..."

                {
                    sleep 1
                    echo "halt"
                    sleep 1
                    echo "dump_image \"$nvram_file\" $nvram_addr $nvram_size"
                    sleep 2
                    echo "exit"
                } | telnet localhost 4444 2>&1

                if [ -f "$nvram_file" ]; then
                    echo
                    echo "SUCCESS: NVRAM extracted to $nvram_file"
                    echo
                    echo "Searching for configuration data..."
                    echo "------- Configuration Snippets -------"
                    strings "$nvram_file" | grep -E '^(interface|ip|router|line|enable|username|hostname)' | head -50
                    echo "--------------------------------------"
                    echo
                    echo "Full NVRAM saved to: $nvram_file"
                    log_message "INFO" "NVRAM configuration extracted via boot intercept"
                else
                    echo "ERROR: NVRAM extraction failed."
                fi

                read -r -p "Press Enter to continue..."
                ;;
            6)
                # Manual console
                print_header
                echo "--- Manual OpenOCD Console ---"
                echo
                echo "OpenOCD telnet server is running on localhost:4444"
                echo
                echo "Useful commands:"
                echo "  halt              - Halt the CPU"
                echo "  resume            - Resume execution"
                echo "  reset halt        - Reset and halt"
                echo "  reg               - Display registers"
                echo "  mdw <addr> <cnt>  - Read memory (word)"
                echo "  mww <addr> <val>  - Write memory (word)"
                echo "  dump_image <file> <addr> <size> - Dump memory"
                echo "  load_image <file> <addr> - Load to memory"
                echo "  step              - Single step"
                echo
                echo "Connecting to telnet console..."
                echo "Type 'exit' or Ctrl+] then 'quit' to return."
                echo
                read -r -p "Press Enter to connect..."

                telnet localhost 4444

                echo
                echo "Disconnected from OpenOCD console."
                read -r -p "Press Enter to continue..."
                ;;
            7)
                # Examine registers & memory
                print_header
                echo "--- Examine Registers & Memory ---"
                echo
                echo "Retrieving CPU state..."

                local exam_output="${SESSION_DIR}/examination_output.log"
                {
                    sleep 1
                    echo "halt"
                    sleep 1
                    echo "reg"
                    sleep 1
                    echo "exit"
                } | telnet localhost 4444 2>&1 | tee "$exam_output"

                echo
                echo "=== Register Dump ==="
                grep -A 50 "reg" "$exam_output" | head -60
                echo "====================="
                echo

                read -r -p "Examine specific memory address? (y/n): " exam_mem
                if [[ "$exam_mem" == "y" ]]; then
                    read -r -p "Enter address (hex): " exam_addr
                    read -r -p "Enter word count: " exam_count

                    {
                        sleep 1
                        echo "mdw $exam_addr $exam_count"
                        sleep 1
                        echo "exit"
                    } | telnet localhost 4444 2>&1
                fi

                echo
                read -r -p "Press Enter to continue..."
                ;;
            8)
                # Resume boot
                print_header
                echo "--- Resume Boot ---"
                echo
                echo "This will resume device execution and continue booting."
                echo
                read -r -p "Resume now? (y/n): " resume_choice

                if [[ "$resume_choice" == "y" ]]; then
                    echo
                    echo "Resuming device..."

                    {
                        sleep 1
                        echo "resume"
                        sleep 1
                        echo "exit"
                    } | telnet localhost 4444 2>&1

                    echo
                    echo "Device resumed. Boot should continue."
                    echo "Monitor the serial console for boot messages."
                    log_message "INFO" "Device boot resumed after interception"

                    read -r -p "Press Enter to continue..."
                fi
                ;;
            9)
                # Power off device
                print_header
                echo "--- Power Off Device ---"
                echo
                echo "The device will remain halted via JTAG."
                echo "You can manually power off the device now."
                echo
                echo "OpenOCD will keep running. Use option 'b' to kill it."
                read -r -p "Press Enter to continue..."
                ;;
            b)
                # Kill OpenOCD and return
                print_header
                echo "--- Terminating OpenOCD ---"
                echo
                read -r -p "Kill OpenOCD and return to menu? (y/n): " kill_choice

                if [[ "$kill_choice" == "y" ]]; then
                    if kill -0 $openocd_pid 2>/dev/null; then
                        kill $openocd_pid 2>/dev/null
                        sleep 1
                        echo "OpenOCD terminated (PID: $openocd_pid)"
                        log_message "INFO" "OpenOCD terminated after boot interception session"
                    else
                        echo "OpenOCD process already terminated."
                    fi
                    break
                fi
                ;;
            *)
                echo "Invalid option."
                sleep 1
                ;;
        esac
    done
}

menu_jtag_cable_recovery() {
    while true; do
        print_header
        echo "--- JTAG Cable Assisted Recovery ---"
        echo "  Current Adapter: $JTAG_ADAPTER"
        echo "  Current Architecture: $TARGET_ARCH"
        echo
        echo "  1) Test JTAG Cable Connection"
        echo "  2) Detect JTAG TAPs & Diagnostics"
        echo "  3) Interactive OpenOCD Console"
        echo "  4) Automated Boot Interception (NEW)"
        echo "  5) JTAG Password Recovery"
        echo "  6) JTAG Bootloader Recovery"
        echo "  7) JTAG Memory Patching"
        echo "  8) Guided Recovery Wizard"
        echo "  b) Back to Main Menu"
        echo
        read -r -p "Choose an option: " choice

        case "$choice" in
            1) jtag_test_connection ;;
            2) jtag_detect_taps ;;
            3) jtag_interactive_console ;;
            4) jtag_auto_boot_interrupt ;;
            5) jtag_password_recovery ;;
            6) jtag_bootloader_recovery ;;
            7) jtag_memory_patch ;;
            8) jtag_recovery_wizard ;;
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
        echo "  4) JTAG Cable Assisted Recovery"
        echo "  5) Memory Analysis"
        echo "  6) Firmware Manipulation"
        echo "  b) Exit"
        echo
        read -r -p "Choose an option: " choice

        case "$choice" in
            1) menu_platform_jtag_config ;;
            2) menu_password_recovery ;;
            3) menu_jtag_exploitation ;;
            4) menu_jtag_cable_recovery ;;
            5) menu_memory_analysis ;;
            6) menu_firmware_manipulation ;;
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
