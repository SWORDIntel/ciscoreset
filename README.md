# Cisco ISR 4321 Recovery and Management Tool

This script is a powerful, TUI-driven utility for managing a Cisco ISR 4321 router. It offers two primary modes of operation: **ROMMON Recovery** for disaster recovery scenarios and **Live System Management** for routine administrative tasks.

## Modes of Operation

1.  **ROMMON Recovery (Default):** The primary mode, designed for situations where the router's password is lost or the operating system cannot boot. It automates the process of interrupting the boot sequence to access the `rommon` prompt and provides a menu of recovery tools.
2.  **Live System Management:** For interacting with a fully booted and operational router. This mode requires credentials but allows for administrative tasks like backing up the current firmware.

---

## Features

### ROMMON Recovery

-   **Password Reset:** A guided, automated TUI for the standard Cisco password recovery procedure.
-   **Storage Inspector:** A utility to list available storage devices (`dev`) and view the files on them (`dir`).
-   **Manual Boot from File:** An interactive tool to manually boot a specific firmware image from storage, useful when the `BOOT` variable is not set correctly.
-   **Load Firmware from TFTP:** A guided process to load and boot a new IOS-XE firmware image from a TFTP server.
-   **Change Boot Variables:** A menu to view and modify `rommon` environment variables like `CONFREG` and `BOOT`.
-   **ROMMON Upgrade Helper:** Provides guidance and a safety mechanism to help prepare for a ROMMON software upgrade by setting a known-good `BOOT` variable.
-   **Raw Shell:** Provides direct, interactive access to the `rommon` prompt for manual commands.

### Live System Management

-   **Backup Firmware to TFTP:** Securely back up the router's current running firmware image from its flash storage to a TFTP server.

---

## Requirements

-   A Linux-based host machine with Bash and standard coreutils.
-   **Python 3.x:** Required for the `tcsendbreak` system call used in ROMMON Recovery mode.
-   A USB-to-TTL serial adapter (e.g., CP2102/FTDI-style).
-   Physical access to the Cisco ISR 4321 router's internal debug header.

---
## Usage and Command-Line Options
... (This section remains the same) ...
---

## Disclaimer
... (This section remains the same) ...
