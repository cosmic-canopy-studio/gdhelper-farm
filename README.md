# gdhelper-farm

Render farm fleet management for the gdhelper tool family. Manages distributed rendering (Flamenco), asset synchronization (Syncthing), and worker provisioning across Windows and Linux nodes.

## Quick Start

```powershell
# On the hub/render node (admin):
gsudo .\scripts\Set-FarmServer.ps1
gsudo .\scripts\Install-FarmServices.ps1
gsudo .\scripts\Install-Syncthing.ps1

# On the workstation:
.\scripts\Set-FarmClient.ps1 -ServerIP <hub-ip>
```

## What It Does

- **Flamenco** — Distributes Blender render/bake jobs across GPU nodes
- **Syncthing** — Keeps project assets synchronized across all machines (pre-staging)
- **Shaman** — Deduplicates file transfers for repeat jobs (built into Flamenco)
- **CC5 Pipeline** — Offloads Character Creator 5 texture baking to GPU nodes

## Fleet

| Machine | Role | GPU | OS |
|---------|------|-----|-------|
| FLAMINGDRAGON | Hub (manager + worker) | RTX 5080 16GB | Windows 11 |
| monolith | Worker | RTX 3070 8GB | Ubuntu 25.10 |
| SharkTank | Workstation | — | Windows |

## Project Structure

```
scripts/           Setup and management scripts (PowerShell)
jobs/              Flamenco custom job types (JavaScript)
blender/           Blender headless automation (Python)
farm-config.json   Fleet configuration
```

## Submitting Jobs

```powershell
# Render a Blender scene
# (Use Flamenco addon in Blender → Submit to Flamenco)

# Bake a CC5 character (one command: transfer + submit)
.\scripts\Send-CC5Asset.ps1 -Path .\character.fbx -SubmitBake

# Or step by step:
.\scripts\Send-CC5Asset.ps1 -Path .\character.fbx
.\scripts\Submit-CC5Bake.ps1 -InputFile R:\CC5Inbox\character.fbx -Resolution 2048
```

## Requirements

- Blender 5.2 LTS (same version on all nodes)
- Flamenco 3.9.3+
- Syncthing 2.x
- NVIDIA GPU with CUDA drivers
- Windows: WinSW for service management
- Linux: systemd for service management
