# ROCKNIX RK3326 image audit — 2026-10-11

Reference: official ROCKNIX/distribution release 20260901, asset
`ROCKNIX-RK3326.aarch64-20260901.tar` (official release asset).
SHA-256: `118c5641d0f02ecbe1af1143c3de316d720bb0722df40ee0048cb2636e9d652f`.
The downloaded archive matched this digest. SYSTEM was extracted with unsquashfs;
no target binaries were executed. Ownership restoration is unavailable in this
container; library content was extracted without changing target bytes.

Compared with WPE 2.54.0 artifact from Fire4nix run 36968610673.
Six AArch64 ELF files inspected. No architecture errors or missing required
version nodes among resolved direct dependency providers. This is not a browser
execution test, nor proof of individual symbol or transitive dependency closure.

## Missing direct library names (20)

- `libavif.so.16`
- `libenchant-2.so.2`
- `libgstallocators-1.0.so.0`
- `libgstapp-1.0.so.0`
- `libgstaudio-1.0.so.0`
- `libgstgl-1.0.so.0`
- `libgstpbutils-1.0.so.0`
- `libgsttag-1.0.so.0`
- `libgstvideo-1.0.so.0`
- `libharfbuzz-icu.so.0`
- `libhyphen.so.0`
- `libicui18n.so.76`
- `libicuuc.so.76`
- `libjpeg.so.62`
- `libjxl.so.0.11`
- `liblcms2.so.2`
- `libseccomp.so.2`
- `libsoup-3.0.so.0`
- `libtasn1.so.6`
- `libwpe-1.0.so.1`

These must be built for the target or bundled with their own audited dependencies.
Do not replace system libc, graphics drivers or the dynamic loader with Debian
versions. ICU, JPEG, AVIF and JXL require exact SONAME compatibility; a newer
package version alone does not satisfy a different SONAME.

## Next gate

Stage missing libraries and audit the launcher plus the complete runtime against
this pinned image, including bundled library dependencies. Check dlopen modules,
loader path, certificates, media plugins and Wayland startup separately.
Only actual device testing can validate rendering, buttons and memory behavior.

The dependency auditor now resolves absolute sysroot symlinks inside the target
image, and rejects escape paths and loops. Seven dependency tests pass.

## Automated follow-up

The integration workflow now downloads and checksum-verifies the pinned official
image and audits the matched launcher plus staged WPE runtime against its library
files. The audit follows reachable system libraries recursively. It publishes a
separate compatibility report with BLOCKED or STATIC AUDIT PASSED status; successful
compilation does not imply target compatibility. No browser execution is claimed.
Eight dependency tests pass locally. The workflow requires its own CI validation.
