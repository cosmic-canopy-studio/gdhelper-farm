---
id: "001"
title: "Write Configure-Syncthing.ps1 fleet management script"
status: open
priority: high
blocked_by: []
---

# Write Configure-Syncthing.ps1

## Context

Syncthing pairing currently requires manual web UI interaction or fragile XML editing. A script that configures any node via the REST API (using the shared API key) makes the fleet reproducible.

## What It Does

```powershell
.\scripts\Configure-Syncthing.ps1 -Role Hub          # On FLAMINGDRAGON
.\scripts\Configure-Syncthing.ps1 -Role Workstation  # On SharkTank
.\scripts\Configure-Syncthing.ps1 -Role Worker       # On monolith (via SSH wrapper)
```

Reads `farm-config.json` for device IDs, determines role-based folder types, adds all peers via REST API.

## Acceptance Criteria

- [ ] Adds all fleet devices via REST API (X-API-Key auth)
- [ ] Creates folders with correct type per role (send-receive/send-only/receive-only)
- [ ] Sets hub as Introducer
- [ ] Handles Windows service context (--home flag)
- [ ] Handles Docker container context (SSH + docker exec)
- [ ] Idempotent (running twice = no changes)
- [ ] Outputs connection status
