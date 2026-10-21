# Fire4Nix — três bibliotecas alvo integradas com GCC ROCKNIX real

## Resultado verificado em 21/10/2026

[GitHub Actions 39657259468 — SUCCESS](https://github.com/Baltdh/Fire4nix/actions/runs/39657259468) confirmou que três dependências compiladas *separadamente* podem compartilhar um `DESTDIR` privado e ser vinculadas conjuntamente pelo cross-compiler oficial ROCKNIX RK3326.

- GCC AArch64 ROCKNIX/GLIBC 2.41, recuperado exclusivamente do checkpoint [39525819979](https://github.com/Baltdh/Fire4nix/actions/runs/39525819979).
- zlib 1.3.1 real do [39539080424](https://github.com/Baltdh/Fire4nix/actions/runs/39539080424).
- SQLite 3.50.2 real do [39539424500](https://github.com/Baltdh/Fire4nix/actions/runs/39539424500).
- libtasn1 4.21.0 real do [39538774186](https://github.com/Baltdh/Fire4nix/actions/runs/39538774186).

O teste verificou os headers, metadados `pkg-config`, formato ELF64 AArch64 e limites GLIBC dos objetos compartilhados. Ao construir `combined-consumer-aarch64`, confirmou os três SONAMEs em `DT_NEEDED`: `libz.so.1`, `libsqlite3.so.0`, `libtasn1.so.6`. Os arquivos são acumulados em um staging privado, com verificação de colisões e symlinks inseguros.

A execução registrou:

```text
PRIVATE_STAGE_FILES_COPIED=66
THREE_DEPENDENCY_STAGE=PASS_REAL_ROCKNIX_AARCH64
THREE_DEPENDENCY_CONSUMER_LINK=PASS_ALL_THREE_REAL_SONAMES
TARGET_MAX_GLIBC=2.41
LIBRARIES=zlib_1.3.1,sqlite_3.50.2,libtasn1_4.21.0
R36H_EXECUTED=no
```

Artefato: [Fire4Nix-ROCKNIX-THREE-REAL-DEPS-PRIVATE-STAGE](https://github.com/Baltdh/Fire4nix/actions/runs/39657259468/artifacts/12371387708). Retenção temporária até 04/11/2026.

## Limites obrigatórios

**Este é um teste de ligação AArch64, não um navegador pronto.** O ELF não foi executado no host x86 nem no R36H. Não há validação de resolução de símbolos pelo loader real, nem HTTPS, GUI ou renderização Wayland/Mali. As outras dependências de desenvolvimento de WebKit e os processos WPE continuam pendentes. O sistema do console, firmware e `/usr/lib` não foram modificados.

O staging é somente para testes cruzados e **não** deve ser copiado para o console como se fosse um pacote de instalação.

## Próxima etapa técnica

Construir bibliotecas alvo dependentes dessas três, especialmente `libpng` usando `zlib`, continuar com GLib/GIO, libsoup3, libpsl e glib-networking TLS, e montar um sysroot com headers e metadados completos. Só após o fechamento de dependências configurar, compilar e ligar o WPE WebKit com `USE_GSTREAMER=OFF` e auditar as bibliotecas finais.
