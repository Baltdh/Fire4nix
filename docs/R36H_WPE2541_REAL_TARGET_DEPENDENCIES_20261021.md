# Fire4Nix — WebKit WPE 2.54.1: preparação para compilação integral (21/10/2026)

## Evidência real de target ROCKNIX RK3326

O SDK `aarch64-rocknix-linux-gnu` da revisão oficial `3b9cb1f6bf48ee9ca0cf01edd9af52ca2a6b73fb` foi restaurado em CI. As seguintes compilações (ELF AArch64 / GLIBC <= 2.41, **não executadas no aparelho**) passaram:

| Etapa | Prova no GitHub Actions | Escopo |
|---|---|---|
| Seis libs básicas | [39679782372](https://github.com/Baltdh/Fire4nix/actions/runs/39679782372) | zlib, SQLite, libtasn1, libpng, libffi e PCRE2 (dois comprimentos) |
| GLib 2.85.1 | [39680591647](https://github.com/Baltdh/Fire4nix/actions/runs/39680591647) | glib, gobject, gio, gmodule |
| Sete libs integradas | [39682062894](https://github.com/Baltdh/Fire4nix/actions/runs/39682062894) | estágio privado, consumidor C vinculado com `-z defs` |
| libxml2 2.14.4 | [39683023507](https://github.com/Baltdh/Fire4nix/actions/runs/39683023507) | fonte SHA256 da receita oficial, SONAME `libxml2.so.16`, consumidor XML |
| libxslt 1.1.43 | [39683799673](https://github.com/Baltdh/Fire4nix/actions/runs/39683799673) | XSLT ligado ao libxml2-alvo via `libxml2-config.cmake` de estágio privado |

Os artefatos dos workflows expiram; versões, receitas, hashes, instruções e logs de auditoria permanecem no GitHub. Estas bibliotecas NÃO devem ser copiadas isoladamente a `/usr/lib` no R36H.

## Verificação da lista real de dependências WebKit upstream

`Source/cmake/OptionsWPE.cmake` da tag **wpewebkit-2.54.1** exige na configuração mínima:

- `GLib >= 2.70`, com **GioUnix**, Thread e Module — versão 2.85.1 real já compilada. GioUnix também deve ser verificado no estágio combinado;
- `HarfBuzz >= 2.7.4` com **COMPONENTS ICU** — **bloqueio descoberto**: a receita ROCKNIX 20260801 de `harfbuzz 11.2.1` define `-Dicu=disabled`; isto NÃO satisfaz `find_package(HarfBuzz ... COMPONENTS ICU)`. Deve-se compilar ICU target e HarfBuzz com `-Dicu=enabled` sem perder a identidade do release;
- `ICU >= 70.1`, partes data/i18n/uc; ainda não validada em estágio do Fire4Nix;
- JPEG, Epoxy >= 1.5.4, LibGcrypt >= 1.7.0, Soup3 >= 3.0.0, Tasn1, XkbCommon >= 0.4, libxml2 >= 2.9.13, PNG, SQLite3, WebP com **demux**, ZLIB, FreeType >= 2.9;
- `libxslt >= 1.1.13` somente com `ENABLE_XSLT=ON`. O estágio atual permite preservar XSLT no navegador;
- para Wayland, `Wayland >= 1.20` e `WaylandProtocols >= 1.24`.
- `ENABLE_WPE_PLATFORM=ON`, `ENABLE_WPE_PLATFORM_WAYLAND=ON` e `ENABLE_WPE_LEGACY_API=OFF`; GStreamer, vídeo e WebAudio OFF nesta primeira versão.

**Não confundir presença de receitas `package.mk` com bibliotecas compiladas, headers e `.pc` corretos no sysroot.** É preciso gerar estágio unificado de desenvolvimento para WPE e testar configure CMake real, sem bibliotecas Ubuntu host.

## Próximas ações de desenvolvimento em ordem

1. Integrar `libxml2` e `libxslt` aos artefatos das sete bibliotecas com teste de colisões e `DT_NEEDED`; separar caminhos de build-host e target, preservar symlinks e arquivos CMake/pkg-config.
2. Compilar as dependências críticas restantes, principalmente **ICU + HarfBuzz com ICU ON**, FreeType/Fontconfig, LibGcrypt, libepoxy, Wayland, libxkbcommon, libwebp demux, Soup3 e GLib TLS.
3. Rodar `build-wpe-2.54.1.sh --configure` exclusivamente com SDK ROCKNIX real; validar `CMakeCache.txt` e ausência de GStreamer.
4. Compilar motor **WebKit e subprocessos**, auditar ELF/GLIBC/SONAME/recursos e apenas então empacotar na partição ext4 interna para primeiro teste HTML offline 640x480, com rollback.
5. Testar HTTPS real, controles A/Enter, estabilidade e desempenho; não tocar no SD externo exFAT problemático nem em `/usr/lib`.

**Estado:** libxslt e libxml2 compilados para o target; WebKit completo e navegador para R36H ainda não compilados nem testados.
