<#
.SYNOPSIS
    Configure this machine as a Flamenco render farm server (Manager + Worker).
.DESCRIPTION
    Reads farm-config.json for all settings. Idempotent — safe to run repeatedly.
    Outputs a connection-info block that must be shared with the client machine.

    Exit codes: 0 = success, 1 = fatal prerequisite missing, 2 = partial (warnings)
.EXAMPLE
    gsudo .\Set-FarmServer.ps1
    gsudo .\Set-FarmServer.ps1 -WhatIf
    gsudo .\Set-FarmServer.ps1 -ConfigPath .\custom-config.json
#>
#Requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'farm-config.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# --- Load config ---
if (-not (Test-Path $ConfigPath)) {
    Write-Host "  [FATAL] Config not found: $ConfigPath" -ForegroundColor Red
    exit 1
}
$Cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json

# --- Auto-detect machine-specific values ---
$ServerHostname = $env:COMPUTERNAME
$ServerIP = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.PrefixOrigin -eq 'Dhcp' -or $_.PrefixOrigin -eq 'Manual' } |
    Where-Object { $_.IPAddress -notlike '169.*' -and $_.IPAddress -notlike '127.*' } |
    Select-Object -First 1).IPAddress

# Auto-detect Blender
$BlenderExe = $null
$blenderSearch = Get-Item "${env:ProgramFiles}\Blender Foundation\Blender $($Cfg.blender.required_version)*\blender.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($blenderSearch) {
    $BlenderExe = $blenderSearch.FullName
} else {
    $blenderCmd = Get-Command blender -ErrorAction SilentlyContinue
    if ($blenderCmd) { $BlenderExe = $blenderCmd.Source }
}

# Auto-detect Flamenco install dir (check storage_root first, then alongside this script)
$FlamencoDir = $null
$flamencoSearchPaths = @(
    (Join-Path $Cfg.server.storage_root 'Flamenco')
    $PSScriptRoot
    (Join-Path $PSScriptRoot 'Flamenco')
)
foreach ($fp in $flamencoSearchPaths) {
    if (Test-Path (Join-Path $fp 'flamenco-manager.exe')) {
        $FlamencoDir = $fp
        break
    }
}

# --- Logging setup ---
$LogDir = Join-Path $Cfg.server.storage_root 'logs'
if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
$LogPath = Join-Path $LogDir "Set-FarmServer_$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

$script:changed = 0
$script:skipped = 0
$script:warnings = 0
$script:errors = 0

function Log {
    param([string]$Msg, [ValidateSet('INFO','OK','SKIP','WARN','ERR','FATAL')]$Lvl = 'INFO')
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts] [$Lvl] $Msg"
    Add-Content -Path $LogPath -Value $line -ErrorAction SilentlyContinue
    $color = switch ($Lvl) {
        'OK'    { 'Green' }
        'SKIP'  { 'DarkGray' }
        'WARN'  { 'Yellow'; $script:warnings++ }
        'ERR'   { 'Red'; $script:errors++ }
        'FATAL' { 'Red'; $script:errors++ }
        default { 'Gray' }
    }
    $prefix = switch ($Lvl) { 'INFO' { '     ' } default { "[$Lvl] " } }
    Write-Host "  $prefix$Msg" -ForegroundColor $color
}

# --- Header ---
Write-Host ""
Write-Host "  Set-FarmServer — $($Cfg.farm.name)" -ForegroundColor Cyan
Write-Host "  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor DarkGray
Write-Host "  Log: $LogPath" -ForegroundColor DarkGray
if ($WhatIfPreference) { Write-Host "  MODE: WhatIf (no changes will be made)" -ForegroundColor Yellow }
Write-Host ""
Log "Run started on $env:COMPUTERNAME$(if ($WhatIfPreference) {' [WhatIf]'})"

# ===========================================================================
# PREREQUISITES
# ===========================================================================
Write-Host "  Prerequisites" -ForegroundColor White

# Blender
if ($BlenderExe -and (Test-Path $BlenderExe)) {
    $blenderVer = & $BlenderExe --version 2>&1 | Select-Object -First 1
    Log "Blender: $blenderVer at $BlenderExe" 'OK'
} else {
    Log "Blender $($Cfg.blender.required_version).x not found. Install it or ensure it's in Program Files." 'FATAL'
    exit 1
}

