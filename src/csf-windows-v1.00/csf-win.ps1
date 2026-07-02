# This sets the protection mode to '1', the recommended default.
reg add "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" /v SynAttackProtect /t REG_DWORD /d 1 /f

# 1. Increase the "half-open" connection queue (default is 100)
# This is the equivalent of 'tcp_max_syn_backlog'
reg add "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" /v TcpMaxHalfOpen /t REG_DWORD /d 4096 /f

# 2. Increase the "retried half-open" queue (default is 80)
reg add "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" /v TcpMaxHalfOpenRetried /t REG_DWORD /d 2048 /f

# 3. Reduce SYN-ACK retries (default is 3)
# This is the equivalent of 'tcp_synack_retries'. We'll set it to 2.
reg add "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" /v TcpMaxConnectResponseRetransmissions /t REG_DWORD /d 2 /f

netsh advfirewall firewall add rule name="MySQL Rate Limit" dir=in action=allow protocol=TCP localport=3306 security=authip profile=any limit=yes maxconnect=5/second

netsh advfirewall firewall add rule name="RDP Rate Limit" dir=in action=allow protocol=TCP localport=3389 security=authip profile=any limit=yes maxconnect=4/minute

<#
.SYNOPSIS
    Installs the Revolutionary Technology "LFD for Windows" Service.
    
    This creates a scheduled task that runs every 5 minutes to
    scan Security logs for failed RDP, SMB, and other network logins,
    and then permanently blocks the attacker's IP address.
#>

#Requires -RunAsAdministrator

Write-Host "Installing Revolutionary Technology LFD for Windows Service..." -ForegroundColor Green

# --- 1. Define the Monitoring Script (the "Daemon") ---
# This is the script that will be run by the scheduled task
$ScriptContent = @"
# Revolutionary Technology - LFD for Windows - Watchdog Script
# This script is run by a scheduled task. Do not run manually.

# --- Configuration ---
\$FailureThreshold = 5            # Block an IP after this many failures
\$TimeLimit = (Get-Date).AddMinutes(-5) # Look at events from the last 5 minutes (to match task schedule)
# --- End Configuration ---

# We are watching for:
#   Logon Type 10: RemoteInteractive (RDP)
#   Logon Type 3:  Network (SMB, IIS Windows Auth, Exchange, etc.)
\$LogonTypesToBlock = @(3, 10)

# Get all failed logon events (ID 4625)
\$FailedLogins = Get-WinEvent -FilterHashtable @{
    LogName = 'Security'
    Id = 4625
    StartTime = \$TimeLimit
} | Where-Object { 
    (\$LogonTypesToBlock -contains \$_.Properties[8].Value) -and 
    (\$_.Properties[19].Value -ne '::1') -and 
    (\$_.Properties[19].Value -ne '127.0.0.1') -and
    (\$_.Properties[19].Value -ne '-') # Ignore non-IP sources
}

if (\$null -eq \$FailedLogins) {
    exit # No failures found
}

# Group by IP address and count the failures
\$BadIPs = \$FailedLogins | Group-Object { \$_.Properties[19].Value } | Where-Object { \$_.Count -ge \$FailureThreshold }

if (\$null -eq \$BadIPs) {
    exit # No IPs exceeded the threshold
}

# Block each bad IP
foreach (\$ip in \$BadIPs) {
    \$IPAddress = \$ip.Name
    if (\$null -eq \$IPAddress -or \$IPAddress -eq "") { continue }
    
    \$RuleName = "RT-LFD Block - \$IPAddress"
    
    # Check if a rule for this IP already exists
    if (-not (Get-NetFirewallRule -DisplayName \$RuleName -ErrorAction SilentlyContinue)) {
        
        # Create the new firewall rule
        # This rule blocks ALL inbound traffic from the attacker's IP
        New-NetFirewallRule -DisplayName \$RuleName `
            -Description "Auto-blocked by Revolutionary Technology LFD for \$(\$ip.Count) failed logins" `
            -Direction Inbound `
            -Action Block `
            -RemoteAddress \$IPAddress `
            -Profile Any
    }
}
"@

# --- 2. Create the Script File on Disk ---
$ScriptPath = "C:\Program Files\RevolutionaryTechnology"
$ScriptFile = "$ScriptPath\Watch-Logons.ps1"

if (-not (Test-Path $ScriptPath)) {
    New-Item -Path $ScriptPath -ItemType Directory -Force
}
$ScriptContent | Out-File $ScriptFile -Encoding utf8 -Force
Write-Host "  [+] LFD Watchdog script created at $ScriptFile"

# --- 3. Create the Scheduled Task ---
$Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -File `"$ScriptFile`""
$Trigger = New-ScheduledTaskTrigger -RepetitionInterval (New-TimeSpan -Minutes 5) -Once -At (Get-Date)
$Principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType Service -RunLevel Highest

Register-ScheduledTask -TaskName "RevolutionaryTech-LFD-Windows" `
    -Action $Action `
    -Trigger $Trigger `
    -Principal $Principal `
    -Description "Monitors RDP, SMB, and other logs for failed logins and blocks attacker IPs. (Revolutionary Technology)" `
    -Force

Write-Host "  [+] Scheduled Task 'RevolutionaryTech-LFD-Windows' created."
Write-Host ""
Write-Host "INSTALLATION COMPLETE. The LFD for Windows is now active and will run every 5 minutes." -ForegroundColor Green