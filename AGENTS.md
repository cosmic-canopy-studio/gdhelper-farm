# gdhelper-farm — Render Farm Fleet Management

Manages a distributed render farm for the gdhelper tool family. Handles machine provisioning, Flamenco job orchestration, Syncthing asset sync, and worker lifecycle — across Windows and Linux nodes.

## Project Type

Infrastructure tooling. PowerShell scripts (Windows), Bash (Linux), JSON config. Future: Go CLI (`farmctl`).

## Workspace Layout

```
.memory/           Persistent context (glossary, ADRs)
.memory/CONTEXT.md Project glossary
.memory/adr/       Architecture decision records
.scratch/          Ephemeral working notes (gitignored)
.references/       Research + prior art (gitignored)
.tickets/          Git-native tickets (tkt)
.kiro/skills/      Agent skills for farm management

scripts/           PowerShell setup/management scripts
jobs/              Flamenco custom job type definitions (.js)
blender/           Blender headless automation scripts (.py)
farm-config.json   Fleet topology and shared configuration
```

## Key Scripts

| Script | Purpose | Runs on | Admin |
|--------|---------|---------|-------|
| `Set-FarmServer.ps1` | Configure hub node (share, firewall, Flamenco, Defender, Shaman) | Hub | Yes |
| `Set-FarmClient.ps1` | Configure workstation (map share, verify tools) | Workstation | No |
| `Install-FarmServices.ps1` | Install Flamenco as Windows Services (WinSW) | Hub | Yes |
| `Install-Syncthing.ps1` | Install + configure Syncthing for asset pre-staging | Any | Yes |
| `Send-CC5Asset.ps1` | Transfer CC5 assets to render node inbox | Workstation | No |
| `Submit-CC5Bake.ps1` | Queue a CC5 bake job via Flamenco REST API | Workstation | No |

## Architecture

```
SharkTank (workstation) ◄── Syncthing bidirectional ──► FLAMINGDRAGON (hub)
                                                              │
                                                    Syncthing │ send-only
                                                              ▼
                                                        monolith (worker)
```

Flamenco Manager runs on the hub. Workers on hub + monolith pull jobs. Assets sync continuously via Syncthing so they're local when jobs start.

## Fleet Details (from farm-config.json)

- Hub: FLAMINGDRAGON (RTX 5080, 16 GB VRAM)
- Worker: monolith (RTX 3070, 8 GB VRAM)
- Workstation: SharkTank

## Commands

```powershell
# Server setup (run once on hub, as admin)
gsudo .\scripts\Set-FarmServer.ps1

# Install persistent services (run once on hub, as admin)
gsudo .\scripts\Install-FarmServices.ps1

# Client setup (run once on workstation)
.\scripts\Set-FarmClient.ps1 -ServerIP 192.168.0.107

# Submit a CC5 bake job
.\scripts\Submit-CC5Bake.ps1 -InputFile R:\CC5Inbox\character.fbx

# Transfer + auto-bake
.\scripts\Send-CC5Asset.ps1 -Path D:\CC5\Exports\character.fbx -SubmitBake
```

## Conventions

- Scripts are idempotent (safe to run repeatedly)
- Scripts support `-WhatIf` for dry-run preview
- All machine-specific values auto-detected (not hardcoded)
- `farm-config.json` contains only portable settings (IDs, roles, ports)
- Exit codes: 0=success, 1=fatal, 2=partial
- Logs written to `C:\RenderFarm\logs\` (hub) or `.scratch/` (client)

## Dependencies

- Flamenco 3.9.3+ (render job management)
- Syncthing 2.x (asset sync)
- Blender 5.2 LTS (must match across all nodes)
- WinSW (Windows service wrapper)
- NVIDIA GPU drivers with CUDA support

## Related Projects

- `gdhelper-pipeline` — Blender→Godot asset pipeline (consumes this farm)
- `system-health` — Windows system health scripts (where farm was prototyped)
