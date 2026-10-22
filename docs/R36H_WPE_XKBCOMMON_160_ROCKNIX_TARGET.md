# Fire4Nix: libxkbcommon 1.6.0 e libxkbregistry ARM64 para ROCKNIX/WPE

## Bloqueio observado no WPE

O diagnóstico real do WPE WebKit 2.54.1,
[Actions 39696548285](https://github.com/Baltdh/Fire4nix/actions/runs/39696548285),
já detecta LibGcrypt, HarfBuzz+ICU, libepoxy/EGL e Soup3. Sua configuração
**ainda falha**, com `WPE_CMAKE_EXIT_CODE=1` e
`Could NOT find XkbCommon (missing: XkbCommon_VERSION)`.
O próximo passo não é modificar o código do WebKit, e sim preparar os
metadados de desenvolvimento e a biblioteca AArch64 esperados.

## Versão efetiva e prova de fonte

A receita base de
`packages/wayland/libxkbcommon/package.mk` do ROCKNIX 20260801
requer 1.10.0, mas o override **efetivo** do R36H em
`projects/ROCKNIX/packages/wayland/libxkbcommon/package.mk`
define **1.6.0**, obtido de
`https://xkbcommon.org/download/libxkbcommon-1.6.0.tar.xz`.

O override não fixa `PKG_SHA256`. O pipeline usa o arquivo original
de 510456 bytes, SHA-256
`0edc14eccdd391514458bc5f5a4b99863ed2d651e4dd761a90abf4f46ef99c2b`
e MD5 `90079ab4a0c6fa56dc75abffef9b1bc6`, de acordo com o
[manifesto de fonte Debian 2023](https://lists.debian.org/debian-x/2023/10/msg00071.html)
e [BLFS 12.1](https://linuxfromscratch.org/blfs/view/12.1/general/libxkbcommon.html).
Se o download não satisfizer **ambos os hashes**, o build falha.

SDK ROCKNIX imutável:
`3b9cb1f6bf48ee9ca0cf01edd9af52ca2a6b73fb`.
Toolchain real compilado no
[CI 39525819979](https://github.com/Baltdh/Fire4nix/actions/runs/39525819979).
Libxml2 e libwayland já existem no estágio ARM64 de
[CI 39693569119](https://github.com/Baltdh/Fire4nix/actions/runs/39693569119).

## Perfil de compilação

A receita **completa** do ROCKNIX para `DISPLAYSERVER=wl` habilita
`-Denable-x11=true -Denable-wayland=true` e `xkb-config-root`
em `/usr/share/X11/xkb`. Isso também pressupõe as bibliotecas alvo
XCB e xcb-xkb para `libxkbcommon-x11`.

Para o **primeiro teste mínimo do WPE em Wayland**, o script desta PR
utiliza `-Denable-x11=false`, `-Denable-tools=false`,
`-Denable-wayland=false`, `-Denable-xkbregistry=true`
e `-Dxkb-config-root=/usr/share/X11/xkb`:

- `enable-x11=false` afeta apenas a biblioteca adicional
  `libxkbcommon-x11`. Não remove os recursos principais de XKB.
- `enable-wayland=false` afeta os programas utilitários
  `xkbcli-interactive-wayland`, que são desativados.
  **Não desativa o uso de libxkbcommon por clientes Wayland.**
- `enable-xkbregistry=true` mantém a biblioteca auxiliar vinculada à
  **libxml2 real**.
- Não é um build completo de todas as extensões X11 do perfil
  ROCKNIX; essa diferença é deliberada, registrada e não pode ser
  promovida a substituição transparente das bibliotecas do firmware.

A checagem do estágio privado usa um script Python com bloqueio de
colisões de arquivos e symlinks. O Meson recebe apenas os cabeçalhos,
`.pc` e bibliotecas do AArch64; bison, flex e outras ferramentas
de geração rodam somente como host.

## Aceitação e limites

A workflow
`.github/workflows/r36h-rocknix-xkbcommon-160-target.yml`
compila a árvore e valida `libxkbcommon.so.0`,
`libxkbregistry.so.0`, `xkbcommon.pc` e `xkbregistry.pc`.
O consumidor de teste deve **ligar** os quatro SONAMEs ARM64 de
libxkbcommon, libxkbregistry, libxml2 e libwayland-client.
Não se tenta executá-lo no Ubuntu.

Os indicadores de sucesso são:

- `XKBCOMMON_BUILD=PASS_REAL_ROCKNIX_AARCH64`
- `XKBREGISTRY_LIBXML2=PASS_REAL_AARCH64`
- `XKB_WAYLAND_CONSUMER=PASS_REAL_AARCH64_FOUR_SONAMES`
- Binários `ELF64 AArch64`, SONAME válido, GLIBC no máximo 2.41,
  sem `TEXTREL` ou dependências GStreamer inesperadas.

**Ainda não comprovado:** carregamento de keymaps de
`/usr/share/X11/xkb` no console, eventos de teclado/controle físico,
renderização, HTTPS, GPU Mali, configuração completa nem compilação do
WPE WebKit. A próxima etapa é inserir o novo estágio no teste CMake
pós-Soup3 para resolver `FindXkbCommon.cmake` e descobrir
a dependência seguinte com a cadeia real. Não instalar nada em
`/usr/lib`, SD ou firmware do R36H.
