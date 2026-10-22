# Fire4Nix — CMake real WPE 2.54.1 após XkbCommon/Wayland AArch64

## Ponto de partida verificado

O diagnóstico precedente com Soup3 real
[39696548285](https://github.com/Baltdh/Fire4nix/actions/runs/39696548285)
retornou `WPE_CMAKE_EXIT_CODE=1` com o primeiro erro novo:

`Could NOT find XkbCommon (missing: XkbCommon_VERSION)`

Esse é um bloqueio **de metadados de desenvolvimento alvo**, não evidência
de que o XKB do console esteja danificado. A etapa de compilação independente
[39697406436](https://github.com/Baltdh/Fire4nix/actions/runs/39697406436)
já produziu **libxkbcommon 1.6.0** e **libxkbregistry 1.6.0** ARM64 com
`xkbcommon.pc`, `xkbregistry.pc` e Wayland 1.23.1 aprovados em CI.
A fonte XkbCommon está autenticada por SHA256 e MD5 do manifesto Debian
e corresponde ao override **efetivo** do ROCKNIX.

## Prova objetiva pretendida

Este workflow NÃO modifica o upstream WebKit. Continua usando:

- Source WPE WebKit 2.54.1 oficial, SHA256
  `0de8bdfba011f9cd63ba9a9171fa6038dd2c08237894f4082abbb821f29d3fe9`.
- SDK ROCKNIX 20260801 e GCC `aarch64-rocknix-linux-gnu`
  da execução [39525819979](https://github.com/Baltdh/Fire4nix/actions/runs/39525819979);
  GLIBC 2.41 como limite de destino.
- Stages versionados e testados de Cairo/Fontconfig/ICU,
  HarfBuzz+ICU, libglvnd/EGL/libepoxy, LibGcrypt/LibGpgError,
  nghttp2/libpsl/Soup3 e XkbCommon/Wayland.
- Cache CMake de perfil mínimo WPE **GStreamer desligado**
  (`USE_GSTREAMER=OFF`, áudio/vídeo desativados).

O script `scripts/assemble-wpe-post-harfbuzz-stage.py` faz merge
somente do `usr/lib` e `usr/include`, rejeita colisões não idênticas
e links que escapem e valida ELF64 AArch64 dos SONAMEs reais, incluindo
`libxkbcommon.so.0`, `libxkbregistry.so.0` e
`libwayland-client.so.0`.

O `scripts/probe-wpe-post-harfbuzz-target-configure.sh` passa a ler
os pacotes `xkbcommon`, `xkbregistry` e `wayland-client` do
`PKG_CONFIG_LIBDIR` privado, no mesmo CMake que antes falhava no
`FindXkbCommon.cmake` upstream:

```cmake
pkg_check_modules(XkbCommon QUIET IMPORTED_TARGET "xkbcommon>=${XkbCommon_FIND_VERSION}")
find_package_handle_standard_args(XkbCommon REQUIRED_VARS XkbCommon_VERSION)
```

Se o resultado ainda contiver `Could NOT find XkbCommon` ou
`XkbCommon_VERSION`, o workflow **falha** com
`XKBCOMMON_FIRST_BLOCKER_CLEARED=NO`.
Se não contiver o erro e os `.pc` ARM64 foram resolvidos, registra
`XKBCOMMON_FIRST_BLOCKER_CLEARED=YES`, mesmo que o CMake continue
bloqueado por outra dependência.

## Critérios e limitações

O resultado aprovado demonstra **eliminação do bloqueio anterior**,
não necessariamente `WPE_CMAKE_EXIT_CODE=0`. O primeiro bloqueio
subsequente é capturado com nome e mensagem exatos, mantendo log e
`CMakeCache.txt` para reutilização posterior.

A runtime closure completa, TLS/GIO, fontes de teclado, carregamento
GPU Mali, WebKit/JSC compilado e renderização física no R36H continuam
sem confirmação. Não instalar estágio de desenvolvimento no firmware
ou em `/usr/lib`.

**Revisar `WPE_TARGET_CONFIGURE`, `WPE_CMAKE_EXIT_CODE` e a primeira
mensagem `CMake Error` antes de afirmar que o motor foi compilado.**
