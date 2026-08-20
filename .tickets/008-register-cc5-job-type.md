---
id: "008"
title: "Register and test cc5-bake custom job type in Flamenco"
status: open
priority: high
blocked_by: []
---

# Register cc5-bake Custom Job Type

## Context

`jobs/cc5-bake.js` defines a Flamenco custom job type but hasn't been tested with the actual Flamenco Manager. The job compiler JS API may need adjustments based on the real Flamenco 3.9.3 behavior.

## Deliverables

- [ ] Copy `cc5-bake.js` to `C:\RenderFarm\Flamenco\scripts\` on hub
- [ ] Restart Flamenco Manager service
- [ ] Verify job type appears in Flamenco web UI
- [ ] Submit a test job via the web UI
- [ ] Submit a test job via `Submit-CC5Bake.ps1`
- [ ] Fix any issues with the JS compiler script
- [ ] Document working job type in skill

## Reference

- `.references/research/flamenco-custom-jobs.md` — full JS API documentation
