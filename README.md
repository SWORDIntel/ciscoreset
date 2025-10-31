# Cisco ISR & ASA Advanced Recovery Tool v2.1

## Overview

This script is a professional-grade, TUI-driven framework for multi-vector interaction with Cisco ISR and ASA devices. It combines standard serial console recovery methods with placeholders for advanced JTAG exploitation and post-exploitation analysis.

## Features

-   **TUI-Driven:** A full Text-based User Interface for all operations.
-   **Platform Auto-Detection:** Automatically sniffs serial boot messages to identify the connected device (ISR vs. ASA).
-   **Session Logging:** All commands and responses are logged to a timestamped session file in `/var/log/cisco_tool_sessions`.
-   **Configuration File:** Supports an optional configuration file at `/etc/cisco_tool.conf` to override default settings.

### ROMMON Recovery Menu

-   **Automated ROMMON Entry:** A function to send the break sequence to interrupt the boot process.
-   **Platform-Specific Password Resets:** Dedicated, automated workflows for recovering passwords on both Cisco ISR and ASA devices.

### Analysis & Auditing

-   **Configuration Dumper:** A tool to download the `running-config` and `startup-config` from a live device for offline analysis.
-   **(Planned) Memory Analysis:** Placeholder for analyzing memory dumps.
-   **(Planned) JTAG Exploitation:** Placeholders for JTAG-based interaction.

## Requirements

-   **Root Privileges:** The script must be run as root.
-   **Core Dependencies:** `bash`, `stty`, `timeout`, `logger`.
-   **Hardware:** An appropriate serial and/or JTAG adapter.

## Usage

1.  Ensure all dependencies are installed.
2.  Connect your hardware.
3.  Run the script as root: `./cisco_recovery.sh`
4.  Follow the TUI prompts.

## Disclaimer

This is a powerful security and recovery tool. Use with extreme caution.
