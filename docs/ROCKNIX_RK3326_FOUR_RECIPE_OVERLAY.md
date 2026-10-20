# Fire4Nix 1.19 — quatro receitas ROCKNIX preparadas, motor WebKit ainda pendente

## O que foi de fato produzido

O overlay de **código-fonte** está em `rocknix-integration/rocknix-overlay/packages/`:

| Receita | Pasta relativa no overlay | Fonte travada por SHA-256 |
|---|---|---|
| libtasn1 4.21.0 | `security/libtasn1/package.mk` | GNU tar.gz |
| libpsl 0.21.5 | `network/libpsl/package.mk` | upstream tar.gz |
| glib-networking 2.80.1 | `network/glib-networking/package.mk` | GNOME tar.xz |
| libsoup3 3.6.5 | `web/libsoup3/package.mk` | GNOME tar.xz |

A lista de hashes/URLs foi validada em uma execução anterior da GitHub Actions e permanece em `rocknix-integration/rocknix-wpe-prerequisites.lock`.

O ROCKNIX 20260801 **não** contém essas quatro receitas nos caminhos esperados. A nova rotina `apply-rocknix-wpe-overlay.sh` copia as receitas a uma **árvore de build descartável**, exige consentimento explícito `FIRE4NIX_OVERLAY_ALLOW_APPLY=1`, recusa substituição de receitas upstream e rejeita caminhos de sistema/firmware e armazenamento removível.

## Como validar no host de desenvolvimento (NÃO no console)

O exemplo pressupõe que `/home/runner/work/rocknix-20260801` é um checkout limpo da tag oficial `20260801`, ou seja, ambiente descartável de CI:

```sh
export FIRE4NIX_ROCKNIX_SOURCE=/home/runner/work/rocknix-20260801
sh rocknix-integration/verify-rocknix-wpe-overlay.sh
sh rocknix-integration/apply-rocknix-wpe-overlay.sh --check
FIRE4NIX_OVERLAY_ALLOW_APPLY=1 sh rocknix-integration/apply-rocknix-wpe-overlay.sh --apply
```

A última etapa exibe `missing_required_recipes=0` e `OVERLAY_APPLIED=FOUR_SOURCE_RECIPES_NOT_BUILT`. **Ela não executa compilação**, instala pacotes, escreve no cartão SD ou atualiza o ROCKNIX da máquina portátil.

## Decisões técnicas que evitam os erros anteriores

1. O arquivo upstream `libsoup-3.6.5.tar.xz` descompacta em `libsoup-3.6.5/`, mas a receita se chama `libsoup3`. `PKG_SOURCE_DIR="libsoup-${PKG_VERSION}"` evita gerar uma pasta vazia no `scripts/unpack` do ROCKNIX.
2. A verificação TLS no configure do libsoup3 usa `cc.run()`, inviável em cross-compilação AArch64 pura. A receita usa `-Dtls_check=false` **somente para esse teste de compilação**, não para desligar TLS.
3. `glib-networking` continua com `-Dgnutls=enabled` (backend GIO obrigatório). Desativa `libproxy` e `gnome_proxy` — dependências desktop ausentes no dispositivo. É preciso manter e testar o módulo GIO `libgiognutls.so` no runtime final.
4. `libpsl` usa `-Druntime=libicu` e a receita `icu` já presente no ROCKNIX para evitar dependências adicionais de libidn2 e libunistring. Compatibilidade real de runtime depende da futura compilação.
5. Os `PKG_SHA256` das quatro receitas são comparados byte a byte com o manifesto. As opções TLS e a configuração de diretório da Soup também possuem testes de regressão que falham diante de alterações inseguras.

## O que falta para um WebKit executável

Estas receitas ainda precisam passar **pela compilação contra o toolchain/sysroot exato de ROCKNIX 20260801, GLIBC 2.41**. Os próximos testes exigirão:

- `scripts/build_mt` ou sistema equivalente oficial executando os pacotes no host de build;
- verificação da árvore de desenvolvimento com `libsoup-3.0.so.0`, `libpsl.so.5`, `libtasn1.so.6`, e módulo `gio/modules/libgiognutls.so`;
- suporte HTTPS real com certificados CA (ainda não testado no hardware);
- configuração WPE 2.54.1 `USE_GSTREAMER=OFF`, verificação das flags **no CMakeCache** e dos `DT_NEEDED` **nos arquivos finais**;
- testes de renderização Wayland, HTML offline, HTTPS, controles e memória no R36H.

**Estado atual: receitas de build preparadas e verificadas estaticamente; dependências reais não compiladas; WPE WebKit ainda não compilado; navegador ainda sem funcionamento confirmado no R36H.**

Não substitua a instalação antiga ou bibliotecas de `/usr/lib` no console. A versão recuperada anteriormente continua um backup para investigação.
