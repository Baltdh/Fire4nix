# Fire4Nix — Wayland 1.23.1 do ROCKNIX para o WPE no R36H

## Contexto

A construção do navegador Fire4Nix para R36H (RK3326, Cortex-A35,
AArch64, glibc 2.41) precisa de cliente Wayland para exibir a interface
em ROCKNIX/Sway, além do restante da cadeia WPE WebKit.

A receita `projects/ROCKNIX/packages/wayland/wayland/package.mk`
da distribuição ROCKNIX 20260801 substitui a versão geral
**1.24.0** pela versão **1.23.1**, desabilitando `scanner` no destino,
mas habilitando bibliotecas compartilhadas. A presente etapa respeita
a versão **efetiva**, em vez de misturar fontes 1.24.0 ao firmware 1.23.1.

## Proveniência e fontes

- Commit imutável ROCKNIX:
  `3b9cb1f6bf48ee9ca0cf01edd9af52ca2a6b73fb`.
- Toolchain genuine RK3326 AArch64:
  [build 39525819979](https://github.com/Baltdh/Fire4nix/actions/runs/39525819979).
- Estágio de bibliotecas alvo (libffi, Expat, libxml2 etc.):
  [Fontconfig CI 39687860420](https://github.com/Baltdh/Fire4nix/actions/runs/39687860420).
- Wayland tarball `wayland-1.23.1.tar.xz`, hash SHA256 oficial:
  `864fb2a8399e2d0ec39d56e9d9b753c093775beadc6022ce81f441929a81e5ed`.
  A receita ROCKNIX de projeto não tem SHA256; neste teste, o valor foi
  recuperado de uma **mensagem de lançamento de Wayland publicada por
  Simon Ser em agosto de 2024** e confirmado por Buildroot.
  Referências: [anúncio](https://mail-archive.com/wayland-devel%40lists.freedesktop.org/msg43056.html)
  e [Buildroot](https://lists.buildroot.org/pipermail/buildroot/2025-September/786400.html).

O download é aceito somente se um dos espelhos HTTPS fornecer **exatamente**
esse hash. A diferença entre a receita base 1.24.0 e o override 1.23.1
é intencional e fica documentada.

## Ponto crítico do cross-build

O Wayland 1.23.1 exige um `wayland-scanner` **nativo** para gerar os
cabeçalhos e descrições do protocolo, mesmo que `-Dscanner=false` no
destino. O fluxo reproduz o comportamento do pacote original do ROCKNIX:

1. Compilar `wayland-scanner 1.23.1` em um **prefixo de host privado**,
   com `-Dscanner=true -Dlibraries=false`, `libexpat` somente no Ubuntu.
2. Configurar o projeto target em **cross-file Meson** independente com
   `aarch64-rocknix-linux-gnu-gcc`, `-Dscanner=false` e `-Dlibraries=true`.
3. Vincular o gerador nativo por `wayland-scanner.pc` do próprio host,
   sem permitir que as dependências ELF de destino sejam resolvidas no Ubuntu.
4. Compilar `wayland-client`, `wayland-server`, `wayland-cursor` e
   `wayland-egl` e instalar **somente** no `DESTDIR` privado.
5. Auditar os quatro DSOs ELF64 AArch64, SONAME, GLIBC até 2.41, ausência
   de `TEXTREL` e dependências GStreamer.
6. Compilar, **não executar**, uma biblioteca de integração ARM64 que
   referencia as quatro APIs e comprovar os quatro registros DT_NEEDED.

Os arquivos da PR são:

- `scripts/build-rocknix-wayland-1231-wpe.sh`
- `.github/workflows/r36h-wayland-1231-real-target.yml`
- Este documento.

## Critérios de aceitação

O workflow deve terminar **SUCCESS** e produzir os registros:

`WAYLAND_TARGET_BUILD=PASS_REAL_ROCKNIX_AARCH64`

`WAYLAND_HOST_SCANNER=PASS_SEPARATE_NATIVE_GENERATOR`

`WAYLAND_LINK_CONSUMER=PASS_FOUR_REAL_AARCH64_SONAMES`

A versão 1.23.1 no `wayland-client.pc`, `wayland-server.pc`,
`wayland-cursor.pc` e `wayland-egl.pc` deve ser comprovada com
`pkg-config` restrito ao stage real.

### O que isto ainda não prova

Não compila WPE WebKit 2.54.1, libepoxy nem
Wayland-protocols do compositor. Também não valida Mali/GLES, HTTPS,
controle do gamepad, renderização 640×480 ou uso real de memória no console.
O artefato não é instalável no R36H. Não executar binários target num runner
x86_64 e não instalar arquivos na raiz do sistema do aparelho.
