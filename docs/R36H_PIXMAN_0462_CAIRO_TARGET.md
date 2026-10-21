# Fire4Nix — Pixman 0.46.2, etapa prévia a Cairo e HarfBuzz

## Por que esta etapa é necessária

O teste do CMake **real** do WPE WebKit 2.54.1 no SDK ROCKNIX
[39684582460](https://github.com/Baltdh/Fire4nix/actions/runs/39684582460)
parou em `FindHarfBuzz.cmake`, versão mínima 2.7.4, versão de destino
não encontrada.

Na distribuição ROCKNIX 20260801, a receita HarfBuzz 11.2.1 liga com
Cairo, FreeType e GLib. Cairo, por sua vez, depende de Pixman,
Fontconfig, FreeType, GLib, libpng e zlib. Pixman **não resolve sozinho**
o bloqueio do HarfBuzz. É apenas uma dependência real, isolada, que
permite prosseguir sem usar binários x86_64 ou bibliotecas Ubuntu.

## Proveniência fixada

- Checkout ROCKNIX `3b9cb1f6bf48ee9ca0cf01edd9af52ca2a6b73fb`
- `packages/x11/lib/pixman/package.mk`: **0.46.2**
- SHA256 oficial da receita `d075209d18728b1ca5d0bb864aa047a262a1fde206da8a677d6af75b2ee1ae98`
- URL `https://xorg.freedesktop.org/archive/individual/lib/pixman-0.46.2.tar.xz`
- O override `projects/ROCKNIX/packages/x11/lib/pixman/package.mk` define
  flags específicas para AArch64: MMX, SSE2, VMX, ARM SIMD, NEON e IWMMXT
  desabilitados. Mantidas no teste, em vez de importar otimizações de x86_64.

O teste reusa os artefatos genuínos previamente aprovados:
[toolchain 39525819979](https://github.com/Baltdh/Fire4nix/actions/runs/39525819979)
e [sete dependências 39682062894](https://github.com/Baltdh/Fire4nix/actions/runs/39682062894).

## Limites e critérios

`scripts/build-rocknix-pixman-cairo-prereq.sh` compila o Pixman no CI
sem tocar o rootfs, `/usr/lib` ou cartão do R36H. A workflow
`.github/workflows/r36h-rocknix-pixman-cairo-prereq.yml` deve comprovar:

1. Fonte íntegra via SHA-256 idêntico à receita ROCKNIX
2. Compilador `aarch64-rocknix-linux-gnu-gcc` genuíno, ELF64 AArch64
3. `pixman-1.pc` versão 0.46.2, instalado em DESTDIR privado
4. `libpixman-1.so` AArch64 e GLIBC requerida no máximo 2.41
5. Um objeto AArch64 compartilhado vinculado aos SONAMEs reais de
   Pixman, GLib, libpng e zlib, não executado no runner x86_64
6. Nenhum `libgst*` requerido e nenhum `TEXTREL` no DSO produzido

Um workflow aprovado significa **Pixman compilado e verificado**, não
Cairo, HarfBuzz ou WebKit compilados; nenhum navegador instalável
deve ser oferecido a partir desse artefato.

## Próximos bloqueios objetivos

Para recompilar o WPE após o teste: terminar a etapa FreeType 2.13.3
em andamento em outra PR; preparar Fontconfig (Expat/libxml2/FreeType);
Pixman + Cairo (com flags corretas para Wayland/GLES);
HarfBuzz 11.2.1 contra essas dependências; reexecutar o diagnóstico
CMake contra o mesmo SDK. Só depois compilar e validar o WebCore,
WPEPlatform, JavaScriptCore, GIO/TLS, bibliotecas e Wayland/Mali no
R36H real.
