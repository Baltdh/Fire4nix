# Fire4Nix 1.20 — Portão para o PRIMEIRO teste gráfico real no R36H

## Testes realizados e limites reais

1. **Fontes:** ROCKNIX 20260801 (RK3326/AArch64, GLIBC 2.41) e WPE WebKit 2.54.1 confirmados.
2. **Quatro receitas:** libsoup3 3.6.5, libtasn1 4.21.0, glib-networking 2.80.1 e libpsl 0.21.5 aplicadas numa árvore de fontes **descartável**, sem compilar SDK ROCKNIX.
3. **Build real de dependências:** em Ubuntu 24.04 ARM64 nativo, as quatro bibliotecas foram compiladas a partir das fontes de hashes fixos. Objeto `libgiognutls.so` e `libsoup-3.0.so.0` realmente gerados. Um programa C independente instanciou `SoupSession` e verificou `g_tls_backend_supports_tls()`: **PASS sem rede**. ELF AArch64, requisitos GLIBC individuais no máximo 2.41. Esse build **não é um pacote ROCKNIX**: dependências transitivas e opções do SDK diferem.
4. **Configuração real WPE 2.54.1:** `scripts/configure-aarch64-wpe-2541-smoke.sh` usa CMake/Ninja num runner nativo ARM64, GStreamer OFF, WebAudio/vídeo/WebRTC OFF, API Wayland ON, módulos opcionais da primeira versão desativados. `CMakeCache.txt` precisa passar por `verify-wpe-media-cache.sh`. Isto ainda **não compila** o motor nem gera navegador executável.
5. **Artefato de primeiro teste:** `installer/www/primeiro-teste-r36h.html` é autocontido, sem URLs remotas, sem armazenamento e usa 640 × 480. O teste estático garante presença de HTML/CSS/JS, botão e teclado, mas **não simula pixels no hardware**. O CI `r36h-first-frame-fixture.yml` e a receita `r36h-oneinstall.yml` verificam/empacotam a página.

## Critérios de conclusão do futuro teste físico (não executado)

Executar somente **quando um WPE novo compilado com o SDK ROCKNIX tiver passado pela auditoria estática**:

- Iniciar a partir do ambiente gráfico/Ports/Wayland do R36H, mantendo biblioteca antiga de resgate em quarentena, sem sobrescrever `/usr/lib` ou gravar no SD externo exFAT.
- Abrir a página **offline** `file://...` dentro do pacote novo, sem acessar internet e sem senha HTTP.
- Observar **quatro faixas coloridas**, texto `JS_OK`, `FRAME_OK`; o último indica callback de animação, mas somente **ver a tela** confirma pixels reais.
- Pressionar o botão/Enter (ou A mapeado) e observar `Pressionamentos: 1`. Verificar `Ultima tecla` ao pressionar botões.
- Confirmar que launcher registra encerramento limpo sem `Segmentation fault (139)`; testar novamente após reabrir.
- Só depois testar fontes, memória, teclado e HTTPS com certificados e backend GIO/TLS comprovados. Não liberar navegação insegura com sandbox desligado nem com execução como root.

## O próximo bloqueio mais importante

O **sysroot oficial de desenvolvimento do ROCKNIX 20260801** ainda não foi efetivamente construído para este projeto. O primeiro build nativo Ubuntu é uma prova das fontes, não substitui esse sysroot. O WPE ainda precisa de um build ARM64 completo, `DT_NEEDED` sem bibliotecas GStreamer, `GLIBC <= 2.41`, subprocessos, recursos do WebKit, integração WPEPlatform e prova visual em R36H. Não disponibilizar ZIP como navegador funcional enquanto isso não ocorrer.

## Ferramentas e CIs
- `.github/workflows/r36h-first-real-arm64-deps.yml` — compila as quatro bibliotecas reais, testa TLS offline e tenta configurar WPE CMake (Ubuntu ARM64, nunca aparelho).
- `.github/workflows/r36h-first-frame-fixture.yml` — verifica que HTML de aceitação é autocontido.
- `rocknix-integration/build-wpe-2.54.1.sh` — futura compilação direcionada ao SDK ROCKNIX.
- `rocknix-integration/stage-wpe-runtime.sh` — futura auditoria e empacotamento de runtime completo.
