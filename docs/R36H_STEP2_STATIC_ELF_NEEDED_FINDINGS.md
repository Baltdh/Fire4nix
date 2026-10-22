# Fire4Nix — análise estática DT_NEEDED do SDK unificado ROCKNIX

## Evidência observada

GitHub Actions: [39714047522](https://github.com/Baltdh/Fire4nix/actions/runs/39714047522).
Os arquivos vêm do pacote unificado da etapa 1 e do sysroot do
toolchain ROCKNIX RK3326, fonte `3b9cb1f6bf48ee9ca0cf01edd9af52ca2a6b73fb`.
Nenhum objeto ARM64 foi executado.

```text
STAGE_SHARED_ELFS=158
RESOLVED_EDGES=449
RESOLVED_FROM_STAGE=209
RESOLVED_FROM_SYSROOT=240
MISSING_EDGES=15
MISSING_SONAME_UNIQUE=1
MISSING_SONAME_NAMES=libgcc_s.so.1
INVALID_ELFS=0
NEWER_GLIBC_REFERENCES=0
UNSAFE_PATHS=6
ELF_CLOSURE_AUDIT=INCOMPLETE_REQUIRES_REVIEW
```

**Por que 158, se a etapa 1 indicou 157?** O arquivo ZIP do
GitHub Actions pode transformar links SONAME em cópias normais ao baixar
o estágio; estas são contagens dos objetos efetivamente encontrados na
árvore auditada, não uma promessa de 158 bibliotecas distintas.

Os 15 vínculos não resolvidos correspondem ao mesmo SONAME
`libgcc_s.so.1`, mencionado por aliases de ICU (libicuuc, libicui18n,
libicuio, libicutu e libicutest). Isso demonstra a insuficiência do
*sysroot consultado*, não comprova ausência da biblioteca no firmware
instalado no R36H.

Os seis objetos com caminhos de compilação indesejados são aliases de:

- `libfontconfig.so`, `libfontconfig.so.1`, `libfontconfig.so.1.16.1`.
- `libgcrypt.so`, `libgcrypt.so.20`, `libgcrypt.so.20.5.1`.

Esses objetos continham `RUNPATH` apontando para
`/home/runner/work/Fire4nix/Fire4nix/...`; **não devem ser
distribuídos no console com tal referência**. O PR #105 fornece
um **overlay privado, não instalável**, de cópias desses seis ELFs com os
caminhos removidos e os metadados ABI essenciais revalidados.

## Política técnica

- `--strict` é um bloqueio de publicação: qualquer dependência
  ausente, ELF inválido, GLIBC maior que 2.41 ou caminho inseguro falha.
- Modo diagnóstico registra lacunas e pode terminar com código 0 mesmo
  com `ELF_CLOSURE_AUDIT=INCOMPLETE_REQUIRES_REVIEW`. CI verde neste modo
  quer dizer **detecção funcionando**, não fechamento aprovado.
- O auditor não chama `ldd`, `dlopen`, subprocessos WPE, Sway nem
  binaries AArch64. Verifica presença de nomes apenas; compatibilidade
  de símbolos e escolha do loader devem ser verificadas posteriormente.
- O sysroot do compilador não é necessariamente uma cópia exata do
  filesystem do dispositivo. O resultado completo precisa incluir
  um snapshot autorizado de bibliotecas da mesma versão do ROCKNIX.

## Localização comprovada da biblioteca de suporte GCC

A [execução #39714391170](https://github.com/Baltdh/Fire4nix/actions/runs/39714391170)
localizou `libgcc_s.so.1` no **toolchain genuíno ROCKNIX**,
em `toolchain/aarch64-rocknix-linux-gnu/lib64/libgcc_s.so.1`,
fora da parte `sysroot/usr/lib` consultada inicialmente.
`readelf` confirmou `Class: ELF64`, little-endian,
`Machine: AArch64` e `SONAME: libgcc_s.so.1`.
Ainda é necessário auditar requisitos de GLIBC/DT_NEEDED antes de
incluir uma cópia no estágio privado. Não inferir automaticamente
que o mesmo arquivo deva substituir a biblioteca do firmware.

## Próximas ações

1. Inspecionar se `libgcc_s.so.1` está no toolchain ROCKNIX,
   validar `ELF64/AArch64`, GLIBC e `DT_NEEDED` antes de copiá-la
   para um estágio de desenvolvimento.
2. Usar apenas a variante Fontconfig/Libgcrypt com `RUNPATH` limpo,
   jamais os caminhos efêmeros.
3. Repetir a auditoria de fechamento e testes de compilação do WebCore,
   JavaScriptCore e WPEPlatform antes de empacotar o navegador.
4. Testar efetivamente no R36H para resolver diferenças de runtime
   não reproduzidas no CI.
