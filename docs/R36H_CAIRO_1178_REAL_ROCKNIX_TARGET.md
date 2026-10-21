# Fire4Nix: Cairo 1.17.8 compilado com dependências gráficas ROCKNIX AArch64

**Execução validada:** [GitHub Actions 39688962028 — SUCCESS](https://github.com/Baltdh/Fire4nix/actions/runs/39688962028), 21/10/2026.

## Fonte e receita efetiva

A árvore ROCKNIX 20260801 (commit `3b9cb1f6bf48ee9ca0cf01edd9af52ca2a6b73fb`) possui:
- `packages/graphics/cairo/package.mk`: versão genérica **1.18.4**.
- `projects/ROCKNIX/packages/graphics/cairo/package.mk`: versão efetiva do projeto **1.17.8**, com SHA256 **`5b10c8892d1b58d70d3f0ba5b47863a061262fa56b9dc7944161f8c8b783bc64`**.

O tarball original `cairo-1.17.8.tar.xz` veio de `https://cairographics.org/snapshots/` e passou na verificação SHA256 antes da extração. No código fonte extraído e temporário, o script aplica o ajuste exato do ROCKNIX para `ipc_rmid_deferred_release`; o arquivo comprimido original permanece intacto.

## SDK e fechamento de dependências

- GCC ROCKNIX RK3326 AArch64, host checkpoint aprovado em [39525819979](https://github.com/Baltdh/Fire4nix/actions/runs/39525819979).
- Fontconfig 2.17.1 e seu estágio-alvo aprovado em [39687860420](https://github.com/Baltdh/Fire4nix/actions/runs/39687860420), contendo FreeType, Pixman, Expat, GLib/GIO, PNG/zlib e dependências auxiliares necessárias.
- O script exige cabeçalhos, `pkg-config` e bibliotecas **AArch64** e rejeita bibliotecas hospedeiras x86_64 antes do Meson.

O perfil configurado é um **perfil mínimo de desenvolvimento WPE**, não a reprodução completa da receita `wl` do sistema. Fontconfig, FreeType, Pixman, PNG/zlib estão habilitados, enquanto Xlib/XCB e **a camada de interoperabilidade GObject/GLib do Cairo** estão desabilitados até completar a cadeia correspondente. O GLib alvo existe no stage, mas não se deve alegar que a biblioteca cairo-gobject foi validada. Isto não altera o caminho original de compilação do firmware ROCKNIX.

## Problemas resolvidos durante o trabalho

1. A opção `-Dlzo=disabled` é de Cairo mais novo e foi rejeitada pelo Meson da versão 1.17.8. Foi removida.
2. A primeira configuração cruzada apontava os includes GLib para o sysroot básico em vez do estágio privado de bibliotecas. Foi necessário ajustar o arquivo Meson cross e os include paths, sem copiar libs Ubuntu.
3. A camada `cairo-gobject` da configuração inicial exigia cabeçalho GLib ausente do caminho reconhecido; o perfil mínimo a desabilitou, preservando Cairo com Fontconfig e FreeType (decisão para teste, não comportamento final).
4. O consumidor de teste incluía `cairo-ft.h` sem o caminho do `fontconfig/fontconfig.h`; foi incluído explicitamente o diretório de cabeçalhos de Fontconfig alvo.

## Evidências finais do CI

```text
CAIRO_GLIBC=PASS_MAX_2_41
CAIRO_TARGET_BUILD=PASS_REAL_ROCKNIX_AARCH64
CAIRO_VERSION=1.17.8_ROCKNIX_PROJECT_EFFECTIVE
CAIRO_FONT_BACKENDS=FONTCONFIG_FREETYPE_ENABLED
CAIRO_PIXMAN=REAL_TARGET_0.46.2
CAIRO_WPE_MINIMAL_X11_PROFILE=DISABLED_XLIB_XCB_UNTIL_TARGET_LIBS
CAIRO_SOURCE_HASH=ORIGINAL_ROCKNIX_SHA256_VERIFIED
CAIRO_TARGET_CONSUMER_LINK=PASS_ELF64_AARCH64
TARGET_GLIBC_MAX=2.41
TARGET_EXECUTED=no
WPE_WEBKIT_BUILT=no
R36H_INSTALLABLE=no
```

Um consumidor C compartihado para AArch64 foi compilado e vinculado com `libcairo.so.2`, mas **não foi executado** no console nem no host x86_64.

[Artefato Cairo AArch64 e relatórios — expira em 04/11/2026](https://github.com/Baltdh/Fire4nix/actions/runs/39688962028/artifacts/12387831350).

## Passo seguinte

Compilar HarfBuzz 11.2.1 contra Cairo, FreeType e GLib reais (com atenção às flags específicas do ROCKNIX), então combinar o artefato ao estágio WPE e repetir o [configure CMake do WPE](https://github.com/Baltdh/Fire4nix/actions/runs/39684582460) para revelar a próxima dependência faltante. A etapa também exigirá revalidar Cairo com `-Dglib=enabled` e os componentes X11 se forem obrigatórios no runtime.

Não há navegador pronto, prova de HTTPS, renderização Mali/Wayland no R36H ou pacote instalável nesta etapa. Nenhuma modificação em firmware, SD ou `/usr/lib` do console.
