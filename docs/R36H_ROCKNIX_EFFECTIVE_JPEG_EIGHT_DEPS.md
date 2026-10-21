# Fire4Nix — libjpeg-turbo efetiva e oitava dependência ROCKNIX AArch64

## Verificação real de 21/10/2026

**[GitHub Actions 39683307528 — SUCCESS](https://github.com/Baltdh/Fire4nix/actions/runs/39683307528)**: compilação cruzada de `libjpeg-turbo 3.0.1` usando o GCC/GLIBC do SDK ROCKNIX 20260801 (RK3326, AArch64) e integração com o estágio de sete componentes testados previamente ([run 39682062894](https://github.com/Baltdh/Fire4nix/actions/runs/39682062894)).

### Por que 3.0.1 e não 3.1.1?

O repositório upstream ROCKNIX fixado no commit `3b9cb1f6bf48ee9ca0cf01edd9af52ca2a6b73fb` contém duas receitas:

- `packages/graphics/libjpeg-turbo/package.mk`: receita genérica `PKG_VERSION="3.1.1"`, bibliotecas estáticas.
- `projects/ROCKNIX/packages/graphics/libjpeg-turbo/package.mk`: versão específica `PKG_VERSION="3.0.1"`, `ENABLE_STATIC=ON`, `ENABLE_SHARED=ON`, `WITH_JPEG8=ON`, e SIMD quando houver NEON/SSE.

A fonte foi obtida diretamente do repositório oficial `libjpeg-turbo/libjpeg-turbo`, com checkout no commit **`ec32420f6b5dfa4e86883d42b209e8371e55aeb5`** correspondente à tag `3.0.1`. Ambos os hashes (ROCKNIX e libjpeg-turbo) são testados antes da configuração. Diferentemente da receita genérica, o override da versão 3.0.1 não oferece SHA-256 do arquivo tar; por isso este teste usa o commit Git imutável, não um arquivo de origem com digest inventado.

### Compilação e segurança de caminhos

O workflow `.github/workflows/r36h-rocknix-eight-deps-jpeg.yml` usa o SDK do [run 39525819979](https://github.com/Baltdh/Fire4nix/actions/runs/39525819979) e os arquivos compilados do [run 39682062894](https://github.com/Baltdh/Fire4nix/actions/runs/39682062894).

O primeiro [run 39683001177](https://github.com/Baltdh/Fire4nix/actions/runs/39683001177) **compilou os arquivos JPEG**, mas o CMake próprio do projeto normalizou um `CMAKE_INSTALL_LIBDIR` relativo como caminho de workspace absoluto. O diretório `DESTDIR/usr/lib` permaneceu vazio. Corrigimos com `-DCMAKE_INSTALL_LIBDIR=/usr/lib` e exigimos esse valor no cache CMake. Nenhum arquivo é instalado no sistema do runner ou console: o install ocorre apenas em `DESTDIR` privado.

A configuração aprovada registrou:

```text
CMAKE_INSTALL_LIBDIR = /usr/lib
Emulating libjpeg API/ABI v8.0 (WITH_JPEG7 = 0, WITH_JPEG8 = 1)
SIMD extensions: arm64 (WITH_SIMD = 1)
```

A verificação em `scripts/verify-rocknix-eight-deps-jpeg.sh` detecta ELF64/AArch64, SONAME, requisitos GLIBC, arquivos `.pc` e cabeçalhos. Recusa sobrescrever arquivos com conteúdo diferente e rejeita links simbólicos externos durante a composição do estágio com bibliotecas anteriores.

### Evidências da aprovação

```text
JPEG_GLIBC_ABI=PASS_MAX_2_41
EIGHT_TARGET_FILES_COPIED=398
JPEG_SONAME=libjpeg.so.8
EIGHT_CONSUMER_GLIBC=PASS_MAX_2_41
JPEG_VERSION=3.0.1_ROCKNIX_PROJECT_EFFECTIVE
JPEG_TARGET_ELF=PASS_AARCH64
EIGHT_TARGET_STAGE=PASS_REAL_ROCKNIX_AARCH64
EIGHT_TARGET_CONSUMER_LINK=PASS_JPEG_GIO_GLIB_PNG_ZLIB_SQLITE_LIBTASN1
JPEG_SIMD_CONFIGURATION=ON_NEON_TARGET_TEST
TARGET_EXECUTED=no
R36H_INSTALLABLE=no
```

O consumidor `libeight-consumer.so`, com `-Wl,-z,defs`, liga libjpeg v8 com GLib/GIO, PNG/zlib, SQLite e libtasn1 para o alvo ROCKNIX. **O código ARM64 não foi executado**; nem SIMD/NEON nem aceleração gráfica do console foram exercitados fisicamente.

[Artefato de desenvolvimento (expira 04/11/2026)](https://github.com/Baltdh/Fire4nix/actions/runs/39683307528/artifacts/12385222174) inclui biblioteca JPEG, cabeçalhos, metadados `pkg-config`, estágio integrado e relatório ELF.

### Limites e próximo trabalho

- Nenhuma mudança no firmware, cartão SD, `/usr/lib` ou rootfs do R36H.
- O estágio de oito componentes **não é navegador instalável**; WPE WebKit, EGL/Wayland/Mali, HTTPS e fechamento completo das dependências ainda não foram comprovados.
- GLib/GIO neste estágio não demonstra automaticamente a presença de `glib-networking`, GnuTLS ou certificados CA.
- Continuar integração dos componentes já em desenvolvimento em paralelo nas PRs #68 (libxml2), #69 (libwebp) e #71 (libxslt) antes de tentar um configure CMake completo do WPE 2.54.1 com `USE_GSTREAMER=OFF`.
