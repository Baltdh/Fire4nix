# libffi estática PIC para GLib/WPE — 21/10/2026

## Motivo

A receita GLib 2.85.1 do ROCKNIX fixado em `3b9cb1f6bf48ee9ca0cf01edd9af52ca2a6b73fb` declara libffi, pcre2, util-linux e zlib como dependências alvo. A PR #60 já validou zlib junto com SQLite, libtasn1 e libpng. Esta etapa constrói a libffi separadamente, preservando o trabalho paralelo de Expat.

## Fidelidade ao ROCKNIX

- libffi 3.5.1, SHA-256 `f99eb68a67c7d54866b7706af245e87ba060d419a062474b456d3bc8d4abdbd1`.
- Dois patches da receita original aplicados antes de `autoreconf -fi`: localização de instalação e pkg-config.
- `--enable-static --disable-shared --with-pic`, além das opções target originais. O consumidor compartilhado usa a libffi estática PIC; não é produzida libffi.so.
- Cross-compiler real ROCKNIX da execução 39525819979, restaurado no caminho original. Instalação limitada a DESTDIR privado.

## Critérios verificáveis

1. SHA e commit upstream exatos.
2. libffi.pc 3.5.1 consultado sem PKG_CONFIG_PATH do host.
3. Todos os membros do arquivo estático são ELF64 AArch64 REL.
4. Consumidor compartilhado usa ffi_prep_cif, ffi_call e ffi_type_sint; link com `-z defs` exige resolução completa.
5. Sem TEXTREL e sem dependência dinâmica libffi; versões GLIBC do consumidor <= 2.41.
6. Artefato inclui stage, relatórios e consumidor para auditoria.

Execução inicial: https://github.com/Baltdh/Fire4nix/actions/runs/39678224570 . Consultar resultado antes de considerar o build aprovado.

## Limites

Não executa o consumidor ARM64 nem comprova resultado de ffi_call no hardware. Não integra ainda libffi ao DESTDIR das quatro bibliotecas. Faltam dependências restantes do GLib e do WebKit, compilação completa WPE sem GStreamer e teste físico R36H. O artefato é de desenvolvimento, não navegador instalável.
