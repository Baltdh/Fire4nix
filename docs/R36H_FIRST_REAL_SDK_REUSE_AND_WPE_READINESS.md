# Fire4Nix — auditoria do primeiro toolchain ROCKNIX real reutilizado

## Origem, sem confundir build e navegador

O workflow [39525819979](https://github.com/Baltdh/Fire4nix/actions/runs/39525819979) terminou **SUCCESS**:
- ROCKNIX no commit `3b9cb1f6bf48ee9ca0cf01edd9af52ca2a6b73fb` (tag 20260801)
- GCC/G++ 15.2.0, compilação e ligação C/C++ com alvo **AArch64**
- glibc alvo 2.41, verificação do ELF `libc.so.6`
- artefato `ROCKNIX-RK3326-toolchain-HOST-ONLY`, ID `12315721316`, gerado e preservado por **7 dias**

A compilação terminou após cerca de uma hora e produziu um **SDK do host**, não um navegador para cartão SD. O `sysroot` do toolchain não contém automaticamente todas as 22 dependências de desenvolvimento exigidas pelo WPE 2.54.1. A execução gráfica real ainda está pendente.

## Auditoria sem reconstruir GCC

A workflow `.github/workflows/audit-r36h-real-rocknix-sdk.yml` recupera o artefato **por run-id 39525819979** usando o token de Actions com permissão `actions:read`. O download tem digest SHA-256 verificado pela action de download.

`scripts/audit-real-rocknix-sdk-checkpoint.sh`:

1. Reconstitui o SDK no caminho original da workspace do GitHub Actions, necessário porque o `fire4nix-toolchain.cmake` e ferramentas de GCC contêm paths absolutos;
2. Inspeciona os membros da tarball e rejeita caminhos fora de `toolchain/`, excluindo links auxiliares que escapam do checkout — sem permitir gravações em `/usr/lib`;
3. Roda `check-rocknix-sdk.sh` no ELF real (`GLIBC_2.41`, AArch64);
4. Roda `check-rocknix-compiler.sh`, compilando/linkando programas C e C++ AArch64, **sem executar o ELF no host**;
5. Roda `audit-wpe-sysroot-pkgconfig.sh --inspect` contra os diretórios `.pc` do sysroot recuperado e salva os 22 resultados em `sdk-audit-reports/wpe-pkgconfig-real-sysroot.txt`.

O auditor `pkg-config` também bloqueia links simbólicos de diretórios para bibliotecas externas ao sysroot. Existe regressão com um `.pc` de host colocado atrás de um symlink.

## Como interpretar o resultado

- `REAL_SDK_CHECKPOINT=PASS_RESTORED_AND_C_CXX_LINKED`: o compilador restaurado passou as provas básicas de ABI e compilação C/C++.
- `SYSROOT_PC_AUDIT=INCOMPLETE_TARGET_SDK` ou `BLOCKED_NO_TARGET_PKGCONFIG_DIRECTORIES`: faltam pacotes alvo. **Não** é falha do toolchain; é o estágio normal antes de compilar dependências WPE.
- `SYSROOT_PC_AUDIT=PASS_TARGET_PKGCONFIG_METADATA_ONLY`: somente metadados e versões `.pc` passaram. **Não comprova** linkagem, ELF transitivo, HTTPS, WebKit funcional ou Mali.
- Nunca baixar `ROCKNIX-RK3326-toolchain-HOST-ONLY` no R36H para tentar executá-lo.

## Próximo marco

Compilar libs nativas da mesma receita ROCKNIX 20260801 (GLib/GIO, libsoup3, HarfBuzz, libpsl, GnuTLS, gráficos e restantes), com o sysroot correto. Só então configurar/compilar WPE WebKit 2.54.1 com `USE_GSTREAMER=OFF`, auditar ELF e fazer a primeira página HTML offline no console.

**Observação:** o workflow usa o artefato temporário de 7 dias; depois de expirado será necessário republicar um SDK validado com retenção adequada ou executar novamente o bootstrap. Não há instalação física nesta etapa.
