# Fire4Nix — auditoria do sysroot ROCKNIX real (21/10/2026)

## Evidência técnica, não uma simulação

**Fonte do compilador:** GitHub Actions [39525819979](https://github.com/Baltdh/Fire4nix/actions/runs/39525819979), branch `fix/rocknix-xmlstarlet-source-verified-20261020`, artefato `ROCKNIX-RK3326-toolchain-HOST-ONLY` (ID 12315721316). O bootstrap do upstream ROCKNIX 20260801 compilou GCC 15.2.0, validou C/C++ AArch64 e registrou GLIBC 2.41.

**Auditoria deste branch:** [39538526075](https://github.com/Baltdh/Fire4nix/actions/runs/39538526075), que usa `actions/download-artifact@v4` para reutilizar exatamente o arquivo do build. O conteúdo é extraído apenas num runner Linux descartável. O script de inspeção não executa os ELFs-alvo, não substitui bibliotecas de sistema e não altera cartões SD.

### Resultados efetivamente observados

- Arquivo `tar.xz` do toolchain: **14.610 entradas** verificadas na inspeção de nomes.
- `check-rocknix-sdk.sh --check`: `SDK_PREFLIGHT=PASS`, `arch=AArch64`, `release=20260801`, `target_glibc=2.41`.
- `audit-wpe-sysroot-pkgconfig.sh --inspect`: `TARGET_PC_TOTAL=22`, `TARGET_PC_MISSING_COUNT=22`, `SYSROOT_PC_AUDIT=INCOMPLETE_TARGET_SDK`.
- Todos os 22 requisitos de metadados `.pc` falharam ao serem procurados **somente dentro do sysroot** do artefato. Isso não é prova independente de ausência física de todas as bibliotecas e headers, mas **impede autorizar** uma compilação WPE com base nesses metadados.
- O arquivo CMake do toolchain contém caminhos do runner que o construiu. **Não foi validado o reaproveitamento/relocação do compilador em outro runner**; os comandos de auditoria são leitura estática do sysroot.

### Dependências de desenvolvimento ainda não atendidas

`glib-2.0`, `gio-2.0`, `harfbuzz`, `harfbuzz-icu`, `icu-uc`, `icu-i18n`, `libjpeg`, `epoxy`, `libgcrypt`, `libsoup-3.0`, `libtasn1`, `xkbcommon`, `libxml-2.0`, `libpng`, `sqlite3`, `libwebp`, `libwebpdemux`, `zlib`, `freetype2`, `libxslt`, `wayland-client`, `wayland-protocols`.

No checkout do upstream ROCKNIX fixado no commit `3b9cb1f6bf48ee9ca0cf01edd9af52ca2a6b73fb`, existem receitas em `packages/devel/glib`, `packages/graphics/harfbuzz`, `packages/graphics/libepoxy`, `packages/graphics/libjpeg-turbo`, `packages/compress/zlib`, `packages/databases/sqlite`, `packages/wayland/wayland` e `packages/wayland/wayland-protocols`, entre outras. **Existir a receita não significa que a dependência-alvo já tenha sido compilada ou instalada no sysroot.**

`libsoup3` e `libtasn1` precisam das receitas extras já propostas na PR #38; suas integrações ainda exigem build e conferência no toolchain real. A auditoria de 22 metadados é um portão inicial, não substitui CMake, `readelf`, testes de link e execução no console.

## Próximo portão para uma compilação WPE verdadeira

1. Trazer as correções de fontes da PR #50 à base do toolchain da PR #40, respeitando a integração concorrente com PR #49.
2. Compilar as dependências de desenvolvimento e de runtime do **alvo ROCKNIX AArch64** com o próprio toolchain, preferencialmente no mesmo workspace em que ele é construído; não usar `.pc` nem `.so` do Ubuntu como substitutos.
3. Reexecutar `--pc-ready` no sysroot populado, seguido por CMake configure real, auditoria ABI/GLIBC e `DT_NEEDED` de toda a cadeia WPE.
4. Compilar o WPE WebKit 2.54.1 com `USE_GSTREAMER=OFF`, gerar `libWPEWebKit-2.0.so.1` e os processos WPE, stage em pasta privada e validar offline no R36H (Wayland/Mali, HTML, JavaScript, gamepad).

**Critério de conclusão:** esta etapa só prova prontidão básica do compilador e ausência atual de metadados WPE no snapshot; navegador final no R36H continua **NÃO VALIDADO**. Não instalar o arquivo HOST-ONLY no console.

## Segurança adicional do auditor

A auditoria deve rejeitar diretórios `pkgconfig` que sejam links simbólicos para fora do sysroot. Teste de regressão adiciona um diretório de `.pc` externo simulado e exige `BLOCKED_HOST_PKGCONFIG_SYMLINK`, impedindo que metadados do host pareçam dependências do ROCKNIX.
