<#
.SYNOPSIS
    Transfer CC5 assets from workstation to the render node's inbox for processing.
.DESCRIPTION
    Copies CC5 project files (FBX exports, .ccProject folders, textures) to the
    render farm's shared storage where they can be:
      1. Opened in CC5 on the render node (via Parsec) for further editing
      2. Submitted as Flamenco bake jobs (FBX → GLB pipeline)

    Supports individual FBX files, directories, and .ccProject bundles.
    Provides progress feedback and validates file integrity via size comparison.

    Does NOT require elevation.
.EXAMPLE
    .\Send-CC5Asset.ps1 -Path D:\CC5\Exports\female.fbx
    .\Send-CC5Asset.ps1 -Path D:\CC5\Projects\MyCharacter -ServerIP 192.168.0.107
    .\Send-CC5Asset.ps1 -Path .\*.fbx -SubmitBake
.PARAMETER Path
    File or directory to send. Supports wildcards (*.fbx).
.PARAMETER ServerIP
    Render node IP. If omitted, reads from farm-config.json or connection-info.txt.
.PARAMETER SubmitBake
    After transfer, automatically submit a bake job for each FBX file.
.PARAMETER Inbox
    Subdirectory on the share for incoming assets (default: CC5Inbox).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [string]$Path,

    [string]$ServerIP,
    [switch]$SubmitBake,
    [string]$Inbox = 'CC5Inbox',
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'farm-config.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# --- Load config ---
$Cfg = $null
if (Test-Path $ConfigPath) {
    $Cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json
}

# --- Resolve server ---
if (-not $ServerIP) {
    # Try mapped drive's connection-info.txt
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
        Write-Host "  [FATAL] Cannot determine server IP." -ForegroundColor Red
        Write-Host "         Use -ServerIP or ensure drive is mapped with connection-info.txt" -ForegroundColor Red
        exit 1
    }
}

$shareName = if ($Cfg) { $Cfg.server.share_name } else { 'RenderFarm' }
$shareUNC = "\\$ServerIP\$shareName"
$inboxPath = Join-Path $shareUNC $Inbox

Write-Host ""
Write-Host "  Send-CC5Asset" -ForegroundColor Cyan
Write-Host "  Server: $ServerIP" -ForegroundColor DarkGray
Write-Host "  Inbox:  $inboxPath" -ForegroundColor DarkGray
Write-Host ""

# --- Verify connectivity ---
if (-not (Test-Path $shareUNC)) {
    Write-Host "  [FATAL] Cannot access $shareUNC" -ForegroundColor Red
    Write-Host "         Is the share mapped? Try: net use R: $shareUNC" -ForegroundColor Red
    exit 1
}

# --- Create inbox if needed ---
if (-not (Test-Path $inboxPath)) {
    New-Item -Path $inboxPath -ItemType Directory -Force | Out-Null
    Write-Host "  [OK] Created inbox: $inboxPath" -ForegroundColor Green
}

# --- Resolve source files ---
$sourceItems = Get-Item $Path -ErrorAction SilentlyContinue
if (-not $sourceItems) {
    # Try as wildcard
    $sourceItems = Get-ChildItem $Path -ErrorAction SilentlyContinue
}
if (-not $sourceItems) {
    Write-Host "  [FATAL] No files found matching: $Path" -ForegroundColor Red
    exit 1
}

# --- Transfer ---
$transferred = @()
$totalSize = 0

foreach ($item in $sourceItems) {
    $destPath = Join-Path $inboxPath $item.Name

    if ($item.PSIsContainer) {
        # Directory — robocopy for progress and speed
        Write-Host "  Copying directory: $($item.Name) ..." -ForegroundColor White
        $result = robocopy $item.FullName $destPath /E /NP /NFL /NDL /NJH /NJS 2>&1
        $dirSize = (Get-ChildItem $item.FullName -Recurse -File | Measure-Object Length -Sum).Sum
        $totalSize += $dirSize
        Write-Host "  [OK] $($item.Name) ($([math]::Round($dirSize / 1MB, 1)) MB)" -ForegroundColor Green
        $transferred += $destPath
    } else {
        # Single file
        $sizeMB = [math]::Round($item.Length / 1MB, 1)
        Write-Host "  Copying: $($item.Name) ($sizeMB MB) ..." -ForegroundColor White -NoNewline
        Copy-Item $item.FullName $destPath -Force
        $totalSize += $item.Length

        # Verify
        $destFile = Get-Item $destPath -ErrorAction SilentlyContinue
        if ($destFile -and $destFile.Length -eq $item.Length) {
            Write-Host " OK" -ForegroundColor Green
            $transferred += $destPath
        } else {
            Write-Host " FAILED (size mismatch)" -ForegroundColor Red
        }
    }
}

# --- Summary ---
Write-Host ""
Write-Host "  --- Transfer Complete ---" -ForegroundColor Cyan
Write-Host "  Files:      $($transferred.Count)" -ForegroundColor White
Write-Host "  Total size: $([math]::Round($totalSize / 1MB, 1)) MB" -ForegroundColor White
Write-Host "  Location:   $inboxPath" -ForegroundColor White
Write-Host ""

# --- Output for cross-machine use ---
$fbxFiles = $transferred | Where-Object { $_ -like '*.fbx' }
if ($fbxFiles) {
    Write-Host "  --- FBX Files Ready for Bake ---" -ForegroundColor Cyan
    foreach ($f in $fbxFiles) {
        Write-Host "    $f" -ForegroundColor White
    }
    Write-Host ""

    if ($SubmitBake) {
        Write-Host "  Submitting bake jobs..." -ForegroundColor Yellow
        $submitScript = Join-Path $PSScriptRoot 'Submit-CC5Bake.ps1'
        if (Test-Path $submitScript) {
            foreach ($f in $fbxFiles) {
                & $submitScript -InputFile $f -ServerIP $ServerIP
            }
        } else {
            Write-Host "  [WARN] Submit-CC5Bake.ps1 not found at $submitScript" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  To bake these characters, run:" -ForegroundColor DarkGray
        foreach ($f in $fbxFiles) {
            $outName = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetFileName($f), '.glb')
            $outPath = Join-Path (Join-Path $shareUNC 'Output') $outName
            Write-Host "    .\Submit-CC5Bake.ps1 -InputFile `"$f`" -ServerIP $ServerIP" -ForegroundColor DarkGray
        }
    }
} else {
    Write-Host "  Assets transferred. Open CC5 on render node (via Parsec) to process them." -ForegroundColor White
    Write-Host "  CC5 project location on render node: C:\RenderFarm\$Inbox\" -ForegroundColor DarkGray
}

Write-Host ""
