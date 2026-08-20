<#
.SYNOPSIS
    Install Flamenco Manager and Worker as persistent Windows Services.
.DESCRIPTION
    Uses WinSW to wrap Flamenco processes as auto-start services with restart-on-failure.
    Idempotent — reinstalls cleanly if services already exist.
    Ensures only one worker instance runs on this machine.

    Requires elevation (Run as Administrator).
    Requires WinSW: winget install CloudBees.WindowsServiceWrapper
.EXAMPLE
    gsudo .\Install-FarmServices.ps1
    gsudo .\Install-FarmServices.ps1 -ConfigPath .\farm-config.json
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

# --- Auto-detect Flamenco directory ---
$FlamencoDir = $null
$searchPaths = @(
    (Join-Path $Cfg.server.storage_root 'Flamenco')
    $PSScriptRoot
    (Join-Path $PSScriptRoot 'Flamenco')
)
foreach ($fp in $searchPaths) {
    if (Test-Path (Join-Path $fp 'flamenco-manager.exe')) {
        $FlamencoDir = $fp
        break
    }
}
if (-not $FlamencoDir) {
    Write-Host "  [FATAL] Cannot find flamenco-manager.exe in any expected location" -ForegroundColor Red
    Write-Host "         Searched: $($searchPaths -join ', ')" -ForegroundColor Red
    exit 1
}

$LogDir = Join-Path $Cfg.server.storage_root 'logs'
if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }

Write-Host ""
Write-Host "  Install-FarmServices" -ForegroundColor Cyan
Write-Host "  Flamenco: $FlamencoDir" -ForegroundColor DarkGray
Write-Host "  Logs: $LogDir" -ForegroundColor DarkGray
Write-Host ""

# --- Find WinSW ---
$winsw = (Get-Command winsw -ErrorAction SilentlyContinue).Source
if (-not $winsw) {
    $winsw = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\winsw.exe'
}
if (-not (Test-Path $winsw)) {
    Write-Host "  [FATAL] WinSW not found. Install:" -ForegroundColor Red
    Write-Host "         winget install CloudBees.WindowsServiceWrapper" -ForegroundColor Yellow
    exit 1
}
Write-Host "  WinSW: $winsw" -ForegroundColor DarkGray

# --- Stop any running Flamenco processes ---
Stop-Process -Name 'flamenco-manager' -Force -ErrorAction SilentlyContinue
Stop-Process -Name 'flamenco-worker' -Force -ErrorAction SilentlyContinue
Start-Sleep 1

# --- Remove old scheduled tasks (from prior Set-FarmServer runs) ---
Unregister-ScheduledTask -TaskName 'FlamencoManager' -Confirm:$false -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName 'FlamencoWorker' -Confirm:$false -ErrorAction SilentlyContinue

# --- Generate WinSW XML configs ---
$managerXml = @"
<service>
  <id>FlamencoManager</id>
  <name>Flamenco Manager</name>
  <description>Flamenco render farm manager ($($Cfg.farm.name))</description>
  <executable>$FlamencoDir\flamenco-manager.exe</executable>
  <workingdirectory>$FlamencoDir</workingdirectory>
  <log mode="roll-by-size">
    <sizeThreshold>10240</sizeThreshold>
    <keepFiles>5</keepFiles>
  </log>
  <logpath>$LogDir</logpath>
  <onfailure action="restart" delay="5 sec"/>
  <onfailure action="restart" delay="10 sec"/>
  <onfailure action="restart" delay="30 sec"/>
  <resetfailure>1 hour</resetfailure>
  <startmode>Automatic</startmode>
  <delayedAutoStart>true</delayedAutoStart>
</service>
"@

$workerXml = @"
<service>
  <id>FlamencoWorker</id>
  <name>Flamenco Worker</name>
  <description>Flamenco render worker ($($Cfg.farm.name))</description>
  <executable>$FlamencoDir\flamenco-worker.exe</executable>
  <arguments>-manager http://localhost:$($Cfg.flamenco.manager_port)</arguments>
  <workingdirectory>$FlamencoDir</workingdirectory>
  <log mode="roll-by-size">
    <sizeThreshold>10240</sizeThreshold>
    <keepFiles>5</keepFiles>
  </log>
  <logpath>$LogDir</logpath>
  <depend>FlamencoManager</depend>
  <onfailure action="restart" delay="5 sec"/>
  <onfailure action="restart" delay="10 sec"/>
  <onfailure action="restart" delay="30 sec"/>
  <resetfailure>1 hour</resetfailure>
  <startmode>Automatic</startmode>
  <delayedAutoStart>true</delayedAutoStart>
