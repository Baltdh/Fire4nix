# Fire4Nix — xmlstarlet source fetch blockage in genuine ROCKNIX bootstrap

## Physical target and pinned source

Fire4Nix targets the existing R36H ROCKNIX 20260801-compatible rootfs:
RK3326/AArch64; glibc observed on device 2.41. The actual browser WPE WebKit
must still be built with a matching cross-toolchain/sysroot.

## Failure evidence

GitHub Actions [run 39520551993](https://github.com/Baltdh/Fire4nix/actions/runs/39520551993)
failed while fetching xmlstarlet 1.6.1. Original SourceForge netcologne
host failed DNS; the distribution-sources fallback returned HTTP 404.
Prior failed downloads included 7-Zip and GNU configtools, which now have
independent source-hash gates.

ROCKNIX distribution commit
`3b9cb1f6bf48ee9ca0cf01edd9af52ca2a6b73fb` has source recipe
`packages/textproc/xmlstarlet/package.mk` pinned to:

- `PKG_VERSION="1.6.1"`
- `PKG_SHA256="15d838c4f3375332fd95554619179b69e4ec91418a3a5296e7c631b7ed19e7ca"`

## Verified replacement (same tarball, no altered checksum)

[GitHub Actions 39525630567](https://github.com/Baltdh/Fire4nix/actions/runs/39525630567)
confirmed the archive at:

`https://sources.libreelec.tv/mirror/xmlstarlet/xmlstarlet-1.6.1.tar.gz`

The artifact has **420923 bytes**, SHA256 equals the ROCKNIX recipe exactly,
and its archive contains `xmlstarlet-1.6.1/configure`.
Only the URL was changed in an isolated build-host checkout; `git diff --name-only`
showed precisely `packages/textproc/xmlstarlet/package.mk`. The original
`PKG_VERSION` and `PKG_SHA256` were preserved.

## Integration

The scripts `scripts/verify-rocknix-xmlstarlet-source.sh` and
`rocknix-integration/stage-xmlstarlet-source-mirror.sh` run as part of
`scripts/build-rocknix-rk3326-toolchain.sh`, following the configtools
preflight and before `./scripts/build toolchain`.

The stage script refuses non-CI execution, checks the exact upstream commit
and original recipe, demands a matching verified digest and HTTPS URL from an
allowlist, and edits only the single URL line. No file in the ROCKNIX console
rootfs, firmware, or removable SD is changed.

Use [the dedicated preflight workflow](https://github.com/Baltdh/Fire4nix/actions/workflows/verify-rocknix-xmlstarlet-source.yml)
to validate source provenance before any repeated multi-hour toolchain build.

**Scope limitation:** a successful source check does **not** mean the ROCKNIX
cross-compiler, WPE engine, JavaScriptCore, TLS modules, or R36H graphical
rendering has passed. Additional external source fetches may still fail.
