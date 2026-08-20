---
id: "002"
title: "Add monolith as Flamenco worker node"
status: open
priority: medium
blocked_by: []
---

# Add monolith as Flamenco Worker

## Context

monolith (Ubuntu 25.10, RTX 3070, 64 GB RAM) is validated as capable. Syncthing connection is live. Needs Blender + Flamenco worker installed.

## Deliverables

- [ ] Install Blender 5.2 LTS (snap or manual — must match hub)
- [ ] Install cc_blender_tools addon
- [ ] Download flamenco-worker binary
- [ ] Create systemd service pointing at FLAMINGDRAGON manager
- [ ] Set FLAMENCO_WORKER_NAME=monolith-RTX3070
- [ ] Verify worker appears in Flamenco dashboard (awake)
- [ ] Submit test render → verify monolith picks it up
- [ ] Write provisioning script (`Add-Worker-Linux.sh`)

## Machine

- IP: 192.168.0.48
- SSH: sam@monolith-wifi.lan
- GPU: RTX 3070 (8 GB, CUDA 8.6)
- Flamenco Manager: http://192.168.0.107:8080
