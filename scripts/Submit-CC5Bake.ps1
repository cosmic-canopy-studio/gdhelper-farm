<#
.SYNOPSIS
    Submit a CC5 character bake job to the Flamenco render farm.
.DESCRIPTION
    Sends an API request to the Flamenco Manager to queue a CC5 bake job.
    The render node will run Blender headless with cc5_bake.py to produce
    a game-ready GLB from the FBX.

    Does NOT require elevation.
.EXAMPLE
    .\Submit-CC5Bake.ps1 -InputFile \\FLAMINGDRAGON\RenderFarm\CC5Inbox\female.fbx
    .\Submit-CC5Bake.ps1 -InputFile R:\CC5Inbox\female.fbx -Resolution 4096
    .\Submit-CC5Bake.ps1 -InputFile R:\CC5Inbox\female.fbx -ServerIP 192.168.0.107 -NoGpu
.PARAMETER InputFile
    Path to the CC5 FBX file (must be accessible from the render node).
.PARAMETER OutputFile
    Path for output GLB. Defaults to RenderFarm\Output\<inputname>.glb.
.PARAMETER Resolution
    Bake texture resolution in pixels (default: 2048).
.PARAMETER ServerIP
    Flamenco Manager IP. Auto-detected from config or mapped drive.
.PARAMETER NoGpu
    Disable GPU baking (use CPU only).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [string]$InputFile,

    [string]$OutputFile,
    [int]$Resolution = 2048,
    [string]$ServerIP,
    [switch]$NoGpu,
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'farm-config.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Load config ---
$Cfg = $null
if (Test-Path $ConfigPath) {
    $Cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json
}

# --- Resolve server ---
if (-not $ServerIP) {
    if ($Cfg) {
        $driveLetter = $Cfg.client.drive_letter
        $infoFile = Join-Path $driveLetter 'connection-info.txt'
        if (Test-Path $infoFile) {
            $content = Get-Content $infoFile -Raw
            if ($content -match 'IP:\s+(\d+\.\d+\.\d+\.\d+)') {
                $ServerIP = $Matches[1]
            }
        }
    }
    if (-not $ServerIP) {
        Write-Host "  [FATAL] Cannot determine server IP. Use -ServerIP." -ForegroundColor Red
        exit 1
    }
}

$port = if ($Cfg) { $Cfg.flamenco.manager_port } else { 8080 }
$managerUrl = "http://${ServerIP}:${port}"

# --- Resolve output path ---
if (-not $OutputFile) {
    $inputName = [System.IO.Path]::GetFileNameWithoutExtension($InputFile)
    $shareName = if ($Cfg) { $Cfg.server.share_name } else { 'RenderFarm' }
    $outputSubdir = if ($Cfg) { $Cfg.server.output_subdir } else { 'Output' }
    $OutputFile = "\\$ServerIP\$shareName\$outputSubdir\${inputName}.glb"
}

# --- Convert UNC paths to local paths for the render node ---
# The render node sees \\server\RenderFarm as C:\RenderFarm
$storageRoot = if ($Cfg) { $Cfg.server.storage_root } else { 'C:\RenderFarm' }
$shareName = if ($Cfg) { $Cfg.server.share_name } else { 'RenderFarm' }

function Convert-ToNodeLocal {
    param([string]$UncPath)
    # \\server\RenderFarm\subdir\file → C:\RenderFarm\subdir\file
    $patterns = @(
        "\\\\[^\\]+\\$shareName\\",
        "\\\\[^\\]+\\$shareName/"
    )
    $result = $UncPath
    foreach ($p in $patterns) {
        $result = $result -replace [regex]::Escape($p.TrimEnd('\\/')), $storageRoot
    }
    # Also handle drive-letter mapped paths (R:\subdir → C:\RenderFarm\subdir)
    if ($Cfg) {
        $dl = $Cfg.client.drive_letter
        if ($result -like "$dl*") {
            $result = $result -replace [regex]::Escape($dl), $storageRoot
        }
    }
    return $result
}

$nodeInputFile = Convert-ToNodeLocal $InputFile
$nodeOutputFile = Convert-ToNodeLocal $OutputFile

Write-Host ""
Write-Host "  Submit-CC5Bake" -ForegroundColor Cyan
Write-Host "  Manager:    $managerUrl" -ForegroundColor DarkGray
Write-Host "  Input:      $InputFile" -ForegroundColor DarkGray
Write-Host "  Output:     $OutputFile" -ForegroundColor DarkGray
Write-Host "  Node input: $nodeInputFile" -ForegroundColor DarkGray
Write-Host "  Resolution: ${Resolution}px" -ForegroundColor DarkGray
Write-Host "  GPU:        $(-not $NoGpu)" -ForegroundColor DarkGray
Write-Host ""

# --- Verify manager is reachable ---
try {
    $version = curl.exe -s "$managerUrl/api/v3/version" | ConvertFrom-Json
    Write-Host "  [OK] Manager: $($version.name) $($version.version)" -ForegroundColor Green
} catch {
    Write-Host "  [FATAL] Cannot reach Flamenco Manager at $managerUrl" -ForegroundColor Red
    exit 1
}

# --- Submit job via API ---
$jobPayload = @{
    name     = "CC5 Bake: $([System.IO.Path]::GetFileName($InputFile))"
    type     = "cc5-bake"
    priority = 50
    settings = @{
        input_file  = $nodeInputFile
        output_file = $nodeOutputFile
        resolution  = $Resolution
        use_gpu     = (-not $NoGpu)
    }
} | ConvertTo-Json -Depth 5

try {
    $response = curl.exe -s -X POST "$managerUrl/api/v3/jobs" `
        -H "Content-Type: application/json" `
        -d $jobPayload

    $job = $response | ConvertFrom-Json

    if ($job.id) {
        Write-Host "  [OK] Job submitted: $($job.id)" -ForegroundColor Green
        Write-Host "       Name: $($job.name)" -ForegroundColor White
        Write-Host "       Monitor: $managerUrl/jobs/$($job.id)" -ForegroundColor White
    } else {
        Write-Host "  [WARN] Job submitted but no ID returned. Response:" -ForegroundColor Yellow
        Write-Host "         $response" -ForegroundColor DarkGray
    }
} catch {
    Write-Host "  [ERR] Failed to submit job: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "        Response: $response" -ForegroundColor DarkGray
    exit 1
}

Write-Host ""
Write-Host "  Output will appear at: $OutputFile" -ForegroundColor White
Write-Host "  Monitor at: $managerUrl" -ForegroundColor DarkGray
Write-Host ""
