# Fire4Nix — LibGcrypt real para o WPE 2.54.1 do ROCKNIX

## Bloqueio medido, não presumido

O [workflow WPE 39693723425](https://github.com/Baltdh/Fire4nix/actions/runs/39693723425)
conseguiu superar a descoberta anterior de HarfBuzz com ICU e libepoxy/EGL,
mas **não configurou WPE WebKit completamente**: `WPE_CMAKE_EXIT_CODE=1`
devido a `Could NOT find LibGcrypt`, com ausência de
`LibGcrypt_LIBRARY` e `LibGcrypt_INCLUDE_DIR`.

Esta etapa constrói o par de bibliotecas necessário para resolver **esse**
erro concreto. O código continua sem executar o navegador no R36H.

## Fontes ROCKNIX 20260801 e versões efetivas

- Checkout exato ROCKNIX:
  `3b9cb1f6bf48ee9ca0cf01edd9af52ca2a6b73fb`.
- GCC AArch64 real da execução
  [39525819979](https://github.com/Baltdh/Fire4nix/actions/runs/39525819979).
- `packages/security/libgpg-error/package.mk`, versão **1.55**,
  SHA256 `95b178148863f07d45df0cea67e880a79b9ef71f5d230baddc0071128516ef78`.
- O **override específico** do ROCKNIX
  `projects/ROCKNIX/packages/security/libgpg-error/package.mk`
  exige `--disable-static --enable-shared`, ao contrário da receita
  genérica. Isso foi expressamente corrigido durante a revisão:
  precisamos de **libgpg-error.so.0** AArch64, não apenas `.a`.
- `packages/security/libgcrypt/package.mk`, versão **1.11.1**,
  SHA256 `24e91c9123a46c54e8371f3a3a2502f1198f2893fbfbf59af95bc1c21499b00e`.
- Os dois tarballs são obtidos de `https://www.gnupg.org/ftp/gcrypt/`
  e devem passar os hashes originais antes da extração.

## Portabilidade e segurança do teste

A workflow `.github/workflows/r36h-rocknix-libgcrypt-1111-wpe.yml`
restaura o compilador genuíno sem modificar o sysroot. O script
`scripts/build-rocknix-libgcrypt-1111-wpe.sh` constrói libgpg-error
compartilhada e, em seguida, LibGcrypt compartilhada no mesmo
`DESTDIR` privado, com `CC_FOR_BUILD=gcc` apenas para geradores
nativos exigidos pelas receitas autotools.

Os testes de aceitação devem verificar:

1. `libgpg-error.so.0` e `libgcrypt.so.20` ELF64 AArch64 genuínos.
2. Hash SHA256 correspondente **às fontes ROCKNIX fixadas**.
3. `DT_NEEDED` de LibGcrypt apontando à
   `libgpg-error.so.0` do estágio compatível.
4. Cabeçalhos `gpg-error.h` e `gcrypt.h` verdadeiros do target.
5. Versões GLIBC exigidas no máximo 2.41, sem `TEXTREL` ou GStreamer.
6. Objeto de teste AArch64 vinculado simultaneamente às duas bibliotecas,
   sem sua execução no host x86_64.
7. Log/artefato com `LIBGCRYPT_TARGET_BUILD=PASS_REAL_ROCKNIX_AARCH64`.

## O que ainda não está concluído

A presença dessas bibliotecas no estágio não faz automaticamente o CMake
WPE passar. É necessário anexá-las à cadeia de dependências do
[workflow de descoberta WPE real](https://github.com/Baltdh/Fire4nix/actions/runs/39693723425),
usar o mesmo `pkg-config` e `CMAKE_FIND_ROOT_PATH` alvo e repetir o
diagnóstico para encontrar o próximo bloqueio. Depois será preciso
compilar WPE WebKit 2.54.1, verificar fechamento dos `DT_NEEDED`,
GLIBC/GStreamer, iniciar processo sob Wayland/Mali e testar HTML e HTTPS
fisicamente no R36H.

Nenhum arquivo do firmware, cartão ou `/usr/lib` do aparelho é alterado.
