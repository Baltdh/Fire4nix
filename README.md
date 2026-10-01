# Fire4Nix

Fire4Nix e um navegador controller-first para handhelds RK3326 rodando
ROCKNIX, com foco no R36H/R36S em 640x480, Wayland/Sway e baixo consumo de
recursos.

## Estado atual

A branch ativa e `codex/fire4nix-preparation`. O snapshot atual e
**0.84-beta-rocknix-wpe-runtime**.

Ja estao implementados nesta linha:

- selecao automatica de engine com WPEPlatform como caminho preferencial;
- fallback Cog/Chromium/Firefox sem desativar sandbox para facilitar o launch;
- bridge de navegacao e estado entre a UI e o engine;
- launcher WPE com URL, cookies, proxy, ITP, filtro de conteudo e recuperacao
  de Web Process;
- superficie WPEPlatform configurada para o alvo 640x480 com
  maximize/fullscreen;
- smoke report para ROCKNIX/RK3326;
- cross-build aarch64 baseado em sysroot ROCKNIX;
- empacotador One File com gate que exige um ELF ARM64 real;
- launcher portatil que recupera permissoes perdidas ao extrair ZIP;
- CI para os contratos de GUI, IPC, renderer, WPE windowing e scripts.

## Bloqueio para a versao instalavel

O arquivo atualmente versionado em `bin/fire4nix-wpe-platform` ainda e um
launcher de compatibilidade. A One File Edition final so sera produzida depois
que ele for substituido por um ELF ARM64 WPE real, o runtime WPE autocontido
for montado em `runtime/aarch64/` e todo o conjunto for aprovado no R36H.

Para compilar/testar:

```sh
cd Fire4Nix
make AUDIT_MODE=1 BUILD_MODE=SDL_ONLY
make test-gui
make test-bridge
make test-ipc
make test-renderer
```

Para o caminho ARM64 e o pacote final, veja
[`Fire4Nix/BUILD_ON_ROCKNIX.md`](Fire4Nix/BUILD_ON_ROCKNIX.md) e
[`docs/WPE_RK3326_2026.md`](docs/WPE_RK3326_2026.md) e
[`docs/WPE_PORTABLE_RUNTIME.md`](docs/WPE_PORTABLE_RUNTIME.md).
