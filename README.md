# Cisco & Generic Embedded Advanced Recovery Tool v3.0

## Overview

This script is a professional-grade, TUI-driven framework for multi-vector interaction with Cisco and other embedded devices. It combines serial console recovery, advanced JTAG exploitation, JTAG cable assisted recovery, firmware modification, advanced firmware analysis, bootloader development, filesystem manipulation, automated exploit development, configuration management, and live memory manipulation for comprehensive hardware reverse engineering and security auditing.

### New in v3.0 - Quality of Life Improvements

-   **Color-Coded Output:** Beautiful, easy-to-read interface with color-coded SUCCESS (green), ERROR (red), WARNING (yellow), and INFO (blue) messages throughout the entire tool
-   **Startup Dependency Checker:** Automatic validation of all required and optional tools on launch with clear installation hints and package names
-   **Recent Files Tracking:** Quick access to the last 10 firmware files, binaries, and filesystems you've worked with - no more typing paths repeatedly!
-   **Device Address Presets:** Pre-configured memory maps for ISR 4000/1000/900, ASA 5500-X/Classic, and generic ARM/MIPS devices - eliminates guesswork for memory operations

## Features

-   **Multi-Platform & Multi-Architecture:** Targets Cisco ISR (ARM), ASA, and generic MIPS32 devices.
-   **Dynamic Device Detection:** Scans for and identifies a wide range of serial and JTAG adapters (FTDI, J-Link, CH341).
-   **Session Logging & Configuration:** Supports session logging and an external config file.

### JTAG Exploitation Menu

-   **Data Exfiltration:** Includes tools for dumping memory regions and extracting the full contents of flash memory via JTAG.
-   **Multi-Architecture Profiles:** Provides distinct initialization profiles for ARM and MIPS targets.

### JTAG Cable Assisted Recovery Menu

-   **Connection Testing:** Verify JTAG cable connectivity and detect issues before attempting recovery operations.
-   **TAP Detection & Diagnostics:** Automatically detect and identify JTAG TAPs in the chain with IDCODE reporting.
-   **Interactive OpenOCD Console:** Launch an interactive OpenOCD server for manual debugging and recovery operations.
-   **Automated Boot Interception (NEW):** Revolutionary feature that monitors device boot via JTAG and automatically interrupts it:
    -   Waits for ISR/device to start booting
    -   Automatically halts CPU during boot process
    -   Presents comprehensive post-interrupt recovery menu
    -   **Post-Interrupt Options:**
        -   Password Reset (NVRAM extraction method)
        -   Password Reset (Config register bypass method - confreg 0x2142)
        -   Dump Firmware/Flash
        -   Dump RAM
        -   Extract NVRAM Configuration (including startup-config)
        -   Manual OpenOCD Console (drop to telnet for advanced operations)
        -   Examine Registers & Memory
        -   Resume Boot (continue normal boot after modifications)
        -   Power Off Device (keep halted)
    -   All operations performed while device is halted at boot
    -   Perfect for password recovery when serial console is locked
-   **JTAG Password Recovery:** Three methods for password recovery:
    -   Extract and analyze NVRAM for credentials
    -   Patch configuration register (confreg bypass method)
    -   Extract full flash and search for passwords
-   **JTAG Bootloader Recovery:** Write new bootloader images via JTAG to recover from bootloader corruption (DANGEROUS).
-   **JTAG Memory Patching:** Patch memory or flash for recovery purposes:
    -   Write single words to memory
    -   Apply binary patches
    -   Fill memory regions with patterns
