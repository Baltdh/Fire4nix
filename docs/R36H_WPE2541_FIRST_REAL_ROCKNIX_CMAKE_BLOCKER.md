# Fire4Nix — primeiro bloqueio REAL da configuração do WPE WebKit 2.54.1 com ROCKNIX

**Data:** 21/10/2026  
**Fonte do diagnóstico:** [GitHub Actions 39684582460 — SUCCESS como execução do diagnóstico](https://github.com/Baltdh/Fire4nix/actions/runs/39684582460). **O CMake do WebKit NÃO passou**: exit code 1.

## O que foi testado

- WPE WebKit 2.54.1 oficial, tarball com SHA-256 validado `0de8bdfba011f9cd63ba9a9171fa6038dd2c08237894f4082abbb821f29d3fe9`.
- Toolchain real do ROCKNIX RK3326/AArch64, commit `3b9cb1f6bf48ee9ca0cf01edd9af52ca2a6b73fb`, libc alvo 2.41, [build do GCC 39525819979](https://github.com/Baltdh/Fire4nix/actions/runs/39525819979).
- Estágio de dependências genuínas [39683307528](https://github.com/Baltdh/Fire4nix/actions/runs/39683307528) com GLib/GIO 2.85.1, libjpeg-turbo 3.0.1, libpng 1.6.40, SQLite 3.50.2 e outras bibliotecas alvo.
- CMake em modo configuração apenas: `PORT=WPE`, `USE_GSTREAMER=OFF`, `USE_GSTREAMER_GL=OFF`, mídia e funcionalidades opcionais desativadas. O arquivo de toolchain estende o sysroot original somente com um estágio privado; o host Ubuntu não fornece bibliotecas alvo.
- Nenhuma execução de ELF AArch64, compilação completa do WebKit, instalação em firmware, cartão SD ou `/usr/lib`.

## Resultado exato do primeiro bloqueio

```text
ROCKNIX_REAL_SDK_AARCH64=PASS
TARGET_PC_glib-2.0=2.85.1
TARGET_PC_gio-2.0=2.85.1
TARGET_PC_gobject-2.0=2.85.1
TARGET_PC_libjpeg=3.0.1
TARGET_PC_libpng16=1.6.40
TARGET_PC_sqlite3=3.50.2
WPE_SOURCE_SHA256=PASS_OFFICIAL_2_54_1
WPE_CMAKE_EXIT_CODE=1
WPE_TARGET_CONFIGURE=BLOCKED_WITH_REAL_SDK
WPE_WEBKIT_BUILT=no
```

A configuração interrompeu em `Source/cmake/FindHarfBuzz.cmake:94`:

```text
CMake Error at Source/cmake/FindHarfBuzz.cmake:94 (message):
  Required version (2.7.4) is higher than found version ()
Call Stack (most recent call first):
  Source/cmake/OptionsWPE.cmake:13 (find_package)
  Source/cmake/WebKitCommon.cmake:331 (include)
  CMakeLists.txt:22 (include)
```

**Interpretação:** HarfBuzz compatível com o target **não está disponível ou não foi identificado** pelo CMake/pacote de desenvolvimento no estágio atual. Como a versão encontrada está vazia, não se deve diagnosticar especificamente uma versão antiga sem antes inspecionar o `harfbuzz.pc` e as bibliotecas alvo. Um workflow diagnosticado como `SUCCESS` significa apenas que preservou e classificou o bloqueio; **não** que WPE ficou configurado.

## Como resolver respeitando a receita efetiva do ROCKNIX

A árvore ROCKNIX 20260801 inclui `packages/graphics/harfbuzz/package.mk` com versão **11.2.1**, SHA-256 do tarball **`093714c8548a285094685f0bdc999e202d666b59eeb3df2ff921ab68b8336a49`** e dependências **Cairo, FreeType e GLib**. Suas flags de destino habilitam Cairo, FreeType e GLib e desabilitam ICU/Graphite/docs/tests; o objetivo é manter esse perfil, não contornar o erro inserindo bibliotecas x86 ou cabeçalhos genéricos Ubuntu.

A receita de FreeType fixa versão **2.13.3**, SHA-256 **`0550350666d427c74daeb85d5ac7bb353acba5f76956395995311a9c6f063289`**, e usa zlib e libpng, já compiladas para ARM64 em passos anteriores.

**Próximo conjunto técnico:** construir FreeType 2.13.3 contra libpng/zlib reais; resolver Cairo e sua cadeia de bibliotecas; então compilar HarfBuzz 11.2.1 com o GCC ROCKNIX e verificar `harfbuzz.pc`, SONAME, requisitos GLIBC e vinculação de consumidor AArch64. Reexecutar a configuração CMake do WPE no mesmo sysroot para descobrir o próximo bloqueio. Só então considerar qualquer etapa de build integral.

## Evidências reproduzíveis

- Arquivos: `.github/workflows/r36h-real-rocknix-wpe-cmake-probe.yml` e `scripts/probe-wpe-rocknix-target-configure.sh`.
- [GitHub Actions 39684582460](https://github.com/Baltdh/Fire4nix/actions/runs/39684582460).
- [Artefato de relatórios CMake e CMakeCache — temporário](https://github.com/Baltdh/Fire4nix/actions/runs/39684582460/artifacts/12386060531).
- O status do workflow e o status do CMake são reportados **separadamente**.

**Estado:** oito componentes de estágio não equivalem ao navegador. A renderização gráfica no R36H, Wayland/Mali e HTTPS continuam não validados.
