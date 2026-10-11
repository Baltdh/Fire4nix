# Build no ROCKNIX

1. Copie a pasta do projeto.
2. Execute:
   ```sh
   chmod +x build_fire4nix.sh rebuild_fire4nix.sh Install-Fire4Nix.sh
   ./rebuild_fire4nix.sh
   ```
3. Envie o arquivo `.build/logs/build.log` para análise.
4. Se estiver testando a instalação, rode `./Install-Fire4Nix.sh` na pasta do projeto.
5. Consulte `ROCKNIX_BOOT_NOTES.md` antes de tocar em `extlinux.conf` ou `boot.scr`.

Nota do beta: após a instalação, rode `browser_manager.sh beta-check` para confirmar Wayland, runtime e binário ARM64.


Updated: Added automatic engine detection and launch dispatch for Cog/WPE WebKit, Firefox and Chromium on ROCKNIX.

Note: `rocknix_reference/runtime-libs/aarch64/` stores captured ARM64 libraries from the uploaded runtime set for later dependency matching and fallback diagnostics, and `rocknix_reference/runtime-libs/armhf/` plus `rocknix_reference/runtime-tools/armhf/` keep the newly uploaded ARM32 reference snapshots for future helper and compatibility checks.


## Direct launch

After copying the folder to ROCKNIX, you can open `Fire4Nix.sh` directly from the file manager to start the browser without running the installer first.
