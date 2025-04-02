<#
.SYNOPSIS
    Monitors Active Directory database metrics and outputs the results to PRTG.
.DESCRIPTION
    This script gathers key metrics about an Active Directory NTDS database on a domain controller,
    including database size, estimated whitespace, and drive space information. It works with both 
    hostnames and IP addresses, supporting remote monitoring through WMI/CIM or PowerShell remoting.
    The results are formatted as PRTG-compatible XML for integration with PRTG Network Monitor.
.PARAMETER ComputerName
    The hostname or IP address of the domain controller to monitor.
.PARAMETER Username
    The username for authentication to the remote server.
.PARAMETER Password
    The password for authentication to the remote server.
.INPUTS
    None.
.OUTPUTS
    Outputs PRTG sensor results with information on the AD database size, whitespace, and drive statistics.
.NOTES
    Author: Richard Travellin
    Date: 4/2/2025
    Version: 2.0
    
    The script automatically detects if an IP address is used instead of a hostname and
    adapts its connectivity method accordingly to avoid WinRM restrictions on IP addresses.
.EXAMPLE
    ./AD-Database-Sensor.ps1 -ComputerName "dc01.domain.local" -Username "domain\admin" -Password "P@ssw0rd"
    
    This example runs the script to check AD database metrics on the specified domain controller using its hostname.
.EXAMPLE
    ./AD-Database-Sensor.ps1 -ComputerName "192.168.1.10" -Username "administrator" -Password "P@ssw0rd"
    
    This example runs the script to check AD database metrics on the specified domain controller using its IP address.
#>

# Parameters for remote server
param (
    [Parameter(Mandatory=$true)]
    [string]$ComputerName,
    
    [Parameter(Mandatory=$true)]
    [string]$Username,
    
    [Parameter(Mandatory=$true)]
    [string]$Password
)

