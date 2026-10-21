# WPE 2.54.1 / ROCKNIX RK3326 — HarfBuzz-ICU detectado, próximo bloqueio LibGcrypt

Teste GitHub Actions **39693723425 — SUCCESS como diagnóstico**, em 21 de outubro de 2026. O CMake em si terminou com código **1** (erro de dependência), como esperado para esta etapa.

O WebKit WPE 2.54.1, baixado com SHA-256 original, foi configurado sem GStreamer (`USE_GSTREAMER=OFF`), usando o compilador do SDK ROCKNIX RK3326 AArch64 (`3b9cb1f6bf48ee9ca0cf01edd9af52ca2a6b73fb`, GLIBC 2.41). Antes do CMake, foi montada uma árvore `DESTDIR` temporária a partir dos seguintes artefatos CI comprovadamente aprovados: oito bibliotecas 39683307528; Fontconfig/FreeType 39687860420; Cairo 39688962028; ICU 74.1 39688837904; HarfBuzz 11.2.1 **com componente ICU** 39692709765; libglvnd EGL/GLES2 39692039643; libepoxy 1.5.10 39692741218.

O estágio rejeita sobreposição de conteúdo divergente, symlinks externos, headers e bibliotecas ausentes, e objetos não ELF64/AArch64. CMake recebe os caminhos explícitos do target `HarfBuzz_ICU_LIBRARY`, `ICU_*_LIBRARY` e `Epoxy_LIBRARY`.

## Resultado comprovado

```text
TARGET_PC_harfbuzz=11.2.1
TARGET_PC_harfbuzz-icu=11.2.1
TARGET_PC_icu-uc=74.1
TARGET_PC_icu-i18n=74.1
TARGET_PC_epoxy=1.5.10
TARGET_PC_egl=1.5
TARGET_PC_glesv2=3.2
WPE_CMAKE_EXIT_CODE=1
HARFBUZZ_ICU_FIRST_BLOCKER_CLEARED=YES
WPE_TARGET_CONFIGURE=BLOCKED_WITH_REAL_SDK
```

Primeiro erro CMake após avançar sobre HarfBuzz-ICU:

```text
Could NOT find LibGcrypt (missing: LibGcrypt_LIBRARY LibGcrypt_INCLUDE_DIR
LibGcrypt_GpgError_LIBRARY LibGcrypt_GpgError_INCLUDE_DIR)
(found suitable version "1.9.4", minimum required is "1.7.0")
Source/cmake/FindLibGcrypt.cmake:115
Source/cmake/OptionsWPE.cmake:17
```

**A menção de versão 1.9.4 não comprova uma biblioteca alvo utilizável** — o CMake declara ausentes as bibliotecas e cabeçalhos de desenvolvimento. O `FindLibGcrypt.cmake` do WebKit exige tanto `libgcrypt` quanto `libgpg-error` e aceita `libgcrypt.pc` e `gpg-error.pc`. No ROCKNIX base 20260801, receitas **libgcrypt 1.11.1** e **libgpg-error 1.55**; a receita de projeto para libgpg-error habilita a versão compartilhada em vez da estática da receita genérica.

[GitHub Actions 39693723425](https://github.com/Baltdh/Fire4nix/actions/runs/39693723425) | [diagnóstico para download](https://github.com/Baltdh/Fire4nix/actions/runs/39693723425/artifacts/12390351114)

## Critérios seguintes

Compilar as duas bibliotecas com GCC do ROCKNIX e SHA-256 original, verificar os quatro parâmetros exigidos pelo CMake (`LibGcrypt_LIBRARY`, `LibGcrypt_INCLUDE_DIR`, `LibGcrypt_GpgError_LIBRARY`, `LibGcrypt_GpgError_INCLUDE_DIR`), repetir o CMake sem encobrir erros com bibliotecas Ubuntu. Ainda faltam dependências posteriores (Soup3, Tasn1, XkbCommon, XML, WebP, entre outras) cuja presença real deve ser testada antes de afirmar sucesso.

**Não foram compilados WebKit completo ou navegador; nenhuma execução no R36H, nenhum teste Wayland/Mali ou HTTPS, nenhuma modificação do firmware.**
