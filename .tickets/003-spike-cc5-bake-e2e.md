---
id: "003"
title: "Spike: End-to-end CC5 bake via Flamenco"
status: open
priority: medium
blocked_by: ["002"]
---

# Spike: End-to-end CC5 Bake via Flamenco

## Question

Can we submit a CC5 character bake from SharkTank, have it execute on FLAMINGDRAGON's GPU, and get a game-ready GLB back — all automated?

## Steps

1. Export a CC5 character as FBX on SharkTank
2. Run `Send-CC5Asset.ps1 -SubmitBake` from SharkTank
3. Verify: FBX arrives on FLAMINGDRAGON (via Syncthing or direct copy)
4. Verify: Flamenco job appears in dashboard
5. Verify: Blender runs cc5_bake.py headless with GPU (OptiX)
6. Verify: GLB output appears in Output folder
7. Verify: GLB syncs back to SharkTank
8. Import GLB into Godot — mesh + textures correct

## Prerequisite

- cc_blender_tools addon installed on FLAMINGDRAGON's Blender
- cc5-bake.js registered with Flamenco Manager (in scripts/ directory)

## Acceptance Criteria

- [ ] Complete pipeline works end-to-end
- [ ] GPU bake time documented (vs CPU baseline)
- [ ] Any manual steps identified and ticketed for automation
