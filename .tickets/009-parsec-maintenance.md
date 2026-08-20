---
id: "009"
title: "Document and script Parsec headless maintenance"
status: open
priority: low
blocked_by: []
---

# Parsec Headless Maintenance

## Context

FLAMINGDRAGON is accessible via Parsec with the lid closed (VDA routed to RTX 5080). This was configured via system-health scripts. Document and maintain this for the farm — it enables remote CC5 work and troubleshooting.

## Deliverables

- [ ] Move Set-ParsecHeadless.ps1 and Fix-ParsecVDA.ps1 from system-health to this repo (or reference)
- [ ] Add Parsec health check to a future `farmctl health` or status script
- [ ] Document: if VDA reverts to Error after driver update, re-run Fix-ParsecVDA.ps1
- [ ] Add to farm-setup skill: Parsec section for remote access
