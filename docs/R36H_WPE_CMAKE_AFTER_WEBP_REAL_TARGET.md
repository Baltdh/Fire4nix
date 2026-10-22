# Fire4Nix — diagnóstico WPE 2.54.1 após WebP 1.6.0 real

## Resultado anterior

O [workflow de diagnóstico WPE 39697964367](https://github.com/Baltdh/Fire4nix/actions/runs/39697964367)
confirmou o desaparecimento do erro `FindXkbCommon.cmake` depois
de incorporar libxkbcommon 1.6.0 ARM64 do
[build 39697406436](https://github.com/Baltdh/Fire4nix/actions/runs/39697406436).
O primeiro bloqueio novo ficou registrado assim:

```
Could NOT find WebP (missing: WebP_INCLUDE_DIR WebP_LIBRARY
_WebP_REQUIRED_LIBS_FOUND)
Source/cmake/FindWebP.cmake:158
Source/cmake/OptionsWPE.cmake:25
WPE_CMAKE_EXIT_CODE=1
```

Esse erro **não** comprova falta de libwebp no ROCKNIX físico;
apenas demonstra que o SDK privado usado para configurar WPE não
continha cabeçalhos e bibliotecas WebP de desenvolvimento.

## Fonte e artefato verificados

O build anterior [39683707451](https://github.com/Baltdh/Fire4nix/actions/runs/39683707451)
da [PR #69](https://github.com/Baltdh/Fire4nix/pull/69)
já compilou cinco bibliotecas compartilhadas WebP 1.6.0 com o GCC
ROCKNIX RK3326/AArch64, GLIBC <= 2.41, `$ORIGIN` auditado,
consumidor ligado a WebP/demux/mux/GLib/libpng:

- Fonte oficial: `libwebp-1.6.0.tar.gz`;
- SHA256 `e4ab7009bf0629fd11982d4c2aa83964cf244cffba7347ecd39019a9e38c4564`;
- Artefato imutável referenciado por run-id:
  `Fire4Nix-ROCKNIX-EIGHT-DEPS-WEBP-TEST-ONLY`,
  [Actions 39683707451](https://github.com/Baltdh/Fire4nix/actions/runs/39683707451).

A receita efetiva `projects/ROCKNIX/packages/graphics/libwebp/package.mk`
do checkout `3b9cb1f6bf48ee9ca0cf01edd9af52ca2a6b73fb`
fixa **1.6.0**. O artefato é reaproveitado sem baixar bibliotecas
da distribuição Ubuntu.

## Critérios de aceitação do CMake

A workflow `.github/workflows/r36h-wpe2541-post-harfbuzz-configure.yml`
incorpora `eight-rocknix-stage/usr/lib` e `usr/include` da PR #69
no mesmo stage AArch64 que contém Wayland, XkbCommon, Soup3, LibGcrypt,
HarfBuzz+ICU, Cairo e EGL/Epoxy.

As variáveis reais do FindWebP são preenchidas explicitamente:

```cmake
WebP_LIBRARY=<private-stage>/usr/lib/libwebp.so.7
WebP_DEMUX_LIBRARY=<private-stage>/usr/lib/libwebpdemux.so.2
WebP_MUX_LIBRARY=<private-stage>/usr/lib/libwebpmux.so.3
WebP_INCLUDE_DIR=<private-stage>/usr/include
```

Não são caminhos do dispositivo físico e não são bibliotecas de host.
O `FindWebP.cmake` oficial do WPE 2.54.1 também consulta
`libwebp.pc` para metadados e a presença de componentes `demux`/`mux`.

O diagnóstico retorna `WEBP_FIRST_BLOCKER_CLEARED=NO` e falha
se `Could NOT find WebP`, `_WebP_REQUIRED_LIBS_FOUND` ou
qualquer variável WebP obrigatória ainda estiver ausente.
Com todas as verificações atendidas, registra
`WEBP_FIRST_BLOCKER_CLEARED=YES`, preservando o primeiro erro
seguinte do CMake, se houver.

## Limites

Não executar código ARM64 no Ubuntu, nem modificar `/usr/lib`,
firmware ou SD. Mesmo um CI verde comprova apenas o avanço do
**configure do WebKit**, não renderização real no R36H, compilação
do motor, aceleração Mali ou TLS/HTTPS.
