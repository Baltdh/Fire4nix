# Fire4Nix R36H 1.07 — estudo aprofundado de causa raiz

Data de revisão: 18/10/2026. Este documento separa **achados nos arquivos**, **fontes oficiais** e **hipóteses**. O navegador WPE ainda não foi demonstrado em hardware físico.

## Achados verificados nos artefatos do projeto

- Em `Fire4Nix_consolidated_latest_real_backup_beta_test_ready_v2.zip`, o arquivo `Fire4Nix/fire4nix` tem cabeçalho ELF **x86-64** (interpreter `/lib64/ld-linux-x86-64.so.2`). Não é binário utilizável no R36H AArch64.
- A maioria das grandes bibliotecas gráficas desse backup fica em `rocknix_reference/runtime-libs/armhf/lib32-snapshot/`. São referências de **32 bits** e não podem ser diretamente carregadas pelo ELF de 64 bits.
- O backup não contém `libWPEWebKit-2.0.so.1` compilada. O código-fonte `wpewebkit-2.52.5.tar.xz` não substitui a biblioteca compilada.
- O ELF de `Fire4Nix-R36H-1.06-Tracar-139-Ports.zip` é **AArch64** e exige diretamente até **GLIBC_2.34**. Isso não garante os requisitos transitivos de GLib, EGL ou WebKit.
- O `swap.conf` fornecido define `ZRAM_SIZE=0`, `SWAP_FILE_SIZE=0`. Não há comprovação de que esse arquivo corresponde à configuração efetivamente ativa. Um déficit de memória após abrir páginas é diferente de SIGSEGV durante pré-teste `dlopen`.

## Fontes oficiais versus inferência

1. [WPEPlatform — API nova](https://wpewebkit.org/blog/2026-10-06-wpe-platform.html): desde 2.54, `WPE_PLATFORM=wayland` seleciona o backend integrado; legado libwpe/fdo é descontinuado e Cog 0.18.x não terá novas versões estáveis.
2. [WPE WebKit 2.54.1](https://wpewebkit.org/release/wpewebkit-2.54.1.html): corrigiu build do WPEPlatform/Wayland com `libwayland-client >= 1.25`; [bug 324760](https://bugs.webkit.org/show_bug.cgi?id=324760) mostra que a falha era **de compilação** de `wl_pointer_listener::warp`, não prova de correção de nosso SIGSEGV no `dlopen`.
3. [Bug 324726](https://bugs.webkit.org/show_bug.cgi?id=324726): WPE_DISPLAY legado com `WPE_PLATFORM` ausente pode gerar abort por RELEASE_ASSERT; o Fire4Nix atual define WPE_PLATFORM, portanto não pode ser atribuído ao nosso 139 sem logs.
4. [Issue de EGL/surfaceless](https://github.com/WebPlatformForEmbedded/WPEWebKit/issues/1674): discussão sobre WPEPlatform exigir caminhos de renderização EGL sem superfície ou GBM. Pode se tornar relevante ao criar a janela, **não** no pré-teste de símbolos.
5. [ROCKNIX tag 20261001 — glibc](https://github.com/ROCKNIX/distribution/blob/20261001/packages/devel/glibc/package.mk) declara 2.44, enquanto registros anteriores do dispositivo indicavam 2.41. Isso exige verificar o **sistema físico** antes de cruzar dependências.

## Matriz orientada por sintomas

| Etapa | Resultado | Hipótese principal | Teste sem alterações no firmware |
|---|---|---|---|
| 0. ELF | `Exec format error`, 126/127 | Arquitetura errada ou permissões | `readelf -h`, `file`; checar ELF AArch64 |
| 1. Loader | `--check-library` dá 139 antes de `dlopen success` | Construtor estático, relocação, dependência transitiva incompatível ou `LD_PRELOAD` | `LD_DEBUG=libs,versions,files`; gdb/strace se já disponíveis; não usar configuração invasiva |
| 2. API | `--check-library` retorna 0, `--check-platform` 78 | Runtime legado sem `webkit_web_view_get_wpe_view` | `readelf -Ws` e saída `[FIRE4NIX-ABI]` |
| 3. Inicialização | `--check-platform` 0, mas `--headless` falha | Problema ao criar WebKitWebView/subprocessos, fonte/MIME/sandbox | log de estágios nativos, subprocessos e fontes |
| 4. Wayland | headless passa; `--smoke` em Wayland falha | Sway socket, EGL/GBM, driver Mali, compositor/Skia | `WPE_PLATFORM=wayland`, verificar socket e `WAYLAND_DEBUG` em ensaio controlado |
| 5. HTML | Janela abre mas conteúdo falha | Banco MIME, fontes, HTML local/recursos, processos WebKit | carregar somente `file:///.../inicio.html` |
| 6. HTTPS | Offline passa; rede falha | DNS, TLS, certificados ou hora do sistema | Testar uma URL HTTPS conhecida, coletar erro do WebKit |
| 7. Estabilidade | página abre, depois fecha | OOM, renderizador encerrado, GPU process ou GStreamer | `/proc/meminfo`, logs de subprocessos, rodar recursos mínimos |

Código 139 = SIGSEGV; em um Linux típico, OOM killer produz SIGKILL/137, mas outros efeitos de memória ou bugs podem causar SIGSEGV. **Não atribuir falha ao Mali ou Wi-Fi somente pelo número 139.**

## Por que o estudo muda o coletor

A partir de 1.07, `Fire4Nix-Investigar-139.sh` procura **independentemente**:

- `bin/fire4nix-native-aarch64` no pacote/Ports.
- `runtime/lib/libWPEWebKit-2.0.so.1` no SD interno, externo ou pasta tools.

O pacote anterior exigia ambos na mesma pasta. A mudança não copia o WebKit de 174 MB nem instala drivers. Variáveis para teste: `FIRE4NIX_BINARY_ROOT` e `FIRE4NIX_RUNTIME_ROOT`. O pré-teste ainda não é um teste gráfico.

## Critérios de conclusão

1. Arquiteturas AArch64 e versão real de todas as bibliotecas identificadas.
2. `--check-library` e `--check-platform` retornam 0 com runtime **real**, não mock.
3. `--headless` carrega uma página sem SIGSEGV.
4. `--smoke` cria WPEView em Wayland, recebe evento `load-event=3`, e alguém verifica a **janela visível no R36H**.
5. Página HTTPS abre com certificados corretos, controles funcionam, monitorar 10–20 minutos sem encerramento abrupto.
6. Empacotamento por SD/Ports inicia de qualquer localização suportada sem modificar firmware.

**Próximo dado prioritário:** `/storage/Fire4Nix-Investigacao-139/Fire4Nix-139-ultimo.txt` do R36H real obtido com `Fire4Nix-Tracar-139.sh`, contendo `crash_boundary` e `native_preflight_exit`.
