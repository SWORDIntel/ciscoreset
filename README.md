# Cisco ISR 4321 Advanced Recovery Tool v2.0

## Overview

This script is a professional-grade, TUI-driven framework for multi-vector interaction with Cisco ISR 4321 routers. It combines standard serial console recovery methods with advanced JTAG-based exploitation, dynamic device detection, and post-exploitation analysis capabilities.

## Features

-   **Dynamic Device Detection:** Automatically scans for and identifies connected USB-to-Serial adapters and JTAG interfaces (`ftdi`, `jlink`, `stlink`).
-   **Multi-Vector Connectivity:** Supports Serial, JTAG, or combined Serial+JTAG sessions.
-   **Session Logging:** All commands sent and data received are logged to a timestamped session file in `/var/log/cisco_tool_sessions` for a complete audit trail.
-   **Configuration File:** Highly configurable via `/etc/cisco_tool.conf`, allowing overrides for baud rates, directories, and custom JTAG TAP IDs.

### ROMMON Recovery Menu

-   **Automated ROMMON Entry:** Multiple methods to enter `rommon` mode.
-   **Advanced Password Recovery:** A fully automated routine to bypass the startup config, reset all standard passwords, and restore the configuration register.
-   **Firmware & Storage Tools:** Utilities for inspecting storage, loading firmware via TFTP, and manually booting from a file.

### JTAG Exploitation Menu

-   **JTAG Chain Scanning:** Detects and identifies TAPs on the JTAG chain.
-   **Memory Dumping:** Dumps arbitrary memory regions from the device via JTAG for offline analysis.
-   **Flash Extraction:** Extracts the full contents of the onboard flash memory.
-   **Live Payload Injection:** (Experimental) Can inject shellcode to bypass password checks.

### Post-Exploitation Analysis

-   **Memory Analysis:** Scans memory dumps using `strings` and `binwalk` to automatically find credentials, IPs, and embedded files.
-   **Configuration Auditing:** Dumps the `running-config` and `startup-config` and analyzes them for common security weaknesses like plaintext passwords, weak hashes, and insecure protocols.

## Requirements

-   **Root Privileges:** The script must be run as root.
-   **Core Dependencies:** `bash`, `stty`, `timeout`, `logger`, `udevadm`.
-   **Analysis Dependencies:** `strings`, `binwalk` (for `menu_memory_analysis`).
-   **JTAG Dependencies:** `openocd`, `jtag` (UrJTAG), or `JLinkExe`, depending on your adapter.
-   **Hardware:** An appropriate serial and/or JTAG adapter.

## Configuration

Create the file `/etc/cisco_tool.conf` to override default settings. An example configuration is available in `cisco_tool.conf.example`.

## Usage

1.  Ensure all dependencies are installed.
2.  Connect your hardware.
3.  Run the script as root: `./cisco_recovery.sh`
4.  Follow the TUI prompts to select your devices and desired operations.

## Disclaimer

This is a powerful security and recovery tool. It can cause irreversible damage to the target device if used improperly. The user assumes all responsibility for any actions performed by this script. **Use with extreme caution.**
