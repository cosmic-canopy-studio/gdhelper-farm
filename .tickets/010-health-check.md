---
id: "010"
title: "Write Get-FarmHealth.ps1 unified health check"
status: open
priority: medium
blocked_by: ["001"]
---

# Unified Farm Health Check

## Context

Checking farm health currently requires: checking 3 services on FLAMINGDRAGON, SSH to monolith, verifying Syncthing connections, checking Flamenco workers. A single script should report the full picture.

## What It Checks

- [ ] Flamenco Manager service running + port responding
- [ ] Flamenco Worker(s) registered and awake
- [ ] Syncthing service running + all peers connected
- [ ] Syncthing folders in "idle" state (not errored)
- [ ] Parsec VDA status (OK vs Error)
- [ ] GPU utilization and temperature
- [ ] Disk space on render storage
- [ ] monolith reachable via SSH + worker status
- [ ] SharkTank Syncthing connected (visible from hub API)

## Output Format

```
Farm: pnw-farm
Status: HEALTHY (or DEGRADED / DOWN)

Services:
  FlamencoManager   Running  ✓
  FlamencoWorker    Running  ✓
  Syncthing         Running  ✓
  Parsec VDA        OK       ✓

Connections:
  SharkTank         Connected (2s ago)  ✓
  monolith          Connected (5s ago)  ✓

Workers:
  FLAMINGDRAGON-RTX5080  awake  idle
  monolith-RTX3070       awake  idle

Storage:
  C:\RenderFarm  87 GB free (93%)  ✓
```