# NVIDIA GPU
$gpuName = 'Unknown'
$gpuMem = 'N/A'
$nvidiaSmi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
if ($nvidiaSmi) {
    $gpuName = (nvidia-smi --query-gpu=name --format=csv,noheader 2>&1).Trim()
    $gpuMem = (nvidia-smi --query-gpu=memory.total --format=csv,noheader 2>&1).Trim()
    Log "GPU: $gpuName ($gpuMem)" 'OK'
} else {
    Log "nvidia-smi not found — GPU acceleration unavailable" 'WARN'
}

# Flamenco binaries
if (-not $FlamencoDir) {
    Log "Flamenco not found. Place flamenco-manager.exe in $($Cfg.server.storage_root)\Flamenco\ or download from https://flamenco.blender.org/downloads/" 'FATAL'
    exit 1
}
$managerExe = Join-Path $FlamencoDir 'flamenco-manager.exe'
$workerExe = Join-Path $FlamencoDir 'flamenco-worker.exe'
if (-not (Test-Path $workerExe)) {
    Log "Flamenco worker not found at $workerExe" 'FATAL'
    exit 1
}
Log "Flamenco $($Cfg.flamenco.version) at $FlamencoDir" 'OK'

# ===========================================================================
# STORAGE
# ===========================================================================
Write-Host ""
Write-Host "  Storage" -ForegroundColor White

$storageDirs = @(
    $Cfg.server.storage_root
    (Join-Path $Cfg.server.storage_root $Cfg.server.jobs_subdir)
    (Join-Path $Cfg.server.storage_root $Cfg.server.output_subdir)
    $LogDir
)
foreach ($d in $storageDirs) {
    if (Test-Path $d) {
        Log "$d exists" 'SKIP'; $script:skipped++
    } elseif ($PSCmdlet.ShouldProcess($d, 'Create directory')) {
        New-Item -Path $d -ItemType Directory -Force | Out-Null
        Log "Created $d" 'OK'; $script:changed++
    }
}

