# Integração de quatro dependências reais — 21/10/2026

## Estado recuperado

O runtime recuperado no R36H encontrou `GST_CAT_DEFAULT` indefinido. A estratégia permanece compilar WPE WebKit 2.54.1 sem GStreamer com bibliotecas AArch64 compatíveis com ROCKNIX, preservando `/usr/lib` do console.

- Compilador ROCKNIX/GCC: [39525819979](https://github.com/Baltdh/Fire4nix/actions/runs/39525819979), concluído.
- SQLite 3.50.2: [39539424500](https://github.com/Baltdh/Fire4nix/actions/runs/39539424500), aprovado.
- libtasn1 4.21.0: [39538774186](https://github.com/Baltdh/Fire4nix/actions/runs/39538774186), aprovado.
- Integração anterior com três bibliotecas: [39657259468](https://github.com/Baltdh/Fire4nix/actions/runs/39657259468), aprovada.
- libpng efetiva 1.6.40 com zlib 1.3.1: [39677499120](https://github.com/Baltdh/Fire4nix/actions/runs/39677499120), aprovada. A receita específica do projeto prevalece sobre libpng genérica 1.6.50.

## Nova integração

`r36h-four-deps-integration.yml` usa artefatos de execuções fixas. A zlib vem do mesmo estágio da libpng; não sobrepõe uma segunda cópia de outro build. O script monta um DESTDIR privado, rejeita colisões diferentes e links inseguros, verifica headers e pkg-config isolado, exige libpng 1.6.40, ELF64 AArch64 e requisitos GLIBC das bibliotecas <= 2.41.

Um consumidor C usa símbolos das quatro bibliotecas. A auditoria exige os SONAMEs libpng16.so.16, libz.so.1, libsqlite3.so.0 e libtasn1.so.6 no executável, além de libz.so.1 na libpng. O consumidor é ligado, não executado. A comparação de versão no C não é teste de execução; a versão exata é verificada separadamente nos metadados pkg-config.

Execução desta integração: [39677741691](https://github.com/Baltdh/Fire4nix/actions/runs/39677741691). Consultar seu resultado e `acceptance.txt`; criação da PR não equivale a aprovação.

## Limites e próximos critérios

Este DESTDIR ainda não é o sysroot completo do WebKit nem pacote instalável. Completar dependências restantes, validar metadados e ELF transitivo, configurar/compilar WPE sem GStreamer, auditar runtime e só então testar HTML offline, controles e Wayland/Mali no R36H físico. Manter ZIP ideal abaixo de 100 MB e limite de 170 MB. Artefatos de desenvolvimento não devem ser enviados como navegador.

Validações locais: sintaxe Bash, YAML, Python embutido, comandos Bash do workflow, ajuda e recusa fora do runner CI não-root. Não substituem o teste real no Actions.
