---
id: "004"
title: "Spike: farmctl CLI (Go)"
status: open
priority: low
blocked_by: ["001", "003"]
---

# Spike: farmctl CLI

## Context

PowerShell scripts work but are fragile across platforms and hard to compose. A Go CLI provides a single binary that works on all nodes, wraps the REST APIs (Flamenco + Syncthing), and gives a unified UX.

## Question

Is a Go CLI worth building now, or are the PS1 scripts sufficient for current scale?

## Evaluate

- How often do manual tasks require multiple script invocations?
- Is cross-platform an actual need (monolith is Linux)?
- Would a TUI status dashboard save time vs checking web UIs?

## If Yes, MVP Scope

```bash
farmctl status              # All nodes, services, sync state
farmctl health              # Connectivity, disk, GPU, services
farmctl worker list         # Flamenco workers and jobs
farmctl submit bake <file>  # Submit CC5 bake job
farmctl sync status         # Syncthing connections + folders
```

## Deliverables (spike only)

- [ ] Decision: build or defer
- [ ] If build: `go mod init`, basic CLI structure, one working command (`farmctl status`)
- [ ] If defer: document what would trigger building it later