-   **Guided Recovery Wizard:** Step-by-step wizards for common scenarios:
    -   Soft-brick recovery (device won't boot)
    -   Password reset via JTAG
    -   Bootloader corruption recovery
    -   Firmware/config extraction

### Firmware Modification Workshop (NEW)

The ultimate toolkit for custom firmware development and modification:

-   **Firmware Unpacker & Analyzer:**
    -   Quick analysis (file type, entropy, signatures)
    -   Full extraction with binwalk
    -   Filesystem extraction and analysis
    -   Embedded credential scanning
    -   Automatic filesystem security analysis
-   **Binary Firmware Patcher:**
    -   Replace hex bytes at any offset
    -   String replacement with automatic padding
    -   NOP out signature checks (bypass validation)
    -   Apply custom binary patch files
    -   Modify embedded IPs/URLs
    -   Perfect for creating custom firmware
-   **Firmware Flash Workflow:**
    -   Dump → Modify → Flash automated workflow
    -   Quick patch and flash option
    -   Integrated with JTAG boot interception
    -   Safe backup before modifications
-   **Boot Intercept Integration:**
    -   Dump firmware while device is halted
    -   Modify on-the-fly
    -   Flash back immediately
    -   All in one session!

### Advanced Firmware Analysis Suite (NEW)

Comprehensive analysis tools for firmware security research:

-   **Automated Firmware Teardown:**
    -   File type and format identification
    -   Entropy analysis (detect encryption/compression)
    -   String extraction and categorization (URLs, credentials, paths, versions, emails)
    -   Function signature detection
    -   Embedded file detection
    -   Architecture detection
    -   Generates organized reports in session directory
-   **Binary Firmware Differ:**
    -   Compare two firmware versions for changes
    -   Byte-level differences with hex dumps
    -   Added/removed strings analysis
    -   Changed function detection
    -   Modified embedded files comparison
    -   Checksum comparison (MD5, SHA256)
-   **Vulnerability Scanner:**
    -   Hardcoded credentials detection
    -   Dangerous function calls (strcpy, gets, system, etc.)
    -   Weak cryptographic algorithms (MD5, DES, RC4, SHA1)
    -   Private keys and certificates detection
    -   Debug/backdoor string patterns
    -   SQL injection pattern detection
    -   Common CVE patterns for outdated components

### Bootloader Development Kit (NEW)

Professional tools for bootloader modification and development:

-   **U-Boot Modifier:**
    -   Patch environment variables
    -   Modify boot commands (bootcmd)
    -   Change boot delays
    -   Update network settings (IP, serverip, netmask, gateway)
    -   Disable signature verification (NOP injection)
    -   Search and analyze U-Boot strings
    -   View U-Boot header information
    -   Creates .modified backup files
-   **Bootloader Chain Builder:**
    -   Build multi-stage bootloader configurations
    -   Define Stage 1, Stage 2, and Kernel components
    -   Configure load addresses and entry points
    -   Generate U-Boot boot scripts
    -   Create combined bootloader images with proper padding
    -   Export configurations for deployment
    -   Supports automatic script compilation with mkimage

### Firmware Filesystem Tools (NEW)

Complete workflow for extracting, modifying, and repackaging firmware filesystems:

-   **Filesystem Extractor:**
    -   Auto-detect and extract squashfs, cramfs, jffs2, yaffs2, ext2/3/4
    -   4-step extraction process (scan, extract, analyze, security scan)
    -   Automatic SUID binary detection
    -   Quick credential search
    -   File type breakdown analysis
-   **Filesystem Modifier:**
    -   Browse extracted filesystem
    -   Edit configuration files with nano/vi
    -   Replace binaries
    -   Add/delete files
    -   Modify permissions and ownership
    -   Inject backdoor scripts (telnet, reverse shell, SSH keys)
    -   Modify init scripts for persistence
    -   Search for files
-   **Filesystem Repackager:**
    -   Rebuild SquashFS with custom compression (gzip, lzma, xz, lzo)
    -   Create JFFS2 images with custom erase block/page sizes
    -   Generate CPIO and TAR archives
    -   Ready for flashing via JTAG or firmware update

### Automated Exploit Development Tools (NEW)

Accelerate exploit development with automated tools:

-   **ROP Gadget Finder:**
    -   Automatic gadget discovery using ROPgadget or objdump
    -   Categorizes gadgets (pop/ret, mov/ret, call, jmp)
    -   Address and offset information
    -   Exports gadgets to categorized files
-   **Shellcode Generator:**
    -   Multi-architecture support (ARM, MIPS, x86, x86_64)
    -   Payload types: reverse shell, bind shell, exec command, add user
    -   Multiple output formats (raw, C, Python)
    -   Manual shellcode templates for offline development
    -   Integration with Metasploit's msfvenom
-   **Buffer Overflow Detector:**
    -   Binary security feature analysis (Stack canary, NX, PIE, RELRO)
    -   Dangerous function detection (strcpy, gets, scanf, sprintf)
    -   Format string vulnerability scanning
    -   ASLR status detection
    -   Comprehensive vulnerability reports

### Configuration Management System (NEW)

Streamline workflow with saved configurations and quick launch:

-   **Profile Management:**
    -   Save current platform, JTAG adapter, and architecture settings
    -   Load saved profiles for quick configuration
    -   Multiple profile support
-   **Quick Launch Workflows:**
    -   Quick Password Recovery (ISR pre-configured)
    -   Quick JTAG Boot Intercept
    -   Quick Firmware Extract & Modify
    -   Quick Vulnerability Scan
    -   Quick ROP Chain Development
    -   One-command access to common workflows

### Live Memory Manipulation During Boot (NEW)

Powerful runtime memory and register manipulation via JTAG:

-   **Memory Poke/Peek:**
    -   Read memory at any address (with hex dump)
    -   Write arbitrary values to memory
    -   Dump memory ranges
    -   Fill memory with patterns (NOP sleds, etc.)
-   **Register Manipulation:**
    -   Read all CPU registers
    -   Read/modify specific registers
    -   Set Program Counter (redirect execution)
    -   Modify Stack Pointer
    -   Real-time register dumps
-   **Runtime Code Injection:**
    -   Inject ARM/MIPS shellcode during execution
    -   Inject code from files
    -   Create NOP sleds at runtime
    -   Load custom payloads into memory
    -   Experimental feature for advanced exploitation

### Reverse Engineering & Analysis Menu

-   **Automated Filesystem Analysis:** A powerful feature that performs a security sweep on a `binwalk`-extracted filesystem. It automatically finds sensitive files, searches for hardcoded credentials, and analyzes executables.
-   **Bootloader Signature Scanning:** Scans memory dumps for the signatures of common bootloaders like U-Boot and CFe.

### Firmware Manipulation Menu

-   **JTAG Flash Writing (DANGEROUS):** Provides the ability to write a firmware image (`*.bin`) directly to the device's flash memory via JTAG. This is a powerful tool for installing custom or patched firmware, but can permanently brick the device if used incorrectly.
-   **Configuration Auditing:** Dumps and analyzes Cisco configurations for security weaknesses.

### ROMMON Recovery Menu

-   **Platform-Specific Password Resets:** Automated workflows for both Cisco ISR and ASA.

## Requirements

-   **Root Privileges:** Required for low-level hardware access.
-   **Core Dependencies:** `bash`, `stty`, `timeout`, `logger`, `lsusb`, `find`.
-   **Analysis Dependencies:** `strings`, `binwalk`, `hexdump`, `grep`, `awk`.
-   **JTAG Dependencies:** `openocd`.
-   **Firmware Modification Dependencies:** `binwalk`, `xxd`, `dd` (for firmware workshop features).

## Usage

1.  Ensure all dependencies are installed.
2.  Connect your hardware (JTAG cable and/or serial console).
3.  Run as root: `./cisco_recovery.sh`
4.  Follow the TUI prompts.

### Automated Boot Interception Workflow

For JTAG-assisted password recovery on locked ISR devices:

1. Configure Platform and JTAG adapter (menu option 1)
2. Select "JTAG Cable Assisted Recovery" (menu option 4)
3. Choose "Automated Boot Interception" (option 4)
4. Power cycle the device when prompted
5. Wait for automatic boot interruption (CPU will halt)
6. Select recovery option from post-interrupt menu:
   - Option 2 for config register password reset (recommended)
   - Option 1 for NVRAM credential extraction
   - Option 6 to drop to manual console
7. After modifications, resume boot (option 8) or keep halted for further analysis

### Firmware Modification Workshop Workflow

For custom firmware development:

1. Navigate to "Firmware Modification Workshop" (menu option 5)
2. **Analyze existing firmware:**
   - Use "Firmware Unpacker & Analyzer" (option 1)
   - Choose full extraction (option 2) to extract filesystem
   - Analyze for credentials, configs, and binaries
3. **Modify firmware:**
   - Use "Binary Firmware Patcher" (option 2)
   - Choose patch type (string replacement, hex editing, NOP injection)
   - Creates `.patched` file automatically
4. **Flash modified firmware:**
   - Use "Firmware Flash Workflow" (option 3)
   - Choose full workflow for dump → modify → flash
   - Or use quick patch for simple string replacements

**Advanced: Boot Intercept Integration:**
- Start boot interception (Main → 4 → 4)
- When halted, dump firmware (option 3)
- Exit to Firmware Workshop (option 5)
- Patch dumped firmware
- Return to boot interception or use JTAG flash

### Advanced Firmware Analysis Workflow

For comprehensive firmware security analysis:

1. Navigate to "Advanced Firmware Analysis Suite" (menu option 6)
2. **Automated Teardown:**
   - Use "Automated Firmware Teardown" (option 1)
   - Provide path to firmware file
   - Review comprehensive 6-step analysis
   - Check session directory for organized reports
3. **Compare Firmware Versions:**
   - Use "Binary Firmware Differ" (option 2)
   - Provide paths to original and modified firmware
   - Review string differences, hex diffs, and embedded file changes
4. **Security Scanning:**
   - Use "Vulnerability Scanner" (option 3)
   - Scan for hardcoded credentials, weak crypto, and dangerous functions
   - Review findings in vulnerability report directory

### Bootloader Development Workflow

For U-Boot modification and bootloader chain creation:

1. Navigate to "Bootloader Development Kit" (menu option 7)
2. **Modify U-Boot:**
   - Use "U-Boot Modifier" (option 1)
   - Provide path to U-Boot image
   - Choose modification type:
     - Option 2: Modify boot commands
     - Option 3: Patch environment variables
     - Option 5: Change network settings
   - Save modified U-Boot (.modified file created)
3. **Build Bootloader Chain:**
   - Use "Bootloader Chain Builder" (option 2)
   - Define Stage 1 bootloader (option 1)
   - Define Stage 2 bootloader (option 2)
   - Define Kernel/Firmware (option 3)
   - Set load addresses and entry points (option 4)
   - Generate U-Boot script (option 5)
   - Create combined image (option 6)
   - Export configuration (option 8)

**Advanced: Combined Workflow:**
- Analyze existing U-Boot with Firmware Analysis Suite
- Modify U-Boot with U-Boot Modifier
- Build complete boot chain with Chain Builder
- Flash via JTAG or deploy to device

## Disclaimer

This tool contains dangerous features, especially:
- JTAG memory/flash write functions
- JTAG bootloader recovery
- JTAG memory patching
- Configuration register manipulation

These operations can cause irreversible damage to the target device and may permanently brick it. The user assumes all responsibility for any actions performed by this script. **Use with extreme caution and only on authorized devices.**
