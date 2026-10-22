# Fire4Nix — opção de desenvolvimento WPE Wayland sem DRM/GBM

## Por que testar esta alternativa

O [diagnóstico real 39698959140](https://github.com/Baltdh/Fire4nix/actions/runs/39698959140)
validou o estágio AArch64 com LibXslt 1.1.43 e registrou:
`LIBXSLT_FIRST_BLOCKER_CLEARED=YES`, mas o WPE 2.54.1 ainda
não completou CMake.

A primeira falha nova é:

```text
-- Could NOT find LibDRM (missing: LibDRM_INCLUDE_DIR LibDRM_LIBRARY)
CMake Error at Source/cmake/OptionsWPE.cmake:452:
  libdrm is required for USE_LIBDRM
WPE_CMAKE_EXIT_CODE=1
```

No código-fonte oficial
[WPE 2.54.1 OptionsWPE.cmake](https://github.com/WebKit/WebKit/blob/wpewebkit-2.54.1/Source/cmake/OptionsWPE.cmake),
`USE_LIBDRM` e `USE_GBM` são opções **públicas** habilitadas por
padrão, mas o CMake só chama `find_package(LibDRM)` dentro de
`if (USE_LIBDRM)`. O backend DRM também depende de GBM; não é o
mesmo backend de WPEPlatform Wayland.

Este teste experimental coloca `ENABLE_WPE_PLATFORM_DRM=OFF`,
`USE_LIBDRM=OFF`, `USE_GBM=OFF` e
`ENABLE_GPU_PROCESS=OFF`, preservando
`ENABLE_WPE_PLATFORM_WAYLAND=ON` e
`ENABLE_WPE_PLATFORM_HEADLESS=ON` em um **perfil mínimo** voltado
a descobrir o caminho de configuração da primeira página HTML.

## Critério verificável

O script exige quatro linhas no `CMakeCache.txt`:

- `USE_LIBDRM:BOOL=OFF`
- `USE_GBM:BOOL=OFF`
- `ENABLE_GPU_PROCESS:BOOL=OFF`
- `ENABLE_WPE_PLATFORM_DRM:BOOL=OFF`

Se algum cache não respeitar o valor ou o CMake continuar exigindo
LibDRM, o teste **falha**; somente a configuração realmente aceita
registra `WPE_REDUCED_WAYLAND_NO_DRM_GBM=PASS_CMAKE_CACHE_GATED`.

Todas as verificações de origem ROCKNIX genuína, stages AArch64,
HarfBuzz ICU, LibGcrypt, Soup3, XkbCommon, WebP e LibXslt
continuam em vigor.

## Escopo e limitações

O perfil **não substitui** o caminho gráfico acelerado que pode precisar
de DRM/GBM para recursos WebGL, compartilhamento de buffers ou GPU
process. Não comprova performance, renderização, eventos de entrada,
HTTPS, funcionamento em Sway ou binário executável no R36H.

Mesmo com workflow verde, se `WPE_CMAKE_EXIT_CODE=1`, o resultado é
**apenas o próximo bloqueio de configuração**. O perfil DRM/GBM
completo deve ser mantido como alternativa futura; não desinstalar
componentes do sistema e não usar este experimento para modificar
`/usr/lib` ou firmware do console.