</service>
"@

$managerXmlPath = Join-Path $FlamencoDir 'flamenco-manager-svc.xml'
$workerXmlPath = Join-Path $FlamencoDir 'flamenco-worker-svc.xml'
$managerSvcExe = Join-Path $FlamencoDir 'flamenco-manager-svc.exe'
$workerSvcExe = Join-Path $FlamencoDir 'flamenco-worker-svc.exe'

Set-Content -Path $managerXmlPath -Value $managerXml -Encoding UTF8
Set-Content -Path $workerXmlPath -Value $workerXml -Encoding UTF8
Write-Host "  [OK] Generated service XML configs" -ForegroundColor Green

# --- Copy WinSW exe as service wrappers ---
Copy-Item $winsw $managerSvcExe -Force
Copy-Item $winsw $workerSvcExe -Force

# --- Uninstall existing services (idempotent reinstall) ---
$existingSvcs = Get-Service -Name 'FlamencoManager', 'FlamencoWorker' -ErrorAction SilentlyContinue
foreach ($svc in $existingSvcs) {
    if ($svc.Status -eq 'Running') { Stop-Service $svc.Name -Force }
    Start-Sleep 1
}
if (Get-Service -Name 'FlamencoWorker' -ErrorAction SilentlyContinue) {
    & $workerSvcExe uninstall 2>&1 | Out-Null
    Start-Sleep 1
}
if (Get-Service -Name 'FlamencoManager' -ErrorAction SilentlyContinue) {
    & $managerSvcExe uninstall 2>&1 | Out-Null
    Start-Sleep 1
}

# --- Install fresh ---
Set-Location $FlamencoDir

$result1 = & $managerSvcExe install 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "  [OK] FlamencoManager service installed" -ForegroundColor Green
} else {
    Write-Host "  [ERR] Manager install failed: $result1" -ForegroundColor Red
    exit 1
}

$result2 = & $workerSvcExe install 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "  [OK] FlamencoWorker service installed (depends on Manager)" -ForegroundColor Green
} else {
    Write-Host "  [ERR] Worker install failed: $result2" -ForegroundColor Red
    exit 1
}

# --- Start services ---
Write-Host ""
try {
    Start-Service FlamencoManager
    Write-Host "  [OK] FlamencoManager started" -ForegroundColor Green
} catch {
    Write-Host "  [ERR] Failed to start Manager: $($_.Exception.Message)" -ForegroundColor Red
}

Start-Sleep 3

try {
    Start-Service FlamencoWorker
    Write-Host "  [OK] FlamencoWorker started" -ForegroundColor Green
} catch {
    Write-Host "  [ERR] Failed to start Worker: $($_.Exception.Message)" -ForegroundColor Red
}

Start-Sleep 2

# --- Verify ---
Write-Host ""
Write-Host "  --- Service Status ---" -ForegroundColor Cyan
Get-Service Flamenco* | Format-Table Name, Status, StartType -AutoSize

$listening = netstat -ano | Select-String ':8080.*LISTENING'
if ($listening) {
    Write-Host "  [OK] Manager listening on port $($Cfg.flamenco.manager_port)" -ForegroundColor Green
} else {
    Write-Host "  [WARN] Port $($Cfg.flamenco.manager_port) not listening - check $LogDir" -ForegroundColor Yellow
}

# Check worker count via API
try {
    $workers = curl.exe -s "http://localhost:$($Cfg.flamenco.manager_port)/api/v3/worker-mgt/workers" | ConvertFrom-Json
    $awake = ($workers.workers | Where-Object { $_.status -eq 'awake' }).Count
    Write-Host "  [OK] Workers registered: $($workers.workers.Count) (awake: $awake)" -ForegroundColor Green
    if ($workers.workers.Count -gt 1) {
        Write-Host "  [WARN] Multiple workers registered - clean stale ones from web UI" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  [WARN] Could not query worker API" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  Services will auto-start on boot and restart on failure." -ForegroundColor White
Write-Host "  Manage: Get-Service Flamenco* | Stop-Service / Start-Service" -ForegroundColor DarkGray
Write-Host ""
