# WPE 2.54.1: HarfBuzz 11.2.1 ARM64 do ROCKNIX compilado com Cairo/FreeType/GLib

**CI real:** [GitHub Actions 39689665850 — SUCCESS](https://github.com/Baltdh/Fire4nix/actions/runs/39689665850), 21/10/2026.

## Razão técnica e fonte

O [primeiro configure real do WPE no SDK ROCKNIX](https://github.com/Baltdh/Fire4nix/actions/runs/39684582460) falhou em `Source/cmake/FindHarfBuzz.cmake:94` por falta da biblioteca alvo e versão requerida >=2.7.4. A receita ROCKNIX 20260801 `packages/graphics/harfbuzz/package.mk` exige:

- **HarfBuzz 11.2.1**.
- Tarball original `harfbuzz-11.2.1.tar.xz` e SHA-256 `093714c8548a285094685f0bdc999e202d666b59eeb3df2ff921ab68b8336a49`.
- Dependências alvo Cairo, FreeType e GLib.
- Flags Meson Cairo/FreeType/GLib enabled e GObject/ICU/Graphite/tests/docs disabled.

O código usa o **mesmo GCC ROCKNIX RK3326/AArch64** do checkpoint [39525819979](https://github.com/Baltdh/Fire4nix/actions/runs/39525819979), não o GCC Ubuntu. Combina em um único estágio isolado e com checagem de colisões:

- Fontconfig 2.17.1 e suas dependências gráficas da [execução 39687860420](https://github.com/Baltdh/Fire4nix/actions/runs/39687860420).
- Cairo 1.17.8 com FreeType/Pixman/PNG compilado no [run 39688962028](https://github.com/Baltdh/Fire4nix/actions/runs/39688962028).

## Provas verificadas

```text
HARFBUZZ_PREREQUISITE_STAGE=PASS_COLLISION_SAFE
TARGET_PC_cairo=1.17.8
TARGET_PC_glib-2.0=2.85.1
TARGET_PC_fontconfig=2.17.1
TARGET_PC_pixman-1=0.46.2
TARGET_PC_libpng16=1.6.40
HARFBUZZ_GLIBC=PASS_MAX_2_41
HARFBUZZ_VERSION=11.2.1_ROCKNIX
HARFBUZZ_TARGET_BUILD=PASS_REAL_ROCKNIX_AARCH64
HARFBUZZ_CAIRO_FREETYPE_GLIB_CONFIGURED=YES
HARFBUZZ_TARGET_CONSUMER_LINK=PASS_ELF64_AARCH64
HARFBUZZ_TARGET_GLIBC_MAX=2.41
TARGET_EXECUTED=no
R36H_INSTALLABLE=no
```

O CI compilou `libharfbuzz.so.0`, metadados de desenvolvimento `harfbuzz.pc`, arquivos header e consumidor C++ compartilhado que usa as operações `hb_buffer_*` e `hb_shape`, confirmado ELF64/AArch64 e `DT_NEEDED=libharfbuzz.so.0`. **Os binários ARM64 foram vinculados, mas não executados**.

[Artefato temporário do estágio HarfBuzz AArch64 — expira em 04/11/2026](https://github.com/Baltdh/Fire4nix/actions/runs/39689665850/artifacts/12388536310).

## Limites

O Cairo do estágio foi compilado para teste com camada `cairo-gobject` e Xlib/XCB desativadas; isto **não comprova** ainda equivalência completa ao firmware Wayland. HarfBuzz segue a receita de compilação **sem ICU**, embora outro agente esteja testando ICU 74.1 em paralelo. O build não altera `/usr/lib`, firmware ou SD do console e não comprova renderização gráfica, TLS/HTTPS, GPU Mali ou subprocessos WPE.

## Próximo teste

Reexecutar o CMake do WebKit 2.54.1 no SDK AArch64 real com os arquivos HarfBuzz agora adicionados e `USE_GSTREAMER=OFF`. Somente o resultado desse próximo `find_package(HarfBuzz)` determinará se o bloqueio anterior foi efetivamente removido e qual a próxima dependência obrigatória a construir.
