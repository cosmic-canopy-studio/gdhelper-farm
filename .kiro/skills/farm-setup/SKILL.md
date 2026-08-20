---
name: farm-setup
description: "Configure, operate, and troubleshoot the Flamenco render farm. Covers server/client setup, Windows service installation, CC5 character bake offloading, asset transfer between machines, and job submission. Trigger: render farm, flamenco, farm setup, render node, offload, distributed render, submit job, bake character, CC5 bake, send asset, farm service, farm not working."
triggers:
  - render farm
  - flamenco
  - farm setup
  - render node
  - offload
  - distributed render
  - submit render job
  - submit bake
  - bake character
  - CC5 bake
  - CC5 offload
  - send asset
  - transfer to render
  - farm service
  - farm connection
  - farm not working
  - install farm
---

# Render Farm — Complete Tool Reference

## Tools Inventory

All scripts live in `tools/farm/`. No hardcoded machine values — all auto-detect or read `farm-config.json`.

| Script | Role | Runs on | Requires Admin |
|--------|------|---------|---------------|
| `Set-FarmServer.ps1` | One-time server setup (share, firewall, config) | Render node | Yes |
| `Set-FarmClient.ps1` | One-time client setup (map share, verify tools) | Workstation | No |
| `Install-FarmServices.ps1` | Install Flamenco as persistent Windows Services | Render node | Yes |
| `Send-CC5Asset.ps1` | Transfer CC5 files to render node inbox | Workstation | No |
| `Submit-CC5Bake.ps1` | Queue a CC5 bake job via Flamenco API | Workstation | No |
| `cc5_bake.py` | Blender headless script (import FBX, bake, export GLB) | Render node (automatic) | — |
| `cc5-bake.js` | Flamenco custom job type definition | Render node (Flamenco) | — |
| `farm-config.json` | Shared configuration (portable, no machine-specific values) | Both | — |

---

## Architecture

```
┌──────────────────────────────────┐           ┌───────────────────────────────────────┐
│  WORKSTATION                     │           │  RENDER NODE                          │
│                                  │   LAN     │                                       │
│  Send-CC5Asset.ps1 ─────────────────────────►│  C:\RenderFarm\CC5Inbox\              │
│  Submit-CC5Bake.ps1 ─── REST API ──────────►│  Flamenco Manager (:8080)             │
│                                  │           │    └─► Flamenco Worker                │
│  Blender + Flamenco addon        │   SMB     │        └─► Blender --background      │
│  R: ◄──────────────────────────────────────── │            └─► cc5_bake.py           │
│     \\server\RenderFarm\Output\  │   share   │                └─► GLB output        │
│                                  │           │                                       │
│  CC5 (GUI) ── export FBX ────────────────────►│  OR: CC5 via Parsec (GUI on node)    │
└──────────────────────────────────┘           └───────────────────────────────────────┘
```

---

## Initial Setup (run once per machine)

### Server (render node)

```powershell
# 1. Configure shares, firewall, Flamenco config, Defender exclusions
gsudo .\tools\farm\Set-FarmServer.ps1

# 2. Complete Flamenco setup wizard in browser (first run only)
#    URL is printed by the script — set shared storage to C:\RenderFarm\Jobs

# 3. Install as persistent Windows Services (survive reboot/logout)
gsudo .\tools\farm\Install-FarmServices.ps1
```

**After this:** Flamenco Manager + Worker run as services. No open windows needed.

### Client (workstation)

```powershell
# Provide the server IP from the connection info output
.\tools\farm\Set-FarmClient.ps1 -ServerIP 192.168.0.107
```

**After this:** Share is mapped at `R:`, Blender version verified, missing addons flagged.

---

## CC5 Character Bake Offload

### Critical: Baked Texture Transfer

When CC5 runs on FLAMINGDRAGON (render node), it bakes skin/hair diffuse textures to a **local temp folder** — not the FBX export directory. These must be copied to the shared export folder before Blender import on the workstation:

```powershell
# Run ON FLAMINGDRAGON after CC5 FBX export:
$src = "$env:LOCALAPPDATA\Temp\CharacterCreator5Temp\BakeTexture"
$dest = "C:\RenderFarm\Jobs\cc5-projects\<export-folder>\textures"

Get-ChildItem $src -Filter "result_*" | ForEach-Object {
    Copy-Item $_.FullName (Join-Path $dest ($_.Name -replace "^result_", ""))
}
```

Without this, the character imports with white skin and colorless hair.

### Quick Path (one command)

