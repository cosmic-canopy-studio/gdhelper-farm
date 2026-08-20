# Project Glossary

Terms and decisions specific to gdhelper-farm.

---

**Farm**:
A set of networked machines that share assets and distribute compute work (rendering, baking, processing). Not a single server — a coordinated fleet.
_Avoid_: "render farm" when referring to the sync-only layer; "cluster" (implies homogeneous nodes)

**Hub**:
The primary farm node that runs the Flamenco Manager, acts as Syncthing Introducer, and serves the SMB share. Currently FLAMINGDRAGON.
_Avoid_: "server" (it also renders), "master" (outdated term)

**Worker**:
A machine running a Flamenco Worker that accepts render/bake jobs. May also be a Syncthing receiver.
_Avoid_: "slave" (outdated), "client" (ambiguous — could mean Syncthing or Flamenco)

**Workstation**:
The actively-used creative machine where the artist works. Sends assets, receives output. Currently SharkTank.

**Fleet**:
The complete set of machines participating in the farm (hub + workers + workstation).

**Shaman**:
Flamenco's built-in content-addressable deduplication system. Only uploads changed files when submitting jobs.

**Introducer**:
A Syncthing device that automatically propagates folder shares to connected peers. The hub is the Introducer — add a folder to it, all peers get it.

**Pre-staging**:
Syncing assets to worker nodes before a job is submitted, so files are local when the job starts (zero transfer time at render time).
