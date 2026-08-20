---
id: "006"
title: "Add job completion notifications (MQTT or webhook)"
status: open
priority: low
blocked_by: ["003"]
---

# Job Completion Notifications

## Context

Currently you must poll the Flamenco web UI to know when a job finishes. Flamenco 3.5+ supports MQTT. A notification when jobs complete (or fail) would close the feedback loop.

## Options

1. **Flamenco MQTT** — built-in, publish to local Mosquitto broker, consume via script/app
2. **Webhook script** — poll Flamenco API every 30s, send notification on state change
3. **Windows Toast** — PowerShell notification on the workstation when output appears
4. **Discord/Slack webhook** — post to a channel on completion

## Deliverables

- [ ] Choose notification mechanism
- [ ] Implement for job completion + job failure
- [ ] Test with a real bake job
