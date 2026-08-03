---
name: Android runtime release
description: Constraints for publishing and consuming the prebuilt Android ARM64 Termux runtime.
---

The public Termux install path uses a rolling `termux-latest` GitHub Release containing the Android ARM64 npm runtime tarball and a SHA-512 sidecar. The launcher must verify the sidecar before extraction and retain a valid cache for later offline starts.

**Why:** Termux users should not need Rust or the Android NDK, and a partially downloaded or replaced native binary must never be executed.

**How to apply:** Any future change to the release workflow or launcher must preserve the asset names, checksum verification, cache behavior, and ARM64/API 29 package contract. Keep `verify-patches.sh` aligned with the workflow's intentional release permissions and publishing steps.