# SMB share — ChangeAccess for workers, FullAccess only for Administrators
$existing = Get-SmbShare -Name $Cfg.server.share_name -ErrorAction SilentlyContinue
if ($existing) {
    Log "Share '$($Cfg.server.share_name)' exists at $($existing.Path)" 'SKIP'; $script:skipped++
} elseif ($PSCmdlet.ShouldProcess($Cfg.server.share_name, 'Create SMB share')) {
    try {
        New-SmbShare -Name $Cfg.server.share_name -Path $Cfg.server.storage_root `
            -ChangeAccess 'Authenticated Users' `
            -FullAccess 'Administrators' `
            -Description "$($Cfg.farm.name) shared storage" | Out-Null
        Log "Created SMB share '$($Cfg.server.share_name)' (Change: Authenticated Users, Full: Administrators)" 'OK'
        $script:changed++
    } catch {
        Log "Failed to create share: $($_.Exception.Message)" 'ERR'
    }
}

# SMB encryption on share
$shareObj = Get-SmbShare -Name $Cfg.server.share_name -ErrorAction SilentlyContinue
if ($shareObj) {
    if ($shareObj.EncryptData) {
        Log "SMB encryption already enabled on share" 'SKIP'; $script:skipped++
    } elseif ($PSCmdlet.ShouldProcess($Cfg.server.share_name, 'Enable SMB encryption')) {
        try {
            Set-SmbShare -Name $Cfg.server.share_name -EncryptData $true -Force
            Log "Enabled SMB encryption on '$($Cfg.server.share_name)'" 'OK'; $script:changed++
        } catch {
            Log "Failed to enable encryption (may require SMB 3.0+ clients): $($_.Exception.Message)" 'WARN'
        }
    }
}

# NTFS permissions — Modify for Authenticated Users (not FullControl)
$acl = Get-Acl $Cfg.server.storage_root
$hasModify = $acl.Access | Where-Object {
    $_.IdentityReference -like '*Authenticated Users*' -and $_.FileSystemRights -match 'Modify'
}
if ($hasModify) {
    Log "NTFS Modify for Authenticated Users set" 'SKIP'; $script:skipped++
} elseif ($PSCmdlet.ShouldProcess($Cfg.server.storage_root, 'Set NTFS Modify permissions')) {
    try {
        # Remove any existing FullControl rule for Authenticated Users (from prior runs)
        $fullRule = $acl.Access | Where-Object {
            $_.IdentityReference -like '*Authenticated Users*' -and $_.FileSystemRights -match 'FullControl'
        }
        if ($fullRule) {
            $acl.RemoveAccessRule($fullRule) | Out-Null
        }
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            'Authenticated Users', 'Modify', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
        $acl.AddAccessRule($rule)
        Set-Acl -Path $Cfg.server.storage_root -AclObject $acl
        Log "Granted NTFS Modify (not FullControl) to Authenticated Users" 'OK'; $script:changed++
    } catch {
        Log "Failed to set NTFS permissions: $($_.Exception.Message)" 'ERR'
    }
}

# ===========================================================================
# FIREWALL
# ===========================================================================
Write-Host ""
Write-Host "  Firewall" -ForegroundColor White

$rules = @(
    @{ Name = 'Flamenco Manager'; Port = $Cfg.firewall.flamenco_port; Desc = 'Flamenco render farm manager' }
    @{ Name = 'C4D Team Render'; Port = $Cfg.firewall.team_render_ports; Desc = 'Cinema 4D Team Render' }
    @{ Name = 'Syncthing'; Port = $Cfg.firewall.syncthing_port; Desc = 'Syncthing file synchronization' }
)
foreach ($r in $rules) {
    $exists = Get-NetFirewallRule -DisplayName $r.Name -ErrorAction SilentlyContinue
    if ($exists) {
        Log "Rule '$($r.Name)' exists" 'SKIP'; $script:skipped++
    } elseif ($PSCmdlet.ShouldProcess($r.Name, 'Create firewall rule')) {
        try {
            New-NetFirewallRule -DisplayName $r.Name -Direction Inbound `
                -LocalPort $r.Port -Protocol TCP -Action Allow `
                -Profile Private -Description $r.Desc | Out-Null
            Log "Created rule '$($r.Name)' (TCP $($r.Port), Private)" 'OK'; $script:changed++
        } catch {
            Log "Failed to create rule '$($r.Name)': $($_.Exception.Message)" 'ERR'
        }
    }
}

# ===========================================================================
# WINDOWS DEFENDER EXCLUSIONS (render performance)
# ===========================================================================
Write-Host ""
Write-Host "  Defender Exclusions" -ForegroundColor White

$exclusions = @{
    Process = @($BlenderExe, $managerExe, $workerExe)
    Path    = @($Cfg.server.storage_root)
}

$currentProcessExcl = (Get-MpPreference -ErrorAction SilentlyContinue).ExclusionProcess
$currentPathExcl = (Get-MpPreference -ErrorAction SilentlyContinue).ExclusionPath

foreach ($proc in $exclusions.Process) {
    if ($currentProcessExcl -and ($currentProcessExcl -contains $proc)) {
        Log "Defender process exclusion exists: $(Split-Path $proc -Leaf)" 'SKIP'; $script:skipped++
    } elseif ($PSCmdlet.ShouldProcess($proc, 'Add Defender process exclusion')) {
        try {
            Add-MpPreference -ExclusionProcess $proc
            Log "Added Defender process exclusion: $(Split-Path $proc -Leaf)" 'OK'; $script:changed++
        } catch {
            Log "Failed to add process exclusion: $($_.Exception.Message)" 'WARN'
        }
    }
}

foreach ($p in $exclusions.Path) {
    if ($currentPathExcl -and ($currentPathExcl -contains $p)) {
        Log "Defender path exclusion exists: $p" 'SKIP'; $script:skipped++
    } elseif ($PSCmdlet.ShouldProcess($p, 'Add Defender path exclusion')) {
        try {
            Add-MpPreference -ExclusionPath $p
            Log "Added Defender path exclusion: $p" 'OK'; $script:changed++
        } catch {
            Log "Failed to add path exclusion: $($_.Exception.Message)" 'WARN'
        }
    }
}

# ===========================================================================
# DEVELOPER MODE (required for Shaman symlinks without admin)
# ===========================================================================
Write-Host ""
Write-Host "  Developer Mode (Shaman symlinks)" -ForegroundColor White

$devModeKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'
$devModeEnabled = (Get-ItemProperty $devModeKey -Name 'AllowDevelopmentWithoutDevLicense' -ErrorAction SilentlyContinue).AllowDevelopmentWithoutDevLicense
if ($devModeEnabled -eq 1) {
    Log "Developer Mode already enabled (symlinks allowed)" 'SKIP'; $script:skipped++
} elseif ($PSCmdlet.ShouldProcess('Developer Mode', 'Enable for Shaman symlinks')) {
    try {
        if (-not (Test-Path $devModeKey)) { New-Item -Path $devModeKey -Force | Out-Null }
        Set-ItemProperty -Path $devModeKey -Name 'AllowDevelopmentWithoutDevLicense' -Value 1 -Type DWord
        Log "Enabled Developer Mode (Shaman symlinks now work without admin)" 'OK'; $script:changed++
    } catch {
        Log "Failed to enable Developer Mode: $($_.Exception.Message). Shaman may not work." 'WARN'
    }
}

# Enable symlink evaluation for remote-to-remote (workers accessing via SMB)
$symlinkEval = (fsutil behavior query SymlinkEvaluation 2>&1) -join ' '
if ($symlinkEval -match 'R2R.*enabled') {
    Log "Remote-to-Remote symlink evaluation already enabled" 'SKIP'; $script:skipped++
} elseif ($PSCmdlet.ShouldProcess('SymlinkEvaluation R2R', 'Enable')) {
    try {
        fsutil behavior set SymlinkEvaluation R2R:1 | Out-Null
        Log "Enabled R2R symlink evaluation (remote workers can follow Shaman symlinks)" 'OK'; $script:changed++
    } catch {
        Log "Failed to set symlink evaluation: $($_.Exception.Message)" 'WARN'
    }
}

# ===========================================================================
# FLAMENCO MANAGER CONFIG
# ===========================================================================
Write-Host ""
Write-Host "  Flamenco Manager Config" -ForegroundColor White

$managerYaml = Join-Path $FlamencoDir 'flamenco-manager.yaml'
$managerYamlBackup = Join-Path $FlamencoDir 'flamenco-manager.yaml.bak'
$jobsPath = Join-Path $Cfg.server.storage_root $Cfg.server.jobs_subdir
$blenderEscaped = $BlenderExe -replace '\\', '\\'
$jobsEscaped = $jobsPath -replace '\\', '\\'

$desiredYaml = @"
# Flamenco Manager — generated by Set-FarmServer.ps1
# DO NOT EDIT — re-run Set-FarmServer.ps1 to update. Backup: flamenco-manager.yaml.bak
version: 3
manager_name: $env:COMPUTERNAME
listen: :$($Cfg.flamenco.manager_port)
local_manager_storage_path: $jobsPath
database_path: $($FlamencoDir)\flamenco-manager.sqlite
shared_storage_path: $jobsPath
shaman:
  enabled: $("$($Cfg.shaman.enabled)".ToLower())
  garbageCollect:
    period: $($Cfg.shaman.gc_period)
    maxAge: $($Cfg.shaman.gc_max_age)

variables:
  blender:
    values:
      - platform: windows
        value: "$blenderEscaped"
      - platform: linux
        value: /usr/local/bin/blender
  job_storage:
    values:
      - platform: windows
        value: "$jobsEscaped"
      - platform: linux
        value: /mnt/renderfarm/jobs
"@

if (Test-Path $managerYaml) {
    $current = Get-Content $managerYaml -Raw -ErrorAction SilentlyContinue
    if ($current.Trim() -eq $desiredYaml.Trim()) {
        Log "Manager YAML unchanged" 'SKIP'; $script:skipped++
    } elseif ($PSCmdlet.ShouldProcess($managerYaml, 'Update manager config')) {
        # Backup before overwriting (protects against wizard overwrites)
        Copy-Item -Path $managerYaml -Destination $managerYamlBackup -Force
        Set-Content -Path $managerYaml -Value $desiredYaml -Encoding UTF8
        Log "Updated manager YAML (backup at .yaml.bak)" 'OK'; $script:changed++
    }
} elseif ($PSCmdlet.ShouldProcess($managerYaml, 'Create manager config')) {
    Set-Content -Path $managerYaml -Value $desiredYaml -Encoding UTF8
    Log "Created manager YAML" 'OK'; $script:changed++
}

# ===========================================================================
# FLAMENCO WORKER CONFIG (explicit manager_url, named worker)
# ===========================================================================
Write-Host ""
Write-Host "  Flamenco Worker Config" -ForegroundColor White

$workerYaml = Join-Path $FlamencoDir 'flamenco-worker.yaml'
$workerName = "$env:COMPUTERNAME-$($gpuName -replace '\s+','-' -replace '[^a-zA-Z0-9\-]','')"

$desiredWorkerYaml = @"
# Flamenco Worker — generated by Set-FarmServer.ps1
manager_url: http://localhost:$($Cfg.flamenco.manager_port)/
task_types: [blender, ffmpeg, file-management, misc]
restart_exit_code: 47
"@

if (Test-Path $workerYaml) {
    $currentWorker = Get-Content $workerYaml -Raw -ErrorAction SilentlyContinue
    if ($currentWorker.Trim() -eq $desiredWorkerYaml.Trim()) {
        Log "Worker YAML unchanged" 'SKIP'; $script:skipped++
    } elseif ($PSCmdlet.ShouldProcess($workerYaml, 'Update worker config')) {
        Set-Content -Path $workerYaml -Value $desiredWorkerYaml -Encoding UTF8
        Log "Updated worker YAML" 'OK'; $script:changed++
    }
} elseif ($PSCmdlet.ShouldProcess($workerYaml, 'Create worker config')) {
    Set-Content -Path $workerYaml -Value $desiredWorkerYaml -Encoding UTF8
    Log "Created worker YAML" 'OK'; $script:changed++
}

# Set worker name via environment variable
$currentWorkerName = [System.Environment]::GetEnvironmentVariable('FLAMENCO_WORKER_NAME', 'Machine')
if ($currentWorkerName -eq $workerName) {
    Log "Worker name already set: $workerName" 'SKIP'; $script:skipped++
} elseif ($PSCmdlet.ShouldProcess('FLAMENCO_WORKER_NAME', "Set to $workerName")) {
    [System.Environment]::SetEnvironmentVariable('FLAMENCO_WORKER_NAME', $workerName, 'Machine')
    Log "Set FLAMENCO_WORKER_NAME=$workerName" 'OK'; $script:changed++
}

# ===========================================================================
# SCHEDULED TASKS (auto-start on boot)
# ===========================================================================
Write-Host ""
Write-Host "  Startup Tasks" -ForegroundColor White

$tasks = @(
    @{ Name = 'FlamencoManager'; Exe = $managerExe; Args = $null; Desc = "Flamenco Manager ($($Cfg.farm.name))" }
    @{ Name = 'FlamencoWorker'; Exe = $workerExe; Args = $null; Desc = "Flamenco Worker ($workerName)" }
)
foreach ($t in $tasks) {
    $existingTask = Get-ScheduledTask -TaskName $t.Name -ErrorAction SilentlyContinue
    if ($existingTask) {
        Log "Task '$($t.Name)' exists" 'SKIP'; $script:skipped++
    } elseif ($PSCmdlet.ShouldProcess($t.Name, 'Create scheduled task')) {
        try {
            $actionParams = @{ Execute = $t.Exe; WorkingDirectory = $FlamencoDir }
            if ($t.Args) { $actionParams.Argument = $t.Args }
            $action = New-ScheduledTaskAction @actionParams
            $trigger = New-ScheduledTaskTrigger -AtStartup
            $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero)
            $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -RunLevel Highest -LogonType S4U
            Register-ScheduledTask -TaskName $t.Name -Action $action -Trigger $trigger `
                -Settings $settings -Principal $principal -Description $t.Desc | Out-Null
            Log "Created task '$($t.Name)'" 'OK'; $script:changed++
        } catch {
            Log "Failed to create task '$($t.Name)': $($_.Exception.Message)" 'ERR'
        }
    }
}

