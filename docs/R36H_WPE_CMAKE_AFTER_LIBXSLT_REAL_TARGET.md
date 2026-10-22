# Fire4Nix — diagnóstico CMake WPE 2.54.1 após libxslt 1.1.43

## Causa comprovada

Após incorporar WebP 1.6.0 e seus componentes demux/mux,
a execução [39698520506](https://github.com/Baltdh/Fire4nix/actions/runs/39698520506)
confirmou `WEBP_FIRST_BLOCKER_CLEARED=YES`, mas o WPE permaneceu
sem configuração completa:

```
Could NOT find LibXslt (missing: LIBXSLT_LIBRARIES LIBXSLT_INCLUDE_DIR)
(Required is at least version "1.1.13")
Source/cmake/OptionsWPE.cmake:299
WPE_CMAKE_EXIT_CODE=1
```

## Dependência já existente e reutilizada

A [PR #71](https://github.com/Baltdh/Fire4nix/pull/71) compilou
**libxslt 1.1.43** (dependendo de libxml2 2.14.4 ARM64) com o GCC
ROCKNIX do RK3326. A execução
[39683799673](https://github.com/Baltdh/Fire4nix/actions/runs/39683799673)
foi aprovada: `LIBXSLT_BUILD=PASS_REAL_ROCKNIX_AARCH64`,
arquitetura ELF64/AArch64, `DT_NEEDED=libxml2.so.16`,
pkg-config versão 1.1.43 e GLIBC até 2.41.

O stage `libxslt-target/stage/usr/lib` e seus cabeçalhos são copiados
**somente** da execução anterior, como última fonte validada de
`scripts/assemble-wpe-post-harfbuzz-stage.py`.
A checagem do stage impede colisões divergentes, links externos e
SO de arquitetura errada.

A workflow `.github/workflows/r36h-wpe2541-post-harfbuzz-configure.yml`
define `LIBXSLT_LIBRARY=<stage>/usr/lib/libxslt.so.1` e
`LIBXSLT_INCLUDE_DIR=<stage>/usr/include`, permitindo que o
`FindLibXslt.cmake` do CMake reconheça headers `libxslt/xslt.h`
e a biblioteca de destino. `pkg-config --exists 'libxslt >= 1.1.13'`
é exigido.

## Aceitação

O novo teste deve apresentar simultaneamente:

- `SOUP3_FIRST_BLOCKER_CLEARED=YES`
- `XKBCOMMON_FIRST_BLOCKER_CLEARED=YES`
- `WEBP_FIRST_BLOCKER_CLEARED=YES`
- `LIBXSLT_FIRST_BLOCKER_CLEARED=YES`

Uma falha de `FindLibXslt` é fatal para o teste. Outras falhas CMake
são preservadas com as mensagens originais, **sem serem classificadas
como navegador compilado**.

Apenas a configuração do código-fonte WPE 2.54.1 é tentada neste
estágio. Sem execução de binários target, sem instalação no console,
sem validação física de Mali/Wayland/HTTPS e sem modificação em
firmware, cartão SD ou `/usr/lib`.
