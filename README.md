# Unified VLAN Management Tool

This script provides a single, easy-to-use interface for provisioning VLANs across a multi-vendor network stack, including Nortel, Cisco ISR, and Cisco ASA devices.

It uses a simple TUI to ask which device you want to configure and then reads the desired configuration from a device-specific text file.

## Features

-   **Unified Interface:** Manage VLANs on Nortel, Cisco ISR, and Cisco ASA from a single script.
-   **Simple, Declarative Config:** Uses easy-to-understand, separate configuration files for each device type.
-   **Automated Interaction:** Handles the specific connection, login, and command execution for each device's unique interface (Nortel menu vs. Cisco CLI).

## Requirements

-   A Linux-based host machine with `bash`.
-   A USB-to-TTL serial adapter for console access.

## Usage

1.  **Create Config Files:** Create one or more of the following files in the same directory as the script: `nortel_vlans.txt`, `isr_vlans.txt`, `asa_vlans.txt`. (See formats below).

2.  **Run the Script:**
    Make the script executable (`chmod +x vlan_manager.sh`) and run it, providing the path to your serial device:
    ```bash
    ./vlan_manager.sh --device /dev/ttyUSB0
    ```
    The script will prompt you to select a device and then ask for the necessary credentials.

---

## Configuration File Formats

### `nortel_vlans.txt`

For Nortel 5520 series switches. Each line is a comma-separated list of key-value pairs.
-   **Keys:** `VLAN`, `NAME`, `PORTS`, `TAG`.
-   **Example:** `VLAN=100, NAME=SERVERS, PORTS=1-12, TAG=48`

### `isr_vlans.txt`

For Cisco ISR routers running IOS. This file contains the exact sequence of commands needed to create the VLANs and their names, as you would type them in `configure terminal` mode.
-   **Example:**
    ```
    vlan 10
     name VOICE
    vlan 20
     name DATA
    ```

### `asa_vlans.txt`

For Cisco ASA firewalls. This file is similar to the ISR file but typically only involves the VLAN ID and name. Interface assignments, `nameif`, and `security-level` are handled separately.
-   **Example:**
    ```
    vlan 10
     name DMZ-SERVERS
    vlan 15
     name GUEST-WIFI
    ```
