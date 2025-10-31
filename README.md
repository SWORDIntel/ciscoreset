# Cisco ISR 4321 Recovery and Management Tool

This script is a powerful, TUI-driven utility for managing a Cisco ISR 4321 router. It offers two primary modes of operation: **ROMMON Recovery** for disaster recovery scenarios and **Live System Management** for routine administrative tasks.

## Modes of Operation

1.  **ROMMON Recovery (Default):** The primary mode, designed for situations where the router's password is lost or the operating system cannot boot. It automates the process of interrupting the boot sequence to access the `rommon` prompt and provides a menu of recovery tools.
2.  **Live System Management:** For interacting with a fully booted and operational router. This mode requires credentials but allows for administrative tasks like backing up the current firmware.

---

## Features

### ROMMON Recovery

-   **Automated ROMMON Access:** Automatically sends a `BREAK` signal to interrupt the boot process.
-   **Password Reset:** A guided, automated TUI for the standard Cisco password recovery procedure.
-   **Change Boot Variables:** View and modify `rommon` environment variables like `CONFREG`.
-   **Load Firmware from TFTP:** A guided process to load and boot a new IOS-XE firmware image from a TFTP server.
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

## Usage

1.  **Hardware Connection:** Connect the GND, RX, and TX pins of your serial adapter to the router's debug header. **DO NOT** connect the VCC pin.

2.  **Running the Script:**
    -   Make the script executable: `chmod +x cisco_recovery.sh`
    -   Run the script: `./cisco_recovery.sh [OPTIONS]`
    -   You will be prompted to choose a mode of operation upon startup.

### Command-Line Options

-   `--device <path>`: The path to the serial device (e.g., `/dev/ttyUSB0`). Default: `/dev/ttyS0`.
-   `--baud <rate>`: The baud rate for the serial connection. Default: `9600`.
-   `--help`: Display a help message.

---

## Disclaimer

This tool interacts directly with the router's bootloader and operating system. Use it with caution. Incorrect commands can lead to a non-functional device. The author is not responsible for any damage caused by the use of this script.