```powershell
# Export FBX from CC5 on workstation, then:
.\tools\farm\Send-CC5Asset.ps1 -Path "D:\CC5\Exports\female.fbx" -SubmitBake
```

This transfers the FBX to the render node AND submits a bake job. The RTX 5080 produces a game-ready GLB at `R:\Output\female.glb`.

### Step-by-Step Path

```powershell
# 1. Transfer asset(s) to render node
.\tools\farm\Send-CC5Asset.ps1 -Path "D:\CC5\Exports\*.fbx" -ServerIP 192.168.0.107

# 2. Submit bake job(s) individually
.\tools\farm\Submit-CC5Bake.ps1 -InputFile "R:\CC5Inbox\female.fbx"
.\tools\farm\Submit-CC5Bake.ps1 -InputFile "R:\CC5Inbox\male.fbx" -Resolution 4096

# 3. Monitor at Flamenco web UI
# URL printed by Submit-CC5Bake, e.g. http://192.168.0.107:8080

# 4. Pick up results
# GLB appears at R:\Output\female.glb when complete
```

### Parsec Path (work in CC5 on render node)

```powershell
# Send CC5 project files to the render node
.\tools\farm\Send-CC5Asset.ps1 -Path "D:\CC5\Projects\MyCharacter\"

# Then Parsec into the render node → open CC5 → work on character
# Export FBX locally (no network transfer) → bake locally or via Flamenco
```

---

## Blender Render Offload (standard Flamenco)

For regular Blender scene rendering (not CC5-specific):

1. Open .blend file on workstation
2. Set output to `R:\Output\`
3. Flamenco panel → Submit to Flamenco
4. Monitor at the Flamenco web UI

---

## Service Management

```powershell
# Check status
Get-Service Flamenco*

# Stop/start
Stop-Service FlamencoManager   # Also stops worker (dependency)
Start-Service FlamencoManager
Start-Service FlamencoWorker

# View logs
Get-Content C:\RenderFarm\logs\FlamencoManager.out.log -Tail 50
Get-Content C:\RenderFarm\logs\FlamencoWorker.out.log -Tail 50

# Reinstall (after update or config change)
gsudo .\tools\farm\Install-FarmServices.ps1
```

---

## Submit-CC5Bake Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `-InputFile` | Yes | — | Path to CC5 FBX (on share or mapped drive) |
| `-OutputFile` | No | `R:\Output\<name>.glb` | Output GLB path |
| `-Resolution` | No | 2048 | Bake texture resolution (px) |
| `-ServerIP` | No | Auto-detect | Flamenco Manager IP |
| `-NoGpu` | No | False | Disable GPU, use CPU baking |

## Send-CC5Asset Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `-Path` | Yes | — | File, directory, or wildcard to transfer |
| `-ServerIP` | No | Auto-detect | Render node IP |
| `-SubmitBake` | No | False | Auto-submit bake job for each FBX transferred |
| `-Inbox` | No | `CC5Inbox` | Subdirectory on share for incoming assets |

---

## Configuration

`tools/farm/farm-config.json` — portable settings, no machine-specific values:

```json
{
  "farm": { "name": "pnw-farm" },
  "server": { "storage_root": "C:\\RenderFarm", "share_name": "RenderFarm" },
  "flamenco": { "version": "3.9.3", "manager_port": 8080 },
  "blender": { "required_version": "5.2" },
  "client": { "drive_letter": "R:" }
}
```

Server IP, hostname, Blender path, GPU — all auto-detected at runtime.

---

## Custom Job Type: cc5-bake

The `cc5-bake.js` file defines a Flamenco job type. To register it:

1. Copy `cc5-bake.js` to `C:\RenderFarm\Flamenco\scripts\` on the render node
2. Restart Flamenco Manager service: `Restart-Service FlamencoManager`
3. In Blender's Flamenco addon: click "Refresh from Manager"

The job type accepts: `input_file`, `output_file`, `resolution`, `use_gpu`.

---

## Troubleshooting

### "Cannot determine server IP"
All client-side scripts auto-detect the server IP from `R:\connection-info.txt` (written by Set-FarmServer). If the drive isn't mapped yet, pass `-ServerIP` explicitly.

### Bake job fails with "cc_blender_tools not found"
Blender on the render node needs `cc_blender_tools` addon installed in its preferences. Open Blender GUI once on the render node, install the addon, save preferences.

### "Flamenco port not responding"
```powershell
# Check service status
Get-Service FlamencoManager
# If stopped, start it
Start-Service FlamencoManager
# Check logs for crash reason
Get-Content C:\RenderFarm\logs\FlamencoManager.out.log -Tail 20
```

### Transfer is slow
The setup uses Wi-Fi (576 Mbps). For large assets (>500 MB):
- Connect both machines via Ethernet for ~10x speed
- Or use Parsec to work directly on the render node (avoids transfer entirely)

### Multiple workers registered
```powershell
# Check via API
curl.exe -s http://SERVER_IP:8080/api/v3/worker-mgt/workers
# Delete stale ones via web UI or API
curl.exe -X DELETE http://SERVER_IP:8080/api/v3/worker-mgt/workers/STALE_ID
```

### Services won't start after reboot
```powershell
# Reinstall (idempotent)
gsudo .\tools\farm\Install-FarmServices.ps1
```

### Flamenco manager YAML gets overwritten by wizard
The setup wizard overwrites the config. Set-FarmServer.ps1 backs up to `.yaml.bak`. After wizard completes, re-run Set-FarmServer if needed — or just configure via the web UI.

---

## End-to-End CC5 → Blender → Godot

```
CC5 (workstation or render node via Parsec)
  │ Export FBX
  ▼
