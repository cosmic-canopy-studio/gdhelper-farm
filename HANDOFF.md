# HANDOFF — gdhelper-farm

## What This Project Is

`gdhelper-farm` is the render farm fleet management tool for the gdhelper family. It manages distributed rendering (Flamenco), asset synchronization (Syncthing), and worker provisioning across a 3-machine creative studio setup.

## How It Serves gdhelper-pipeline

`gdhelper-pipeline` is a Blender-to-Godot asset pipeline (CC5 characters, stylized shaders, toon rendering). Its bottleneck is GPU-intensive work:
- **Texture baking** (cc_blender_bake for CC5 characters → 5-15 min per character)
- **Scene rendering** (Cycles GPU renders for quality checks)
- **Batch processing** (multiple characters/scenes queued overnight)

`gdhelper-farm` offloads that work to dedicated GPU nodes so the artist's workstation stays responsive. The workstation sends assets, the farm bakes/renders, results sync back automatically.

## Current State (as of 2026-08-20)

### What's Working
- **Flamenco Manager + Worker** running as Windows Services on FLAMINGDRAGON (RTX 5080)
- **Syncthing fleet** connected: SharkTank ↔ FLAMINGDRAGON ↔ monolith, 4 folders syncing
- **Parsec headless** — FLAMINGDRAGON accessible with lid closed (VDA fixed, routed to dGPU)
- **SMB shares** — `\\FLAMINGDRAGON\RenderFarm` with encryption enabled
- **Shaman** configured (content-dedup for repeat job submissions)
- **CC5 bake pipeline** scripted (cc5_bake.py + cc5-bake.js + Submit-CC5Bake.ps1)

### What's Not Done Yet (see tickets)
- **008** (HIGH) — cc5-bake.js custom job type not yet registered with Flamenco Manager
- **001** (HIGH) — Configure-Syncthing.ps1 fleet script (currently manual web UI pairing)
- **002** (MED) — monolith doesn't have Blender/Flamenco worker installed yet
- **003** (MED) — End-to-end CC5 bake not proven (scripts exist, not tested)
- **010** (MED) — No unified health check script

## Fleet Topology

```
SharkTank (workstation, artist works here)
    │
    │ Syncthing (bidirectional)
    ▼
FLAMINGDRAGON (hub + render node)
    ├── Flamenco Manager (:8080)
    ├── Flamenco Worker (RTX 5080, 16 GB VRAM)
    ├── Syncthing Introducer
    ├── SMB share (\\FLAMINGDRAGON\RenderFarm)
    ├── Parsec (headless remote access)
    │
    │ Syncthing (send-only → receive-only)
    ▼
monolith (worker node, Ubuntu 25.10)
    ├── RTX 3070, 8 GB VRAM, 64 GB RAM
    ├── Syncthing (Docker: godot-sync)
    └── Flamenco Worker (NOT YET INSTALLED — ticket 002)
```

## Key Files

| File | What It Does |
|------|-------------|
| `farm-config.json` | Fleet topology (device IDs, roles, ports, folders) |
| `scripts/Set-FarmServer.ps1` | One-time hub setup (idempotent, admin) |
| `scripts/Set-FarmClient.ps1` | One-time workstation setup (no admin) |
| `scripts/Install-FarmServices.ps1` | Flamenco as Windows Services |
| `scripts/Install-Syncthing.ps1` | Syncthing install + service |
| `scripts/Send-CC5Asset.ps1` | Transfer CC5 files to render node |
| `scripts/Submit-CC5Bake.ps1` | Queue bake job via Flamenco API |
| `blender/cc5_bake.py` | Headless: import FBX → GPU bake → export GLB |
| `jobs/cc5-bake.js` | Flamenco custom job type definition |
| `.kiro/skills/farm-setup/SKILL.md` | Agent instructions for all farm operations |

## Machine Details

| Machine | Hostname | IP | Syncthing Device ID |
|---------|----------|-----|---------------------|
| Hub | FLAMINGDRAGON | 192.168.0.107 | `XGRPB6R-QNBAIF2-YORV7QM-F64QNCX-P3YUQJK-GYDVGG4-P7B7TAV-JQVRVAB` |
| Worker | monolith | 192.168.0.48 | `X7WRJFJ-EY67OD2-MUTS7HM-2XSB3MF-KSSSUNU-HMYPPC6-VZYN52C-EUP65QP` |
| Workstation | SharkTank | dynamic | `5XNLRSE-GNXNR7A-WJIN3IB-DWAXAFS-UTWSMBP-XKCLTXH-INR7ILU-SEN3FQE` |

## Syncthing API Key

```
pnw-farm-fleet-sync-key
```

Used for REST API calls to `http://localhost:8384/rest/...` on FLAMINGDRAGON. Config lives at `C:\RenderFarm\syncthing-config\`.

## Flamenco Access

- Web UI: http://192.168.0.107:8080
- API: `http://192.168.0.107:8080/api/v3/...`
- Workers: `curl.exe -s http://192.168.0.107:8080/api/v3/worker-mgt/workers`

## Suggested First Actions

1. **Ticket 008** — Copy `jobs/cc5-bake.js` to `C:\RenderFarm\Flamenco\scripts\`, restart FlamencoManager, verify job type appears
2. **Ticket 010** — Write `Get-FarmHealth.ps1` that checks all services/connections in one shot
3. **Ticket 002** — SSH into monolith, install Blender 5.2, set up Flamenco worker as systemd service

## Research Available (in .references/)

13 research documents covering: Flamenco best practices, custom job JS API, render farm security, Syncthing fleet management, shared storage topology, CC5 headless capabilities, Blender headless baking, alternative sync tools, pre-staging patterns, and content-addressed storage evaluation.

## Conventions

- All scripts are **idempotent** (safe to run repeatedly)
- All scripts support **`-WhatIf`** for dry-run
- Machine-specific values are **auto-detected** (not hardcoded)
- `farm-config.json` is the **single source of truth** for fleet topology
- Exit codes: 0=success, 1=fatal, 2=partial
- Logs: `C:\RenderFarm\logs\` on hub, `.scratch/` on client
