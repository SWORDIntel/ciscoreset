# Cisco & Generic Embedded Advanced Recovery Tool v2.6

## Overview

This script is a professional-grade, TUI-driven framework for multi-vector interaction with Cisco and other embedded devices. It combines serial console recovery, advanced JTAG exploitation, JTAG cable assisted recovery, and powerful post-exploitation analysis for hardware reverse engineering and security auditing.

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

## Disclaimer

This tool contains dangerous features, especially:
- JTAG memory/flash write functions
- JTAG bootloader recovery
- JTAG memory patching
- Configuration register manipulation

These operations can cause irreversible damage to the target device and may permanently brick it. The user assumes all responsibility for any actions performed by this script. **Use with extreme caution and only on authorized devices.**
