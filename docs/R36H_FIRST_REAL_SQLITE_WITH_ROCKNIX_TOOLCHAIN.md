# Fire4Nix — segunda biblioteca real em AArch64: SQLite 3.50.2

## Evidência CI (21/10/2026)

A [execução 39539424500](https://github.com/Baltdh/Fire4nix/actions/runs/39539424500)
restaurou o cross-compiler ROCKNIX de [39525819979](https://github.com/Baltdh/Fire4nix/actions/runs/39525819979)
exatamente no caminho absoluto originalmente usado no GitHub Actions Ubuntu 22.04.

A fonte `sqlite-autoconf-3500200.tar.gz` da versão **3.50.2** foi obtida da
URL definida pela receita ROCKNIX 20260801 e teve o SHA-256 verificado:

`84a616ffd31738e4590b65babb3a9e1ef9370f3638e36db220ee0e73f8ad2156`

A compilação usou `aarch64-rocknix-linux-gnu-gcc`, configure cross-target,
`make` e `make install DESTDIR=...`. Não foram executados ELFs do alvo na máquina
de build x86_64.

### Saída real verificada

- `SQLITE_TARGET_BUILD=PASS_REAL_ROCKNIX_AARCH64`
- `SQLITE_VERSION=3.50.2`
- `ELF_MACHINE=AArch64` / classe `ELF64`
- `GLIBC_REQUIRED=2.38`, dentro do limite `2.41` identificado no console.
- `usr/lib/pkgconfig/sqlite3.pc` gerado e validado com `PKG_CONFIG_LIBDIR`
  restrito ao DESTDIR privado.
- Artefato [12317824915](https://github.com/Baltdh/Fire4nix/actions/runs/39539424500/artifacts/12317824915)
  contém `libsqlite3.so*`, headers e relatórios, somente para teste.

## Integração com os avanços existentes

A [PR #55](https://github.com/Baltdh/Fire4nix/pull/55) construiu com o mesmo
compiler a **zlib 1.3.1 AArch64** (`GLIBC_2.17`). Este passo acrescenta SQLite
de verdade, sem usar o SQLite da máquina de build. São dois testes independentes
de bibliotecas de destino; **não** significa que essas bibliotecas tenham sido
instaladas conjuntamente no sysroot completo do WPE.

Conforme a [PR #52](https://github.com/Baltdh/Fire4nix/pull/52), o snapshot
inicial do toolchain mantém **22 de 22 requisitos .pc não atendidos**. É
necessário compilar/instalar as dependências em um **mesmo** sysroot isolado,
reexecutar o auditor, realizar a configuração real do WPE 2.54.1 e compilar
WebCore/WebKit. Nenhum navegador ou driver Mali/Wayland foi testado fisicamente.

## Próximo pacote e cautela de receitas

A receita genérica de `libpng` no upstream está em versão **1.6.50**, mas
`projects/ROCKNIX/packages/graphics/libpng/package.mk` declara **1.6.40**
e opções diferentes de compartilhamento. Antes de incluí-la no build real,
é preciso resolver a precedência da receita e comprovar o hash efetivo,
sem escolher silenciosamente uma versão incorreta.
