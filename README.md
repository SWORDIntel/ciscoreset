# Cisco & Generic Embedded Advanced Recovery Tool v2.3

## Overview

This script is a professional-grade, TUI-driven framework for multi-vector interaction with Cisco and other embedded devices. It combines serial console recovery, advanced JTAG exploitation, and powerful post-exploitation analysis for hardware reverse engineering and security auditing.

## Features

-   **Multi-Platform & Multi-Architecture:** Targets Cisco ISR (ARM), ASA, and generic MIPS32 devices.
-   **Dynamic Device Detection:** Scans for and identifies a wide range of serial and JTAG adapters.
-   **Session Logging & Configuration:** Supports session logging and an external config file.

### JTAG Exploitation Menu

-   **Data Exfiltration:** Includes tools for dumping memory regions and extracting the full contents of flash memory via JTAG.
-   **Multi-Architecture Profiles:** Provides distinct initialization profiles for ARM and MIPS targets.

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
2.  Connect your hardware.
3.  Run as root: `./cisco_recovery.sh`
4.  Follow the TUI prompts.

## Disclaimer

This tool contains dangerous features, especially the JTAG memory write function. It can cause irreversible damage to the target device. The user assumes all responsibility for any actions performed by this script. **Use with extreme caution.**
