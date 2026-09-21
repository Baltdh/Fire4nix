# Browser research and cleanup — 2026-09-21

## Official sources consulted

- Firefox process model: https://firefox-source-docs.mozilla.org/dom/ipc/process_model.html
- Firefox sandbox architecture: https://wiki.mozilla.org/Security/Sandbox/Process_model
- Chromium architecture: https://www.chromium.org/developers/design-documents/multi-process-architecture/
- Opera power-saving behavior: https://help.opera.com/en/latest/features/

Firefox and Chromium separate untrusted content from privileged browser work.
Opera documents reducing background-tab activity and rescheduling work for
battery savings. These are design references, not claims of compatibility or
measured improvements in Fire4Nix.

## Applied changes

- Stop forcing Firefox sandbox off in the wrapper, shipped profile, and policy
  templates. Leave sandbox levels to the installed engine's defaults.
- Enable Safe Browsing preferences in shipped and generated profiles.
- Refuse the Chromium root launch path instead of automatically disabling
  sandboxing. A non-root session is now required for this path.
- Do not kill PulseAudio, evict other sound-device clients, or force mixer
  volumes when constructing the Firefox environment.

These changes do not migrate existing installed profiles or sanitize inherited
environment overrides. An already-installed profile requires a separate,
backed-up migration. Audio/apulse compatibility and actual sandbox operation
must be verified on the target system. The remaining legacy audio settings
are not yet a fully redesigned ROCKNIX audio integration.

## Cleanup

Removed three old root ZIPs from the active branch:

- Fire4Nix_consolidated_latest_real_backup_gui_wpe_bridge_v2.zip
- Fire4Nix_consolidated_latest_real_backup_project_audit_v5.zip
- Fire4Nix_consolidated_latest_real_backup_wpe_integration_cleaned.zip

They are historical snapshots, not build inputs; unique old content remains
recoverable at commit 93085fe77bbf83cbf15c7e843b1f1ee15d5d59e1. The
with_launcher ZIP is retained because it contains reference snapshots excluded
from the editable tree. Removing these files does not shrink Git history.
No source modules were deleted merely because they are not wired up yet.

## Next GUI milestone

Keep address, navigation, loading/error state and page content distinct. Connect
the modular GUI to one event owner and a real renderer before claiming visual
completion. Target 640x480 and controller focus; avoid a desktop-style sidebar.
Plan optional background-tab suspension rather than weakening engine security.
These interface and performance items are planned, not implemented here.

## Validation

Run `python3 -m unittest discover -s tests -p 'test_*.py'`, `make test-gui`,
and the host audit build. Static security tests do not prove runtime sandbox
effectiveness. No screenshot or device validation is claimed.
