# Fire4Nix — preparação verificável do WPE 2.54.1 no ROCKNIX RK3326

**20 de outubro de 2026 — escopo: somente fontes, dependências e CI. Nenhum motor WebKit funcional foi compilado.**

## Fontes oficiais verificadas
- ROCKNIX: tag Git **`20260801`**, plataforma `RK3326`, variante `ARCH=aarch64`. Sua receita `packages/devel/glibc/package.mk` indica **GLIBC 2.41**, também observada no R36H real.
- WPE WebKit: release estável **2.54.1**, arquivo `wpewebkit-2.54.1.tar.xz` (**44,1 MiB**), SHA-256 `0de8bdfba011f9cd63ba9a9171fa6038dd2c08237894f4082abbb821f29d3fe9`, validado no GitHub Actions contra arquivo oficial.
- A tag WPE 2.54.1 possui as opções `USE_GSTREAMER`, `ENABLE_WPE_PLATFORM`, `ENABLE_WPE_PLATFORM_WAYLAND`, e exige `Soup3 >= 3.0.0`. Com `USE_GSTREAMER=OFF`, vídeo, WebAudio, WebCodecs e síntese de voz ficam desabilitados no perfil mínimo.
- O ROCKNIX oferece uma workflow oficial `.github/workflows/build-aarch64-toolchain.yml` que compila toolchain para `DEVICE=RK3326`. Não basta instalar compilador Ubuntu: os pacotes de desenvolvimento do sysroot devem ser compatíveis também.

## Inventário obtido contra a árvore REAL ROCKNIX 20260801

`sh rocknix-integration/audit-rocknix-rk3326-source.sh --check` encontra **18 receitas** e **4 ausentes**, na versão atual do auditor. Isto não certifica que as receitas existentes tenham versões compatíveis ou que estejam compiladas.

| Dependência ainda sem receita ROCKNIX | Papel | Fonte selecionada |
|---|---|---|
| `libsoup3` | HTTP/HTTPS e integração GLib exigidos pelo WPE | 3.6.5, GNOME |
| `libtasn1` | ASN.1 exigido pelo WPE | 4.21.0, GNU (correção de segurança posterior à 4.20.0) |
| `glib-networking` | Backend TLS do GIO utilizado pelo Soup3 em execução | 2.80.1, GNOME |
| `libpsl` | Public Suffix List exigida pelo Soup3 | 0.21.5, release upstream |

As URLs e seus SHA-256 estão em `rocknix-integration/rocknix-wpe-prerequisites.lock`. Executar `sh rocknix-integration/verify-wpe-prerequisite-sources.sh --download` baixa e confere quatro arquivos pequenos em diretório temporário; **não instala nem compila**.

**Atenção ao cross-build do libsoup3:** seu Meson `tls_check` usa `cc.run` para testar um backend TLS; isso é inadequado ao compilador cruzado. O código-fonte upstream admite `-Dtls_check=false` para empacotadores, mas isso **não elimina** a necessidade de portar `glib-networking` e distribuir corretamente os módulos TLS em tempo de execução. Jamais considerar HTTPS pronto por haver apenas `libsoup3.so`.

**Atenção ao libpsl:** versão deve compilar contra as bibliotecas IDN ou ICU disponíveis. O ROCKNIX 20260801 possui uma receita `icu` (74.1), que precisa ser testada na integração; ter um `package.mk` não prova compatibilidade.

## Pipeline novo: o que roda e o que NÃO roda

Arquivo: `.github/workflows/rocknix-wpe-source-prep.yml`.

1. Faz checkout fixo da tag ROCKNIX 20260801 e checa GLIBC/RK3326.
2. Roda regressões negativas de incompatibilidade de versão e de receitas faltantes.
3. Obtém o tarball WPE 2.54.1, valida SHA-256 oficial e compara as opções CMake presentes nele.
4. Audita/valida fontes das quatro dependências em um diretório temporário.
5. Publica um artefato **apenas de relatórios de texto**, com os bloqueios, sem navegador nem SDK.

A documentação oficial ROCKNIX estima **200 GB disponíveis** para a primeira compilação de um alvo e cerca de **10 horas**, portanto compilar o sistema completo em um runner GitHub comum não é uma promessa realista. O pipeline de fontes foi separado da construção pesada de propósito.

## Próximas mudanças de desenvolvimento (ordem de dependências)

1. Portar/validar as quatro receitas faltantes do ROCKNIX; auditar as transitivas e o `glib-networking` em `usr/lib/gio/modules`, com certificados CA disponíveis para HTTPS.
2. Produzir ou reaproveitar toolchain/sysroot **do mesmo release ROCKNIX**, validar glibc 2.41, compiladores C/C++ aarch64 e versões das bibliotecas. O script `check-rocknix-sdk.sh` bloqueia glibc incompatível.
3. `build-wpe-2.54.1.sh --configure`: exigir `-DUSE_GSTREAMER=OFF` e verificar o `CMakeCache.txt` efetivo usando `verify-wpe-media-cache.sh`.
4. `--build`, `--stage` com `DESTDIR` isolado. O stager deve bloquear `DT_NEEDED libgst*`, ELF que não seja AArch64, GLIBC acima de 2.41 e subprocessos/recursos ausentes.
5. Criar ZIP separado e instalar apenas em `/storage` (ext4 interno). Testar primeiro renderização offline no Wayland, depois controles, memória e HTTPS. **Não alterar firmware ou `/usr/lib`**.

## Referências

- https://rocknix.org/contribute/build/
- https://github.com/ROCKNIX/distribution/tree/20260801
- https://github.com/ROCKNIX/distribution/blob/20260801/.github/workflows/build-aarch64-toolchain.yml
- https://wpewebkit.org/release/wpewebkit-2.54.1.html
- https://github.com/GNOME/libsoup/blob/3.6.5/meson_options.txt
- https://download.gnome.org/sources/libsoup/3.6/libsoup-3.6.5.sha256sum
- https://download.gnome.org/sources/glib-networking/2.80/glib-networking-2.80.1.sha256sum
- https://lists.gnu.org/archive/html/info-gnu/2026-01/msg00003.html
- https://github.com/buildroot/buildroot/blob/2025.08/package/libpsl/libpsl.hash
