---
id: "005"
title: "Harden farm security (share permissions, network isolation)"
status: open
priority: low
blocked_by: []
---

# Harden Farm Security

## Context

Current setup uses Authenticated Users with Change access and SMB encryption. This is adequate for a home LAN but should be reviewed as the farm grows.

## Items to Address

- [ ] Create dedicated local group (RenderFarm-Workers) instead of Authenticated Users
- [ ] Separate Read (asset input) vs Write (output) permissions per folder
- [ ] Review Syncthing encryption-in-transit (TLS 1.3 — already default)
- [ ] Consider Windows Firewall IP-scoped rules (only farm subnet)
- [ ] Audit Defender exclusions — are they too broad?
- [ ] Review Flamenco Manager access (no auth currently — add API key/basic auth)
- [ ] Document security posture in an ADR

## Reference

- `.references/research/render-farm-security.md` — full security research
