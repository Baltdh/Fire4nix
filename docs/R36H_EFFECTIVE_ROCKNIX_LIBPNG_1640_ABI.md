# Fire4Nix — corrigir discrepância da libpng ROCKNIX RK3326

## Causa e proveniência

No commit imutável ROCKNIX `3b9cb1f6bf48ee9ca0cf01edd9af52ca2a6b73fb` (20260801) há duas receitas diferentes:

- `packages/graphics/libpng/package.mk`: receita geral `PKG_VERSION="1.6.50"`, `PKG_SHA256="4df396518620a7aa3651443e87d1b2862e4e88cad135a8b93423e01706232307"`, `--enable-static --disable-shared`.
- `projects/ROCKNIX/packages/graphics/libpng/package.mk`: sobreposição específica, **`PKG_VERSION="1.6.40"`**, `--enable-static --enable-shared`, sem SHA-256 explícito no arquivo.

A [PR #58](https://github.com/Baltdh/Fire4nix/pull/58) prova a compilação da versão **genérica 1.6.50** com zlib do ROCKNIX, porém não resolve a compatibilidade com a versão específica pretendida pelo projeto. Não substituir silenciosamente 1.6.40 por 1.6.50 no pacote final.

## Origem do checksum da 1.6.40

O anúncio da versão libpng 1.6.40 publicado pelo mantenedor (22/06/2023) registra o SHA-256 da distribuição oficial **`libpng-1.6.40.tar.xz`**:

```text
535b479b2467ff231a3ec6d92a525906fb8ef27978be4f66dbe05d3f3a01b3a1
```

Fonte: https://sourceforge.net/p/png-mng/mailman/message/37860897/

O workflow dedicado baixa somente via HTTPS, compara o digest antes de descompactar e verifica que a receita ROCKNIX específica mantém a versão 1.6.40. O checksum da 1.6.40 **não deve** ser confundido com o checksum da 1.6.50 na receita geral.

## Escopo do build experimental

Workflow: `.github/workflows/r36h-rocknix-effective-libpng-1640.yml`

- Restaurar GCC AArch64 real/GLIBC 2.41 do artifact [39525819979](https://github.com/Baltdh/Fire4nix/actions/runs/39525819979), apenas no runner Ubuntu 22.04.
- Compilar zlib 1.3.1 para staging privado com GCC AArch64.
- Compilar libpng **1.6.40** com `PNG_SHARED=ON` e `PNG_STATIC=ON`, conforme a intenção de shared/static do perfil ROCKNIX, sobre zlib alvo (não zlib do Ubuntu).
- Auditar `libpng16.so*` ELF64 AArch64, `DT_NEEDED` `libz.so.1`, ABI GLIBC <= 2.41, cabeçalhos e `libpng16.a`.
- Linkar consumidor C com GCC alvo sem executar binário ARM64 no runner.

## Critério de aceitação

Só declarar resultado válido se o job `Fire4Nix effective ROCKNIX libpng 1.6.40 AArch64 with zlib` completar `success` e o artefato tiver bibliotecas, headers e relatórios. A existência de `.a` não garante execução física nem que a ABI do arquivo alvo coincida com toda a imagem ROCKNIX existente.

**Importante:** nem este teste nem a PR #58 compilam WPE WebKit ou comprovam HTML na tela 640×480, GIO TLS, Wayland/Mali ou o restante das bibliotecas. Não gravar `/usr/lib` do console com resultados do CI.

## Resultado real (21/10/2026)

**[GitHub Actions 39677982091 — SUCCESS](https://github.com/Baltdh/Fire4nix/actions/runs/39677982091)** com o GCC AArch64 real do ROCKNIX (20260801):

```text
LIBPNG_ZLIB_CHAIN=PASS_REAL_ROCKNIX_AARCH64_TARGET_LINK
LIBPNG_VERSION=1.6.40_ROCKNIX_PROJECT_EFFECTIVE
TARGET_ZLIB_VERSION=1.3.1
LIBPNG_STATIC_CONSUMER_LINK=PASS_ROCKNIX_TARGET_AARCH64
LIBPNG_GLIBC_MAX_REQUIRED=2.29
TARGET_EXECUTED=no
R36H_INSTALLABLE=no
```

O destino `DESTDIR` possui `libpng16.so.16.40.0` e `libpng16.a`, `libpng16.pc`, headers e zlib 1.3.1 alvo. Foram vinculados **dois consumidores AArch64 separados**: dinâmico (`libpng16.so.16` + `libz.so.1`) e estático (arquivo `libpng16.a` + `libz.so.1` + `libm.so.6`). O teste estático inicialmente revelou referências `pow` não resolvidas. A correção é adicionar explicitamente **`-lm`** após `-lpng16 -lz`, sem alterar ou remover símbolos da biblioteca. [Run com erro de link estático](https://github.com/Baltdh/Fire4nix/actions/runs/39677785986) e [run corrigido](https://github.com/Baltdh/Fire4nix/actions/runs/39677982091).

[Artefato temporário das bibliotecas alvo e relatórios (expira em 28/10/2026)](https://github.com/Baltdh/Fire4nix/actions/runs/39677982091/artifacts/12382294893). O arquivo serve apenas como evidência de desenvolvimento, **não como instalação no R36H**.
