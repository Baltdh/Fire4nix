# Fire4Nix — FreeType 2.13.3 AArch64: próximo passo concreto para HarfBuzz

## Resultado aprovado em 21/10/2026

[GitHub Actions 39685435460 — SUCCESS](https://github.com/Baltdh/Fire4nix/actions/runs/39685435460) compilou **FreeType 2.13.3** contra as bibliotecas genuínas zlib 1.3.1 e libpng 1.6.40 do estágio AArch64 ROCKNIX RK3326, com o GCC real restaurado do SDK 20260801. Não usou as versões do host Ubuntu.

O código-fonte é o lançamento upstream `freetype-2.13.3.tar.xz`, validado pelo SHA256 original da receita ROCKNIX:

```text
0550350666d427c74daeb85d5ac7bb353acba5f76956395995311a9c6f063289
```

A compilação usou configuração cruzada Autotools, com PNG e zlib do *target* obrigatórios e HarfBuzz/Brotli/BZip2 opcionais desativados. Esse ciclo é necessário: FreeType é um pré-requisito do HarfBuzz, não deve depender de HarfBuzz para começar a compilação da cadeia.

### Evidências dos artefatos e ABI

```text
FREETYPE_GLIBC=PASS_MAX_2_41
FREETYPE_VERSION=2.13.3_ROCKNIX
FREETYPE_SOURCE=PASS_ORIGINAL_ROCKNIX_SHA256
FREETYPE_BUILD=PASS_REAL_ROCKNIX_AARCH64
FREETYPE_TARGET_NEEDED=libpng16.so.16,libz.so.1
FREETYPE_CONSUMER_LINK=PASS_ELF64_AARCH64
FREETYPE_TARGET_GLIBC_MAX=2.41
TARGET_EXECUTED=no
R36H_INSTALLABLE=no
```

Foram confirmados `libfreetype.so.6` ELF64 AArch64, os vínculos dinâmicos a PNG/zlib do alvo, o arquivo `freetype2.pc`, headers `ft2build.h` e um consumidor AArch64 real vinculado com `-Wl,-z,defs`, mas **não executado**.

[Artefato dos resultados FreeType, apenas para desenvolvimento (expira em 04/11/2026)](https://github.com/Baltdh/Fire4nix/actions/runs/39685435460/artifacts/12385976708).

## Relação com o bloqueio WPE

O [diagnóstico WPE WebKit 2.54.1 em SDK real](https://github.com/Baltdh/Fire4nix/actions/runs/39684582460) falhou no primeiro bloqueio em `FindHarfBuzz.cmake` — HarfBuzz 2.7.4+ não foi reconhecido no estágio. A receita ROCKNIX utiliza **HarfBuzz 11.2.1**, que depende de **FreeType, Cairo e GLib**.

Este build resolve e testa **FreeType**, uma peça necessária, mas não remove sozinho o bloqueio HarfBuzz. Resta construir Cairo, depois HarfBuzz com a receita ROCKNIX, reunir os arquivos de desenvolvimento no mesmo estágio e reexecutar o CMake do WPE.

**Não é navegador compilado ou instalável**, não escreve firmware, cartão SD nem `/usr/lib` do console. SIMD, font rendering e carregamento ELF no R36H ainda não foram executados fisicamente.
