<#
.SYNOPSIS
    Configure this workstation as a Flamenco render farm client.
.DESCRIPTION
    Reads farm-config.json for server details. Connects to the farm server,
    maps the render share, verifies tool compatibility, and reports readiness.
    Does NOT require elevation (user-level operations only).

    Exit codes: 0 = success, 1 = fatal (can't reach server), 2 = partial (warnings)
.EXAMPLE
    .\Set-FarmClient.ps1
    .\Set-FarmClient.ps1 -ConfigPath \\FLAMINGDRAGON\RenderFarm\farm-config.json
    .\Set-FarmClient.ps1 -ServerIP 192.168.0.107
.NOTES
    Run this AFTER Set-FarmServer.ps1 has been run on the server.
    The server outputs connection info — this script validates against it.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'farm-config.json'),
    [string]$ServerIP   # Override — use if config isn't available locally
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# --- Load config ---
if (-not (Test-Path $ConfigPath)) {
    # Try fetching from server if IP provided
    if ($ServerIP) {
        $remoteConfig = "\\$ServerIP\RenderFarm\farm-config.json"
        if (Test-Path $remoteConfig) {
            $ConfigPath = $remoteConfig
        } else {
            Write-Host "  [FATAL] Config not found locally or at $remoteConfig" -ForegroundColor Red
            exit 1
        }
    } else {
        Write-Host "  [FATAL] Config not found: $ConfigPath" -ForegroundColor Red
        Write-Host "         Use -ConfigPath or -ServerIP to locate farm-config.json" -ForegroundColor Red
        exit 1
    }
}
$Cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json

# --- Logging ---
$LogDir = Join-Path $PSScriptRoot '.scratch'
if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
$LogPath = Join-Path $LogDir "Set-FarmClient_$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

$script:changed = 0
$script:skipped = 0
$script:warnings = 0
$script:errors = 0

