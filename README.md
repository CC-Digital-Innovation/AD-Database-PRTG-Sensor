# Active Directory Database Monitoring PRTG Sensor

## Overview
This PowerShell script creates a custom PRTG sensor that monitors key metrics of Active Directory NTDS databases on domain controllers. It measures database size, estimated whitespace, drive usage, and available free space, presenting the results in PRTG-compatible format with appropriate thresholds.

## Features
* Retrieves AD database size and location from the remote domain controller
* Calculates database whitespace percentage (estimated)
* Monitors database drive free space and usage percentage
* Configurable warning and error thresholds for all metrics
* Outputs results in PRTG-compatible XML format
* Supports both hostnames and IP addresses through automatic connection method detection
* Detailed error handling with specific error codes

## Prerequisites
* PowerShell 5.1 or later
* PRTG Network Monitor
* Domain controller running Active Directory Domain Services
* Account with administrative permissions on the monitored domain controllers

## Installation
1. Save the script file (e.g., `AD-Database-Sensor.ps1`) on your PRTG probe server in the custom sensors directory:
   ```
   C:\Program Files (x86)\PRTG Network Monitor\Custom Sensors\EXEXML\
   ```

## Usage
To use this script as a PRTG sensor:

1. In PRTG, add a new sensor to your domain controller device and choose "EXE/Script Advanced" sensor type.
2. Set the sensor to use the script file name (e.g., `AD-Database-Sensor.ps1`).
3. In the "Parameters" field, enter: `-ComputerName "%host" -Username "%windowsuser" -Password "%windowspassword"`
4. In your device settings, configure Windows credentials with sufficient permissions to access the domain controller.

## Parameters
* `ComputerName`: The hostname or IP address of the domain controller to monitor.
* `Username`: The username for authentication to the remote server.
* `Password`: The password for authentication to the remote server.

## Outputs
This script outputs PRTG sensor results with the following channels:

* **AD Database Size (MB)**: Current NTDS database size in megabytes
* **AD Database Whitespace (MB)**: Estimated whitespace in megabytes 
* **AD Database Whitespace (%)**: Whitespace as a percentage of total database size
* **Database Drive Free Space (MB)**: Available free space on the drive hosting the database
* **Database Drive Usage (%)**: Percentage of drive space used

## Default Thresholds

| Channel | Warning | Error |
|---------|---------|-------|
| AD Database Size | 15,000 MB | 20,000 MB |
| AD Database Whitespace (%) | 30% | 40% |
| Database Drive Free Space | 10,000 MB | 5,000 MB |
| Database Drive Usage | 85% | 95% |

## Customization
You can adjust the warning and error thresholds in two ways:

1. **In the script**: Modify the appropriate values in the XML output section of the script.
2. **In PRTG**: Thresholds can also be adjusted directly through the PRTG web interface by editing the sensor's channel settings, which is often more convenient for making per-sensor adjustments without modifying the script.

## IP Address Support
The script automatically detects when an IP address is provided instead of a hostname and uses direct CIM/WMI queries instead of PowerShell remoting. This avoids issues with WinRM's default restrictions on IP address connections.

## Error Handling
The script provides detailed error information with specific error codes to help troubleshoot connectivity or permission issues:

| Error Code | Description |
|------------|-------------|
| 1 | General error |
| 2 | Access denied (credential issues) |
| 3 | Path not found (AD not installed) |
| 4 | Cannot connect to server |
| 5 | Connection timeout |
| 6 | RPC server unavailable |
| 7 | WinRM IP address connection issue |

## Notes
* Author: Richard Travellin
* Date: April 2, 2025
* Version: 2.0

## License
MIT

## Contributing
Contributions to this project are welcome. Please fork the repository and submit a pull request with your changes.

## Support
For support, please open an issue in the GitHub repository.
