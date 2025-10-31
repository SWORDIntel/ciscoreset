# Cisco ISR 4321 Recovery and Management Tool

This script is a powerful, menu-driven utility for managing a Cisco ISR 4321 router in a recovery (ROMMON) state. It provides a Text-based User Interface (TUI) to automate common recovery tasks that are typically performed over a serial console connection.

## Features

- **Automated ROMMON Access:** The script automatically sends the `BREAK` signal to interrupt the router's boot process and access the `rommon` prompt.
- **Menu-Driven Interface:** Once in `rommon`, the script presents a clear, interactive menu with the following options:
  - **Password Reset:** Automates the standard Cisco password recovery procedure.
  - **Change Boot Variables:** Allows you to view and modify `rommon` environment variables, such as the `confreg`.
  - **Load Firmware from TFTP:** Guides you through the process of loading a new IOS-XE firmware image from a TFTP server.
  - **Raw Shell:** Provides direct, interactive access to the `rommon` prompt for manual command execution.
- **Configurable:** The serial device and baud rate can be easily configured using command-line arguments.

## Requirements

- A Linux-based host machine with Bash and standard coreutils.
- **Python 3.x:** Required for the `tcsendbreak` system call to interrupt the router's boot process.
- A USB-to-TTL serial adapter (e.g., CP2102/FTDI-style).
- Physical access to the Cisco ISR 4321 router's internal debug header.

## Usage

1.  **Hardware Connection:**
    - Connect the GND, RX, and TX pins of your serial adapter to the corresponding pins on the router's debug header. **DO NOT** connect the VCC pin.
    - Connect the USB end of the adapter to your host machine.

2.  **Running the Script:**
    - Make the script executable: `chmod +x cisco_recovery.sh`
    - Run the script, optionally specifying the serial device and baud rate:
      ```bash
      ./cisco_recovery.sh [OPTIONS]
      ```

### Command-Line Options

- `--device <path>`: The path to the serial device (e.g., `/dev/ttyUSB0`). Default: `/dev/ttyS0`.
- `--baud <rate>`: The baud rate for the serial connection. Default: `9600`.
- `--help`: Display a help message.

### Example

```bash
./cisco_recovery.sh --device /dev/ttyUSB0 --baud 9600
```

## Disclaimer

This tool interacts directly with the router's bootloader. Use it with caution. Incorrect use of `rommon` commands can lead to a non-functional device. The author is not responsible for any damage caused by the use of this script.