try {
    # Format domain credentials if needed (add domain name if not present)
    if ($Username -notmatch '\\') {
        $Username = "WORKGROUP\$Username"
    }
    
    # Create credential object
    $securePassword = ConvertTo-SecureString -String $Password -AsPlainText -Force
    $credentials = New-Object System.Management.Automation.PSCredential ($Username, $securePassword)
    
    # Check if ComputerName is an IP address
    $isIPAddress = [bool]($ComputerName -as [System.Net.IPAddress])
    
    # If this is an IP address, we'll use WMI/CIM directly instead of Invoke-Command
    if ($isIPAddress) {
        Write-Verbose "IP address detected. Using direct CIM/WMI queries instead of Invoke-Command."
        
        # Configure CIM session with appropriate options
        $cimOptions = New-CimSessionOption -Protocol Dcom
        $cimSession = New-CimSession -ComputerName $ComputerName -Credential $credentials -SessionOption $cimOptions
        
        # Get NTDS database path from registry
        $regPath = "SYSTEM\\CurrentControlSet\\Services\\NTDS\\Parameters"
        $dbPathValue = Invoke-CimMethod -CimSession $cimSession -Namespace "root\default" -ClassName StdRegProv -MethodName GetStringValue -Arguments @{
            hDefKey = [uint32]2147483650; # HKLM
            sSubKeyName = $regPath;
            sValueName = "DSA Database file"
        }
        
        if (-not $dbPathValue -or -not $dbPathValue.sValue) {
            throw "Failed to retrieve NTDS database path"
        }
        
        $adDbPath = $dbPathValue.sValue
        
        # Get file info
        $dbFile = Get-CimInstance -CimSession $cimSession -ClassName CIM_DataFile -Filter "Name='$($adDbPath.Replace('\','\\'))'" -Property FileSize
        
        # Get drive info
        $driveLetter = $adDbPath.Substring(0, 1) + ":"
        $driveInfo = Get-CimInstance -CimSession $cimSession -ClassName Win32_LogicalDisk -Filter "DeviceID='$driveLetter'" -Property Size,FreeSpace
        
        # Calculate values
        $dbSizeMB = [Math]::Round(($dbFile.FileSize / 1MB), 2)
        $estimatedWhitespacePercentage = 20
        $whitespaceMB = [Math]::Round(($dbSizeMB * $estimatedWhitespacePercentage / 100), 2)
        
        $driveFreeSpaceMB = [Math]::Round(($driveInfo.FreeSpace / 1MB), 2)
        $driveTotalSpace = $driveInfo.Size
        $driveUsedPercentage = [Math]::Round((($driveTotalSpace - $driveInfo.FreeSpace) / $driveTotalSpace * 100), 2)
        
        # Create results object
        $results = @{
            DatabaseSizeMB = $dbSizeMB
            WhitespaceMB = $whitespaceMB
            WhitespacePercentage = $estimatedWhitespacePercentage
            DriveFreeSpaceMB = $driveFreeSpaceMB
            DriveUsedPercentage = $driveUsedPercentage
            DatabasePath = $adDbPath
        }
    }
    else {
        # For hostnames, we can use Invoke-Command which is more efficient
        $results = Invoke-Command -ComputerName $ComputerName -Credential $credentials -ScriptBlock {
            param()
            
            # Get NTDS database path from registry - using direct registry access for speed
            $regPath = "SYSTEM\CurrentControlSet\Services\NTDS\Parameters"
            $adDbPath = (Get-ItemProperty -Path "HKLM:\$regPath" -Name "DSA Database file" -ErrorAction Stop)."DSA Database file"
            
            if (-not $adDbPath) {
                throw "Failed to retrieve NTDS database path"
            }
            
            # Get only the required properties for efficiency
            $driveLetter = $adDbPath.Substring(0, 1) + ":"
            
            # Use direct .NET methods instead of jobs for better performance
            # Get file size using System.IO for speed
            $dbSize = (New-Object System.IO.FileInfo($adDbPath)).Length
            
            # Get drive info directly using WMI with specific properties selection
            $driveInfo = Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='$driveLetter'" | 
                        Select-Object -Property @{Name='Free';Expression={$_.FreeSpace}}, 
                                                @{Name='Used';Expression={$_.Size - $_.FreeSpace}}
            
            # Calculate values directly to avoid temporary variables
            $dbSizeMB = [Math]::Round(($dbSize / 1MB), 2)
            $estimatedWhitespacePercentage = 20
            $whitespaceMB = [Math]::Round(($dbSizeMB * $estimatedWhitespacePercentage / 100), 2)
            
            $driveTotalSpace = $driveInfo.Free + $driveInfo.Used
            $driveFreeSpaceMB = [Math]::Round(($driveInfo.Free / 1MB), 2)
            $driveUsedPercentage = [Math]::Round(($driveInfo.Used / $driveTotalSpace * 100), 2)
            
            # Return a single object with all results
            return @{
                DatabaseSizeMB = $dbSizeMB
                WhitespaceMB = $whitespaceMB
                WhitespacePercentage = $estimatedWhitespacePercentage
                DriveFreeSpaceMB = $driveFreeSpaceMB
                DriveUsedPercentage = $driveUsedPercentage
                DatabasePath = $adDbPath
            }
        }
    }
    
    # Format values for PRTG 
    $xmlOutput = @"
<?xml version="1.0" encoding="UTF-8" ?>
<prtg>
    <result>
        <channel>AD Database Size (MB)</channel>
        <value>$($results.DatabaseSizeMB)</value>
        <float>1</float>
        <unit>Custom</unit>
        <customunit>MB</customunit>
        <limitmode>1</limitmode>
        <limitmaxwarning>15000</limitmaxwarning>
        <limitmaxerror>20000</limitmaxerror>
    </result>
    <result>
        <channel>AD Database Whitespace (MB)</channel>
        <value>$($results.WhitespaceMB)</value>
        <float>1</float>
        <unit>Custom</unit>
        <customunit>MB</customunit>
    </result>
    <result>
        <channel>AD Database Whitespace (%)</channel>
        <value>$($results.WhitespacePercentage)</value>
        <float>1</float>
        <unit>Percent</unit>
        <limitmode>1</limitmode>
        <limitmaxwarning>30</limitmaxwarning>
        <limitmaxerror>40</limitmaxerror>
    </result>
    <result>
        <channel>Database Drive Free Space (MB)</channel>
        <value>$($results.DriveFreeSpaceMB)</value>
        <float>1</float>
        <unit>Custom</unit>
        <customunit>MB</customunit>
        <limitmode>1</limitmode>
        <limitminwarning>10000</limitminwarning>
        <limitminwarning>5000</limitminwarning>
    </result>
    <result>
        <channel>Database Drive Usage (%)</channel>
        <value>$($results.DriveUsedPercentage)</value>
        <float>1</float>
        <unit>Percent</unit>
        <limitmode>1</limitmode>
        <limitmaxwarning>85</limitmaxwarning>
        <limitmaxerror>95</limitmaxerror>
    </result>
    <text>AD Database: $([Math]::Round($results.DatabaseSizeMB, 2)) MB, Whitespace: $([Math]::Round($results.WhitespaceMB, 2)) MB ($([Math]::Round($results.WhitespacePercentage, 2))%), Drive Free: $([Math]::Round($results.DriveFreeSpaceMB, 2)) MB</text>
</prtg>
"@
    
    Write-Host $xmlOutput
}
catch {
    # More granular error handling with specific error codes
    $errorCode = 1
    $errorMessage = $_.Exception.Message
    
    # Capture inner exception details if available
    if ($_.Exception.InnerException) {
        $errorMessage += " - Inner Exception: $($_.Exception.InnerException.Message)"
    }
    
    # Identify specific error conditions for better troubleshooting
    switch -Regex ($errorMessage) {
        "Access is denied" { 
            $errorCode = 2
            $errorMessage = "Access denied. Check credentials: $errorMessage" 
        }
        "Cannot find path|Path not found" { 
            $errorCode = 3
            $errorMessage = "Path not found. Check if server has Active Directory installed: $errorMessage" 
        }
        "Network path was not found|Unable to connect" { 
            $errorCode = 4
            $errorMessage = "Cannot connect to server. Check network connectivity: $errorMessage" 
        }
        "Timeout expired" { 
            $errorCode = 5
            $errorMessage = "Connection timeout: $errorMessage" 
        }
        "The RPC server is unavailable" { 
            $errorCode = 6
            $errorMessage = "RPC server unavailable. Check Windows Remote Management service: $errorMessage" 
        }
        "CannotUseIPAddress|TrustedHosts" {
            $errorCode = 7
            $errorMessage = "WinRM cannot connect to IP address. Try adding IP to TrustedHosts: $errorMessage"
        }
    }
    
    # Output error in PRTG XML format
    Write-Host @"
<?xml version="1.0" encoding="UTF-8" ?>
<prtg>
    <e>$errorCode</e>
    <text>Error monitoring AD database: $errorMessage</text>
</prtg>
"@
}
finally {
    # Clean up resources
    if ($cimSession) {
        Remove-CimSession $cimSession
    }
}
