---
id: "007"
title: "Connect monolith via Ethernet (bandwidth upgrade)"
status: open
priority: low
blocked_by: []
---

# Connect monolith via Ethernet

## Context

monolith is on 2.4 GHz Wi-Fi (270 Mbps negotiated, ~13 MB/s measured). It has an unused Ethernet port (`eno1`). Plugging in would give ~100 MB/s (Gigabit) — 7x improvement for large asset sync.

## Deliverables

- [ ] Physically connect monolith to router/switch via Ethernet
- [ ] Verify eno1 gets DHCP address
- [ ] Update farm-config.json with new IP (if changed)
- [ ] Update Syncthing device address (currently tcp://192.168.0.48:22000)
- [ ] Measure new throughput (iperf3 or SCP test)
- [ ] Consider 2.5GbE USB adapter for FLAMINGDRAGON if router supports it

## Expected Result

Large CC5 FBX files (500-900 MB) transfer in 5-9 seconds instead of 37-66 seconds.
