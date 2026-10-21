# Fire4Nix — Primeira compilação real de dependência ROCKNIX para R36H

## Contexto verificado

A execução GitHub Actions [39525819979](https://github.com/Baltdh/Fire4nix/actions/runs/39525819979) concluiu o toolchain ROCKNIX 20260801 com compiladores GCC/G++ 15.2.0, sysroot GLIBC 2.41 e provas reais C/C++ AArch64, gerando o artefato `ROCKNIX-RK3326-toolchain-HOST-ONLY` (ID 12315721316). Esse é um ambiente de compilação **do host**, não um navegador ou aplicativo instalável no R36H.

## Passo seguinte implementado

O workflow `.github/workflows/r36h-rocknix-libtasn1-crosscompile.yml` reutiliza o artefato original **fixando a execução 39525819979**, sem baixar toolchains arbitrários nem recompilar o GCC. Mantém o caminho do workspace original, necessário porque o checkpoint do toolchain não é relocável automaticamente.

O script `scripts/build-rocknix-libtasn1.sh`:

1. verifica que a compilação ocorre em GitHub Actions, usuário não-root e workspace esperado;
2. reutiliza o sysroot real e executa `check-rocknix-sdk.sh` e `check-rocknix-compiler.sh`;
3. baixa `libtasn1-4.21.0.tar.gz` do GNU por HTTPS e exige o SHA256 fixado `1d8a444a223cc5464240777346e125de51d8e6abf0b8bac742ac84609167dc87`;
4. compila com `aarch64-rocknix-linux-gnu-gcc`, cabeçalhos e libc alvo e usa `make DESTDIR=...` para criar uma pasta privada de staging;
5. exige `libtasn1.so.6` ELF64 AArch64, GLIBC requerida no máximo 2.41, arquivo `libtasn1.pc` e cabeçalho `libtasn1.h`;
6. salva relatórios, checksum dos arquivos e arquivo tar do staging somente para desenvolvimento.

`make check` e execução de binários ARM64 no Ubuntu não fazem parte deste teste. Ele valida *cross-compilation e linking* com o ambiente ROCKNIX real, não o funcionamento da biblioteca no console.

## Aceitação estrita

Só declarar sucesso após CI mostrar `LIBTASN1_BUILD=PASS_REAL_ROCKNIX_CROSS_COMPILE`, `LIBTASN1_TARGET=ELF64_AARCH64`, `LIBTASN1_DEV_PC=PASS`, `LIBTASN1_HEADERS=PASS`, e a etapa de upload de staging produzir artefato.

O pacote `STAGE-ONLY` não deve ser copiado diretamente para `/usr/lib`, SD exFAT ou firmware. É material de compilação incremental para WebKit, não uma instalação autônoma.

Depois da libtasn1, o próximo trabalho é resolver `libpsl` com dependência ICU, `glib-networking` com GnuTLS/GIO TLS e `libsoup3`. Concluir o WPE exige ainda dependências transitivas no sysroot, WebCore, recursos, subprocessos, auditoria ELF dinâmica e renderização física no R36H.
