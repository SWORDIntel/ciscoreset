# Cisco & Generic Embedded Advanced Recovery Tool v2.2

## Overview

This script is a professional-grade, TUI-driven framework for multi-vector interaction with Cisco and other embedded devices (including MIPS-based hardware). It combines serial console recovery methods with advanced JTAG exploitation, dynamic device detection, and post-exploitation analysis.

## Features

-   **Multi-Platform Support:** Targets Cisco ISR (ARM), Cisco ASA, and generic MIPS32-based devices.
-   **Dynamic Device Detection:** Automatically scans for and identifies a wide range of USB-to-Serial and JTAG adapters, including FTDI, CH341, and J-Link.
-   **TUI-Driven:** A full Text-based User Interface for all operations.
-   **Session Logging & Configuration:** Supports session logging and an external configuration file.

### Reverse Engineering & Analysis

-   **Bootloader Signature Scanning:** A key reverse engineering feature that scans a memory dump for the signatures of common bootloaders like U-Boot and CFe, helping to quickly identify the target's firmware.
-   **Memory Analysis:** Scans memory dumps for credentials, IPs, and embedded files (`binwalk`).
-   **Configuration Auditing:** Dumps and analyzes Cisco configurations for security weaknesses.

### JTAG Exploitation Menu

-   **Multi-Architecture Profiles:** Provides distinct initialization profiles for ARM (Cisco) and generic MIPS32 targets.
-   **Core JTAG Functions:** Includes chain scanning, memory dumping, and flash extraction.

### ROMMON Recovery Menu

-   **Platform-Specific Password Resets:** Automated workflows for both Cisco ISR and ASA.

## Requirements

-   **Root Privileges:** Required for low-level hardware access.
-   **Core Dependencies:** `bash`, `stty`, `timeout`, `logger`, `lsusb`.
-   **Analysis Dependencies:** `strings`, `binwalk`, `hexdump`.
-   **JTAG Dependencies:** `openocd`.

## Usage

1.  Ensure all dependencies are installed.
2.  Connect your hardware.
3.  Run as root: `./cisco_recovery.sh`
4.  Follow the TUI prompts to select your device, connection method, and desired operation.

## Disclaimer

This is a powerful security and recovery tool. Use with extreme caution.