Send-CC5Asset.ps1 -SubmitBake
  │ Transfer + queue job
  ▼
Flamenco → cc5_bake.py (on render node GPU)
  │ Import FBX → Bake textures → Export GLB
  ▼
R:\Output\character.glb
  │ Import into Godot
  ▼
Godot test-scene
  │ Apply toon shader + BoneMap + fix hair alpha
  ▼
Game-ready character
```

---

## Syncthing Fleet (Asset Pre-Staging)

### Fleet Topology

```
SharkTank (workstation) ◄── Send-Receive ──► FLAMINGDRAGON (hub) ── Send-Only ──► monolith (worker)
```

### Device IDs

| Machine | Role | Device ID |
|---------|------|-----------|
| FLAMINGDRAGON | Hub + Introducer | `MGWRJ67-GUJ6W4R-...` |
| SharkTank | Workstation | `5XNLRSE-GNXNR7A-...` |
| monolith | Worker (Docker) | `X7WRJFJ-EY67OD2-...` |

### Configuration Script

```powershell
# Configure this machine's Syncthing (after Install-Syncthing.ps1)
.\tools\farm\Configure-Syncthing.ps1 -Role Hub          # FLAMINGDRAGON
.\tools\farm\Configure-Syncthing.ps1 -Role Workstation  # SharkTank
.\tools\farm\Configure-Syncthing.ps1 -Role Worker       # monolith (via SSH)
```

### Syncthing Management Commands

```powershell
# Check service status
Get-Service Syncthing

# Restart (picks up config changes)
Restart-Service Syncthing

# View logs
Get-Content C:\RenderFarm\logs\syncthing-svc.out.log -Tail 20

# Get device ID
syncthing device-id

# Set API key (required before REST calls work)
syncthing cli config gui apikey set "your-shared-api-key"

# Check connections via REST
curl.exe -H "X-API-Key: YOUR_KEY" http://localhost:8384/rest/system/connections
```

### Troubleshooting Syncthing

#### "Connection rejected: unknown device"
The remote device's ID isn't in this machine's config. Add it via web UI (http://localhost:8384) or Configure-Syncthing.ps1.

#### Connect/disconnect loop ("reading length: EOF")
Folder IDs or device IDs don't match between the two nodes. Check that both sides have identical folder IDs and the correct local device ID in folder entries.

#### Service won't start
Config file may be missing or corrupted. Check `C:\RenderFarm\logs\syncthing-svc.err.log`. Fix: `syncthing generate` to create fresh config, then reconfigure.

#### CSRF Error on REST API
API key not matching. Set via: `syncthing cli config gui apikey set "KEY"` then use `-H "X-API-Key: KEY"` in curl calls.

#### Windows service uses different config path
Service runs as SYSTEM → config at `C:\Windows\System32\config\systemprofile\AppData\Local\Syncthing\`. Either run service as your user, or use `--home` flag in the WinSW XML to point to a known path.

### Folder Sync Rules

| Folder | SharkTank | FLAMINGDRAGON | monolith |
|--------|-----------|---------------|----------|
| Assets/ | Send-Receive | Send-Receive | Receive-Only |
| CC5Inbox/ | Send-Receive | Send-Receive | Receive-Only |
| Jobs/ | Send-Receive | Send-Receive | Receive-Only |
| Output/ | Receive-Only | Send-Only | Not synced |
