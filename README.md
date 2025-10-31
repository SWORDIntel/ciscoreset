# Nortel 5520 Automated VLAN Provisioner

This script automates the configuration of VLANs and port assignments on a Nortel 5520 series switch. It reads a simple text file (`vlan_config.txt`) that defines the desired VLANs, names, and port mappings, and then connects to the switch's serial console to execute the necessary menu commands.

## Features

-   **Automated Configuration:** Drastically reduces the manual effort required to provision VLANs.
-   **Declarative Configuration:** Define your entire VLAN setup in a simple, human-readable text file.
-   **Supports Tagged and Untagged Ports:** Can configure ports as members of a VLAN and also tag them for trunking.

## Requirements

-   A Linux-based host machine with `bash`.
-   A USB-to-TTL serial adapter.
-   Console access to a Nortel 5520 series switch.

## Usage

1.  **Create `vlan_config.txt`:**
    Create a file named `vlan_config.txt` in the same directory as the script. Define your VLANs in this file using the format below.

2.  **Run the Script:**
    Make the script executable (`chmod +x nortel_vlan_provisioner.sh`) and run it, providing the path to your serial device:
    ```bash
    ./nortel_vlan_provisioner.sh --device /dev/ttyUSB0
    ```
    The script will prompt you for the switch's username and password before proceeding.

## `vlan_config.txt` Format

Each line in the file represents one VLAN. The format is a comma-separated list of key-value pairs.

**Required Keys:**
-   `VLAN`: The VLAN ID (e.g., `100`).
-   `PORTS`: The port range to be assigned to this VLAN (e.g., `1-12`, `13,15,17-20`).

**Optional Keys:**
-   `NAME`: A descriptive name for the VLAN (e.g., `SERVERS`).
-   `TAG`: A port range to be tagged for this VLAN (e.g., `47-48`).

### Example `vlan_config.txt`

```
VLAN=100, NAME=SERVERS, PORTS=1-12, TAG=48
VLAN=200, NAME=WORKSTATIONS, PORTS=13-24
VLAN=300, NAME=GUEST, PORTS=25-47, TAG=48
```
