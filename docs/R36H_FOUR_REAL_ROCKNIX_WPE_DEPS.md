# Fire4Nix — Quatro dependências reais ROCKNIX no mesmo estágio

## Objetivo

Ampliar o estágio privado aprovado na [PR #57](https://github.com/Baltdh/Fire4nix/pull/57):
zlib **1.3.1**, SQLite **3.50.2** e libtasn1 **4.21.0**, acrescentando
**Expat 2.7.1** para análise XML no futuro WPE WebKit.

Usar o compilador GCC AArch64 e sysroot originais gerados pelo
[workflow 39525819979](https://github.com/Baltdh/Fire4nix/actions/runs/39525819979),
ROCKNIX commit `3b9cb1f6bf48ee9ca0cf01edd9af52ca2a6b73fb`.

## Entradas fixadas

- Checkpoint de toolchain: `ROCKNIX-RK3326-toolchain-HOST-ONLY`, execução `39525819979`.
- Pacote de três dependências: `Fire4Nix-ROCKNIX-THREE-REAL-DEPS-PRIVATE-STAGE`,
  execução `39657259468`. Conferir seus arquivos de aceitação antes do reaproveitamento.
- Expat: receita `packages/textproc/expat/package.mk`, versão `2.7.1`,
  SHA256 `354552544b8f99012e5062f7d570ec77f14b412a3ff5c7d8d0dae62c0d217c30`.
- Override em `projects/ROCKNIX/packages/textproc/expat/package.mk` herda
  a receita de base, apenas acrescentando compatibilidade de política CMake.

## Critérios de teste

O workflow `.github/workflows/r36h-four-rocknix-target-deps-expat.yml`
deve **falhar** caso:

- os dois artefatos predecessores não existam, estiverem incompletos ou não
  corresponderem aos nomes/checkpoints fixados;
- o GCC não reportar `aarch64-rocknix-linux-gnu` ou o sysroot não for AArch64;
- o hash SHA256 de Expat for diferente da receita oficial;
- Expat não gerar ELF64 AArch64 compatível com a GLIBC 2.41 do dispositivo;
- o arquivo `expat.pc` ou algum dos três `.pc` anteriores estiver ausente;
- não for possível compilar **um consumidor ARM64 vinculado aos quatro SONAMEs
  reais** de zlib, SQLite, libtasn1 e Expat.

Resultado positivo exigido: `FOUR_DEPENDENCY_STAGE=PASS_REAL_ROCKNIX_AARCH64`
e `FOUR_DEPENDENCY_CONSUMER_LINK=PASS_ALL_FOUR_REAL_SONAMES`, além de relatórios
de ELF, GLIBC, hash e `pkg-config` no artefato.

## Escopo e limitações

Os executáveis AArch64 são **compilados, mas não executados** no runner x86_64.
O estágio privado é prova de integração do linker, não pacote pronto para
instalação. A ausência de outros módulos para WPE e GIO TLS, a renderização
Wayland/Mali, os problemas anteriores de GStreamer e a estabilidade no R36H
ainda não estão resolvidos por esta etapa.

O artefato tem retenção limitada pelo GitHub; compilações posteriores precisam
revalidar a integridade, não assumir que os artefatos sempre existirão.
