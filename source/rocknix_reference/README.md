# ROCKNIX reference pack

These files are included to keep the next editing pass aligned with the real ROCKNIX environment used for Fire4Nix testing.

- `post-update`: shows how ROCKNIX synchronizes `/usr/config` into `/storage/.config`, which is useful for choosing safe config and log locations.
- `swayimgrc`: confirms the swayimg defaults and key bindings available in the environment.
- `MangoHud.aarch64.json`: documents the Vulkan overlay layer and the `MANGOHUD=1` / `DISABLE_MANGOHUD=1` toggles.
- `httpd.conf` and `host.conf`: show the local server and resolver defaults present on the system.
- `SYSTEM.md5`: identifier for the captured system image.
- `gtkbuilder.rng` and `LICENSE.txt`: retained as supporting reference files for compatibility and redistribution notes.
- `etc/dbus-1/system.conf` and `etc/dbus-1/session.conf`: document the system and session bus defaults.
- `etc/systemd/iocost.conf` and `etc/udev/udev.conf`: capture I/O and device-management tuning.
- `etc/profile.d/00-at-spi`, `etc/xdg/autostart/at-spi-dbus-bus.desktop`, and `etc/gtk-3.0/im-multipress.conf`: preserve accessibility, autostart, and input-method behavior.
- `etc/foot.ini`: records the Wayland terminal defaults that helped validate the shell environment.

These are reference artifacts only; they are not required by the browser at runtime.

- `devkit/armhf/` now carries build-time references captured from the uploaded ROCKNIX environment: `dbus-arch-deps.h`, `glibconfig.h`, `glib-2.0.pc`, `gmodule-2.0.pc`, `gio-2.0.pc`, `girepository-2.0.pc`, `cairo-xlib-xcb.pc`, `cairo-script.pc`, `xwayland.pc`, and `libdisplay-info.pc`. These are useful for Marco 2 / Marco 3 dependency detection and compile-time ABI matching.
- `runtime-tools/armhf/` now also includes `dbus-daemon-launch-helper` and `hostname` as helper snapshots for launch-flow comparison. They remain reference-only and are not wired into the browser runtime yet.

- `runtime-libs/aarch64/`: ARM64 shared-library snapshots captured from the uploaded runtime set. They are kept for future Marco 2 / Marco 3 build and compatibility work, especially for SONAME checks and Wayland/XWayland fallback comparison.

- `etc/dbus-1/system.d/nm-priv-helper.conf`, `etc/dbus-1/system.d/nm-dispatcher.conf`, `etc/dbus-1/system.d/avahi-dbus.conf`, and `etc/dbus-1/system.d/org.freedesktop.NetworkManager.conf`: capture the NetworkManager and Avahi D-Bus policy files used in the captured environment.

- `etc/NetworkManager/NetworkManager.conf` and `etc/tmpfiles.d/systemd-tmp.conf`: capture the NetworkManager and systemd tmpfiles defaults used in the ROCKNIX environment. They help with launch-flow, network policy, and filesystem cleanup comparisons.
- `devkit/armhf/pkgconfig/gio-2.0.pc`, `devkit/armhf/pkgconfig/girepository-2.0.pc`, `devkit/armhf/pkgconfig/cairo-xlib-xcb.pc`, and `devkit/armhf/pkgconfig/cairo-script.pc`: expand the build-time probe set for GIO, GIRepository, and Cairo/XCB support during Marco 2 / Marco 3 dependency matching.
- `etc/fonts/fonts.conf`: stores the system fontconfig baseline.
- `etc/ssl/certs/cacert.pem.system`: preserves the CA bundle reference used for HTTPS validation.
- `etc/systemd/journald.conf`, `etc/systemd/logind.conf`, `etc/systemd/oomd.conf`, `etc/systemd/sleep.conf`, `etc/systemd/resolved.conf`, `etc/systemd/pstore.conf`, `etc/systemd/timesyncd.conf`, `etc/systemd/system.conf`, and `etc/systemd/user.conf`: preserve the captured systemd service-manager defaults for the next edit pass.
- `etc/profile.d/001-functions`, `etc/profile.d/002-autostart`, `etc/profile.d/010-wlr-randr`, `etc/profile.d/045-xorg-server.conf`, `etc/profile.d/050-sway.conf`, `etc/profile.d/090-systemd.conf`, `etc/profile.d/095-zerotier.conf`, `etc/profile.d/098-box64.conf`, and `etc/profile.d/101-gpu-functions`: capture the main ROCKNIX shell/profile hooks, Wayland/Xorg helpers, and GPU/profile behavior that guide next-step compatibility work.


- `runtime-libs/armhf/`: ARM32 shared-library snapshots captured from the uploaded runtime set, kept for Marco 2 / Marco 3 compatibility and fallback comparison.
- `runtime-tools/armhf/gio-launch-desktop`: ARM32 helper executable snapshot kept for future desktop-entry and external-app launch comparison.

## Latest reference additions

This backup was expanded with three new reference bundles from the latest upload pass:

- `etc/tmpfiles.d/` now includes the full tmpfiles snapshot, including `README` and the additional ROCKNIX cleanup/provision rules.
- `devkit/armhf/pkgconfig/` now includes the newer pkg-config snapshot, covering Cairo, GLib/GIO, Wayland, EGL/GBM, Pango, PipeWire, JSON, and related dependency probes.
- `runtime-libs/armhf/lib32-snapshot/` now carries the extracted ARM32 library snapshot from `lib32.zip` for ABI and runtime comparison.

These files are reference-only and are kept so the next Fire4Nix pass can probe the real ROCKNIX environment without needing to reassemble the inputs.