# ===========================================================================
# START SERVICES
# ===========================================================================
Write-Host ""
Write-Host "  Start Services" -ForegroundColor White

if (-not $WhatIfPreference) {
    $managerProc = Get-Process -Name 'flamenco-manager' -ErrorAction SilentlyContinue
    if ($managerProc) {
        Log "Manager already running (PID $($managerProc.Id))" 'SKIP'; $script:skipped++
    } else {
        try {
            Start-ScheduledTask -TaskName 'FlamencoManager'
            Start-Sleep -Seconds 3
            $managerProc = Get-Process -Name 'flamenco-manager' -ErrorAction SilentlyContinue
            if ($managerProc) {
                Log "Manager started (PID $($managerProc.Id))" 'OK'; $script:changed++
            } else {
                Log "Manager task fired but process not found — complete setup wizard at http://localhost:$($Cfg.flamenco.manager_port)" 'WARN'
            }
        } catch {
            Log "Failed to start manager: $($_.Exception.Message)" 'WARN'
        }
    }

    $workerProc = Get-Process -Name 'flamenco-worker' -ErrorAction SilentlyContinue
    if ($workerProc) {
        Log "Worker already running (PID $($workerProc.Id))" 'SKIP'; $script:skipped++
    } else {
        Start-Sleep -Seconds 2
        try {
            Start-ScheduledTask -TaskName 'FlamencoWorker'
            Start-Sleep -Seconds 3
            $workerProc = Get-Process -Name 'flamenco-worker' -ErrorAction SilentlyContinue
            if ($workerProc) {
                Log "Worker started (PID $($workerProc.Id))" 'OK'; $script:changed++
            } else {
                Log "Worker did not start — manager may need setup wizard first" 'WARN'
            }
        } catch {
            Log "Failed to start worker: $($_.Exception.Message)" 'WARN'
        }
    }
} else {
    Log "Skipping service start (WhatIf mode)" 'SKIP'; $script:skipped += 2
}

