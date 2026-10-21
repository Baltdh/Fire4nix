# Fire4Nix — primeira dependência **real** construída com toolchain ROCKNIX

## Resultado: 21 de outubro de 2026

A [execução 39539080424](https://github.com/Baltdh/Fire4nix/actions/runs/39539080424) restaurou o artefato do **toolchain genuíno ROCKNIX RK3326** produzido pelo [build bem-sucedido 39525819979](https://github.com/Baltdh/Fire4nix/actions/runs/39525819979), no **mesmo caminho absoluto** do workspace GitHub Actions usado na compilação original. Foi validado `aarch64-rocknix-linux-gnu` antes de qualquer nova compilação.

O novo workflow usou exclusivamente o arquivo **zlib 1.3.1** especificado em `packages/compress/zlib/package.mk` do ROCKNIX 20260801, commit `3b9cb1f6bf48ee9ca0cf01edd9af52ca2a6b73fb`, verificando SHA-256:

`9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23`

O CMake utilizou explicitamente `fire4nix-toolchain.cmake` criado no build original e instalou em `DESTDIR` privado. Não utilizou bibliotecas `.so` do Ubuntu no pacote gerado nem modificou `/usr/lib` ou o console.

### Provas do log

- `ZLIB_TARGET_BUILD=PASS_REAL_ROCKNIX_AARCH64`
- `ELF_MACHINE=AArch64` e `Class=ELF64` confirmados com `readelf -h`.
- Requisito dinâmico máximo `GLIBC_2.17`, inferior ao limite `GLIBC_2.41`.
- Arquivo real `libz.so*` e `usr/lib/pkgconfig/zlib.pc` produzidos e auditados.
- `pkg-config --exists 'zlib >= 1.3.1'` com `PKG_CONFIG_LIBDIR` isolado passou.
- Artifact [Fire4Nix-RK3326-Zlib-REAL-TARGET-TEST-ONLY](https://github.com/Baltdh/Fire4nix/actions/runs/39539080424/artifacts/12318790888), ID **12318790888**.

### O que isso **não** demonstra

Apenas a dependência zlib foi compilada. O snapshot do toolchain contém uma estrutura de caminhos incorporados, portanto sua relocação para outro computador **não** foi validada; este workflow restaurou o caminho original no runner do GitHub. A biblioteca não foi executada no R36H, e não há WebCore, libWPEWebKit, browser ou renderização Mali/Wayland validados.

O sysroot do checkpoint inicial ainda carece dos metadados das 22 dependências WPE, conforme [auditoria da PR #52](https://github.com/Baltdh/Fire4nix/pull/52). O arquivo gerado de zlib fica em `DESTDIR` isolado; **isso não significa** que o sysroot completo ou a imagem ROCKNIX já inclua `zlib.pc`.

### Próxima etapa

Reproduzir o mesmo método para outras dependências do target (por exemplo libpng/libwebp/GLib/ICU/Wayland) e povoar sysroot controlado, preservando versões e hashes da receita ROCKNIX. Integrar os overlays `libsoup3`, `libtasn1`, `libpsl` e `glib-networking` definidos na PR #38 e validar seus cabeçalhos, arquivos `.pc` e ELFs. Somente então iniciar o CMake WPE 2.54.1 com `USE_GSTREAMER=OFF` e preparar primeiro teste offline físico no R36H.
