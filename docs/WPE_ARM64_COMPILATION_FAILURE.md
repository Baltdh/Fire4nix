# WPE build compatibility finding — 2026-10-13

## Reproduced in GitHub Actions

- Static job passed: https://github.com/Baltdh/Fire4nix/actions/runs/38347923762
- ARM64 C++ compile failed: same run, job `wpe-build`.
- The recovered WPE ARM64 library was found, installed and its pkg-config metadata was available; the failure occurred **during C++ compilation**, not while downloading the engine.

## Specific compiler errors

`src/wpe/wpe_platform_launcher.cpp` calls APIs unavailable in the recovered library headers:
- `webkit_website_data_manager_new_ephemeral`
- `webkit_website_data_manager_new`
- `webkit_website_data_manager_set_itp_enabled`
- `webkit_website_data_manager_set_network_proxy_settings`
- `webkit_website_data_manager_set_tls_errors_policy`
- `webkit_web_context_get_cookie_manager`
- `webkit_web_context_is_ephemeral`
- `webkit_web_view_new_with_context`

These are not fixed by changing the shell launcher or linking flags. The C++ launcher must be adapted to the selected WPE WebKit API generation or built against an older matching WPE library.

## Working evidence to reuse

The earlier experimental integration workflow succeeded:
https://github.com/Baltdh/Fire4nix/actions/runs/38214215725

Its workflow `.github/workflows/fire4nix-wpe-integration.yml` in branch `codex/fire4nix-preparation` invokes `Fire4Nix/scripts/build_wpe_arm64.sh` and archives a matched launcher/runtime. Compare that source and build script before changing the new launcher API. A passing old workflow does **not** prove the reorganized launcher compiles.

## Next gates

1. Inspect header/API version from the actual ARM64 library and decide on an explicit target.
2. Adapt `wpe_platform_launcher.cpp` to that API and preserve private browsing/cookies/proxy where supported.
3. Require successful ARM64 compilation and `readelf` dependency inspection.
4. Audit bundled dependencies against the exact ROCKNIX RK3326 image.
5. Only then publish a device-test candidate, without calling it device-validated.