function Log {
    param([string]$Msg, [ValidateSet('INFO','OK','SKIP','WARN','ERR','FATAL')]$Lvl = 'INFO')
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $LogPath -Value "[$ts] [$Lvl] $Msg" -ErrorAction SilentlyContinue
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

# --- Resolve server address ---
if (-not $ServerIP) {
    # Try reading from a previously-mapped drive's connection-info.txt
    $driveLetter = $Cfg.client.drive_letter
    $infoFile = Join-Path $driveLetter 'connection-info.txt'
    if (Test-Path $infoFile) {
        $infoContent = Get-Content $infoFile -Raw
        if ($infoContent -match 'IP:\s+(\d+\.\d+\.\d+\.\d+)') {
            $ServerIP = $Matches[1]
        }
    }
    if (-not $ServerIP) {
        Write-Host "  [FATAL] Server IP not known. Provide -ServerIP parameter." -ForegroundColor Red
        Write-Host "         Example: .\Set-FarmClient.ps1 -ServerIP 192.168.0.107" -ForegroundColor Red
        exit 1
    }
}
$srvIP = $ServerIP
$srvHost = $srvIP
try {
    $resolved = Resolve-DnsName $srvIP -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($resolved.NameHost) { $srvHost = $resolved.NameHost }
} catch {}
$shareUNC = "\\$srvHost\$($Cfg.server.share_name)"
$shareByIP = "\\$srvIP\$($Cfg.server.share_name)"

# --- Header ---
Write-Host ""
Write-Host "  Set-FarmClient — $($Cfg.farm.name)" -ForegroundColor Cyan
Write-Host "  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor DarkGray
Write-Host "  Server: $srvHost ($srvIP)" -ForegroundColor DarkGray
Write-Host "  Log: $LogPath" -ForegroundColor DarkGray
Write-Host ""
Log "Run started on $env:COMPUTERNAME, targeting $srvHost ($srvIP)"

# ===========================================================================
# 1. NETWORK CONNECTIVITY
# ===========================================================================
Write-Host "  Network" -ForegroundColor White

# Ping
$reachable = Test-Connection -ComputerName $srvIP -Count 1 -Quiet
if ($reachable) {
    Log "Server reachable at $srvIP" 'OK'
} else {
    Log "Cannot reach $srvIP — is the server on this network?" 'FATAL'
    exit 1
}

# SMB (port 445)
$smbTest = Test-NetConnection -ComputerName $srvIP -Port 445 -WarningAction SilentlyContinue
if ($smbTest.TcpTestSucceeded) {
    Log "SMB port 445 open" 'OK'
} else {
    Log "SMB port 445 closed on $srvIP — file sharing not accessible" 'FATAL'
    exit 1
}

# Flamenco (port from config)
$flmPort = $Cfg.firewall.flamenco_port
$flmTest = Test-NetConnection -ComputerName $srvIP -Port $flmPort -WarningAction SilentlyContinue
if ($flmTest.TcpTestSucceeded) {
    Log "Flamenco Manager port $flmPort open" 'OK'
} else {
    Log "Flamenco port $flmPort not responding — manager may not be running. Start it on the server first." 'WARN'
}

# ===========================================================================
# 2. MAP RENDER SHARE
# ===========================================================================
Write-Host ""
Write-Host "  Share" -ForegroundColor White

$driveLetter = $Cfg.client.drive_letter
$driveLabel = $driveLetter.TrimEnd(':')

# Check if already mapped
$existingMap = net use 2>&1 | Select-String $driveLetter
if ($existingMap) {
    Log "Drive $driveLetter already mapped" 'SKIP'; $script:skipped++
} else {
    # Try hostname first, fall back to IP
    $mapped = $false
    try {
        $result = net use $driveLetter $shareUNC /persistent:yes 2>&1
        if ($LASTEXITCODE -eq 0) {
            Log "Mapped $driveLetter → $shareUNC" 'OK'; $script:changed++
            $mapped = $true
        }
    } catch {}

    if (-not $mapped) {
        try {
            $result = net use $driveLetter $shareByIP /persistent:yes 2>&1
            if ($LASTEXITCODE -eq 0) {
                Log "Mapped $driveLetter → $shareByIP (hostname failed, used IP)" 'OK'; $script:changed++
                $mapped = $true
            }
        } catch {}
    }

    if (-not $mapped) {
        Log "Failed to map share. Error: $result" 'ERR'
    }
}

# Verify subdirectories accessible
$jobsPath = Join-Path $driveLetter $Cfg.server.jobs_subdir
$outputPath = Join-Path $driveLetter $Cfg.server.output_subdir
if (Test-Path $jobsPath) {
    Log "Jobs directory accessible: $jobsPath" 'OK'
} else {
    Log "Jobs directory not found at $jobsPath — share may not be mapped correctly" 'WARN'
}
if (Test-Path $outputPath) {
    Log "Output directory accessible: $outputPath" 'OK'
} else {
    Log "Output directory not found at $outputPath" 'WARN'
}

# ===========================================================================
# 3. BLENDER VERSION CHECK
# ===========================================================================
Write-Host ""
Write-Host "  Blender" -ForegroundColor White

$requiredVer = $Cfg.blender.required_version
$blenderExe = $null

# Search common install paths
$searchPaths = @(
    "${env:ProgramFiles}\Blender Foundation\Blender $requiredVer\blender.exe"
    "${env:ProgramFiles}\Blender Foundation\Blender*\blender.exe"
)
foreach ($p in $searchPaths) {
    $found = Get-Item $p -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { $blenderExe = $found.FullName; break }
}
# Also check PATH
if (-not $blenderExe) {
    $cmd = Get-Command blender -ErrorAction SilentlyContinue
    if ($cmd) { $blenderExe = $cmd.Source }
}

if ($blenderExe) {
    $verLine = & $blenderExe --version 2>&1 | Select-Object -First 1
    if ($verLine -match "Blender $requiredVer") {
        Log "Blender $verLine (matches server requirement)" 'OK'
    } else {
        Log "VERSION MISMATCH: local=$verLine, server requires $requiredVer.x — Flamenco jobs will fail!" 'ERR'
    }
} else {
    Log "Blender not found — install Blender $requiredVer.x LTS (must match server)" 'ERR'
}

# ===========================================================================
# 4. FLAMENCO BLENDER ADD-ON
# ===========================================================================
Write-Host ""
Write-Host "  Flamenco Add-on" -ForegroundColor White

$addonPaths = @(
    "$env:APPDATA\Blender Foundation\Blender\$requiredVer\scripts\addons\flamenco"
    "$env:APPDATA\Blender Foundation\Blender\$requiredVer\scripts\addons\flamenco-*"
    "$env:APPDATA\Blender Foundation\Blender\$requiredVer\extensions\user_default\flamenco"
    "$env:APPDATA\Blender Foundation\Blender\$requiredVer\extensions\user_default\flamenco-*"
    "$env:APPDATA\Blender Foundation\Blender\$requiredVer\extensions\flamenco"
    "$env:APPDATA\Blender Foundation\Blender\$requiredVer\extensions\flamenco-*"
)
$addonFound = $false
foreach ($p in $addonPaths) {
    $match = Get-Item $p -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($match) {
        Log "Flamenco add-on found: $($match.FullName)" 'OK'
        $addonFound = $true
        break
    }
}
if (-not $addonFound) {
    $flmUrl = "http://${srvIP}:$flmPort"
    Log "Flamenco add-on NOT found. Download from $flmUrl (web UI provides the zip)" 'WARN'
}

# ===========================================================================
# 5. CC5 / BLENDER TOOLS
# ===========================================================================
Write-Host ""
Write-Host "  CC5 Pipeline Tools" -ForegroundColor White

$ccToolsPaths = @(
    "$env:APPDATA\Blender Foundation\Blender\$requiredVer\scripts\addons\cc_blender_tools"
    "$env:APPDATA\Blender Foundation\Blender\$requiredVer\scripts\addons\cc_blender_tools-*"
    "$env:APPDATA\Blender Foundation\Blender\$requiredVer\extensions\user_default\cc_blender_tools"
    "$env:APPDATA\Blender Foundation\Blender\$requiredVer\extensions\user_default\cc_blender_tools-*"
)
$ccFound = $false
foreach ($p in $ccToolsPaths) {
    $match = Get-Item $p -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($match) {
        Log "cc_blender_tools found: $($match.FullName)" 'OK'
        $ccFound = $true
        break
    }
}
if (-not $ccFound) {
    Log "cc_blender_tools not found — needed for CC5 character pipeline (https://github.com/soupday/cc_blender_tools)" 'WARN'
}

# ===========================================================================
# 6. LOCAL STAGING
# ===========================================================================
Write-Host ""
Write-Host "  Local Directories" -ForegroundColor White

$stagingDir = Join-Path $env:USERPROFILE $Cfg.client.local_staging
if (Test-Path $stagingDir) {
    Log "Staging directory exists: $stagingDir" 'SKIP'; $script:skipped++
} else {
    New-Item -Path $stagingDir -ItemType Directory -Force | Out-Null
    Log "Created staging directory: $stagingDir" 'OK'; $script:changed++
}

# ===========================================================================
# OUTPUT: Status report
# ===========================================================================
Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║  CLIENT STATUS                                              ║" -ForegroundColor Cyan
Write-Host "  ╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

$flmUrl = "http://${srvIP}:$($Cfg.firewall.flamenco_port)"

$readiness = @"
--- CLIENT READINESS ---
Machine:         $env:COMPUTERNAME
Farm server:     $srvHost ($srvIP)
Flamenco URL:    $flmUrl
Render share:    $driveLetter → $shareUNC
Jobs submit to:  $driveLetter\$($Cfg.server.jobs_subdir)
Output from:     $driveLetter\$($Cfg.server.output_subdir)
Blender:         $(if ($blenderExe) { $verLine } else { 'NOT INSTALLED' })
Flamenco addon:  $(if ($addonFound) { 'Installed' } else { 'MISSING — install from ' + $flmUrl })
CC5 tools:       $(if ($ccFound) { 'Installed' } else { 'MISSING — optional for CC5 workflow' })
--- END ---
"@

Write-Host $readiness -ForegroundColor White

# ===========================================================================
# SUMMARY + NEXT STEPS
# ===========================================================================
Write-Host ""
$changedColor = if ($script:changed -gt 0) { 'Green' } else { 'DarkGray' }
Write-Host "  Changed: $($script:changed)  Skipped: $($script:skipped)  Warnings: $($script:warnings)  Errors: $($script:errors)" -ForegroundColor $changedColor

if ($script:warnings -gt 0 -or $script:errors -gt 0) {
    Write-Host ""
    Write-Host "  Action Required:" -ForegroundColor Yellow
    if (-not $blenderExe -or ($verLine -and $verLine -notmatch "Blender $requiredVer")) {
        Write-Host "    • Install Blender $requiredVer.x LTS (must match server)" -ForegroundColor Yellow
    }
    if (-not $addonFound) {
        Write-Host "    • Install Flamenco Blender add-on from $flmUrl" -ForegroundColor Yellow
    }
    if (-not $ccFound) {
        Write-Host "    • (Optional) Install cc_blender_tools for CC5 character pipeline" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "  Workflow:" -ForegroundColor Cyan
Write-Host "    1. Open Blender → set output to $driveLetter\$($Cfg.server.output_subdir)\" -ForegroundColor DarkGray
Write-Host "    2. Flamenco panel → Submit job" -ForegroundColor DarkGray
Write-Host "    3. Monitor at $flmUrl" -ForegroundColor DarkGray
Write-Host ""

Log "Run complete: $($script:changed) changed, $($script:skipped) skipped, $($script:warnings) warnings, $($script:errors) errors"

if ($script:errors -gt 0) { exit 2 }
exit 0