# ===========================================================================
# OUTPUT: Connection info for client
# ===========================================================================
Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║  FARM SERVER READY — share this with the client machine:    ║" -ForegroundColor Cyan
Write-Host "  ╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

$ip = $ServerIP

$connectionInfo = @"
--- FARM CONNECTION INFO (give to client) ---
Server:          $env:COMPUTERNAME
IP:              $ip
Flamenco URL:    http://${ip}:$($Cfg.flamenco.manager_port)
Share (UNC):     \\$env:COMPUTERNAME\$($Cfg.server.share_name)
Share (IP):      \\${ip}\$($Cfg.server.share_name)
Jobs path:       \\$env:COMPUTERNAME\$($Cfg.server.share_name)\$($Cfg.server.jobs_subdir)
Output path:     \\$env:COMPUTERNAME\$($Cfg.server.share_name)\$($Cfg.server.output_subdir)
Blender ver:     $($Cfg.blender.required_version).x LTS
GPU:             $gpuName ($gpuMem)
Worker name:     $workerName
SMB encrypted:   Yes
Config file:     \\${ip}\$($Cfg.server.share_name)\farm-config.json
--- END ---
"@

Write-Host $connectionInfo -ForegroundColor White

# Save connection info to share for easy retrieval by client
if (-not $WhatIfPreference) {
    $infoFile = Join-Path $Cfg.server.storage_root 'connection-info.txt'
    Set-Content -Path $infoFile -Value $connectionInfo -Encoding UTF8
    # Also copy farm-config.json to the share root for client access
    $shareConfigDest = Join-Path $Cfg.server.storage_root 'farm-config.json'
    if (-not (Test-Path $shareConfigDest)) {
        Copy-Item -Path $ConfigPath -Destination $shareConfigDest
        Log "Copied farm-config.json to share for client access" 'OK'
    }
    Log "Connection info saved to $infoFile"
}

# ===========================================================================
# SUMMARY
# ===========================================================================
Write-Host ""
$changedColor = if ($script:changed -gt 0) { 'Green' } else { 'DarkGray' }
Write-Host "  Changed: $($script:changed)  Skipped: $($script:skipped)  Warnings: $($script:warnings)  Errors: $($script:errors)" -ForegroundColor $changedColor
Write-Host ""

Log "Run complete: $($script:changed) changed, $($script:skipped) skipped, $($script:warnings) warnings, $($script:errors) errors"

if ($script:errors -gt 0) { exit 2 }
exit 0
