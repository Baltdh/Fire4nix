# Fire4Nix — Primeiro build JavaScriptCore real (PR #42)

## Escopo exato

O WebKit tem camadas distintas: WPEPlatform (Wayland/headless), JavaScriptCore (motor JavaScript), WebCore (DOM/HTML/CSS), processos WPE e inicializador. Os **54 objetos WPEPlatform** compilados anteriormente são código real mas **não** incluem o browser final.

Esta PR prepara **compilação e execução real do JavaScriptCore** da mesma release `wpewebkit-2.54.1` em **runner Ubuntu ARM64 nativo**, usando a mesma árvore CMake WPE que já foi configurada com `USE_GSTREAMER=OFF`.

### Teste executado no CI

A workflow `.github/workflows/r36h-first-real-arm64-deps.yml` agora:

1. Compila `libtasn1`, `libpsl`, `glib-networking` e `libsoup3`, valida ELF AArch64 e suporte GIO TLS local (sem rede).
2. Configura código-fonte WPE WebKit 2.54.1 e verifica o **CMakeCache** mínimo sem GStreamer.
3. Compila 54 objetos WPEPlatform reais (Wayland/headless/core).
4. Tenta `cmake --build ... --target jsc --parallel 2` com limite de 35 minutos; não constrói WebCore completo.
5. Verifica ELF AArch64 de `jsc` e da biblioteca `libJavaScriptCore`, exige dependência GLIBC **no máximo 2.41** nesses arquivos (inspeção de símbolos, não prova toda ABI transitiva).
6. Executa `native/tests/jsc-webkit-runtime-smoke.js` pelo interpretador construído, conferindo arrays, matemática, JSON e BigInt, sem acesso à rede.
7. Salva logs e relatório `JSC-AARCH64-EXECUTION.txt`. Em falha, arquivo `jsc-build.log` ou `jsc-run.txt` indica o primeiro erro.

### Critérios de sucesso

Somente declarar que **JavaScriptCore real em Ubuntu ARM64 funciona** quando a execução concluir SUCCESS e o relatório contiver:

```text
JSC_AARCH64_BUILD=COMPLETED
JSC_ELF=AARCH64
JSC_RUNTIME=PASS
JSC_SMOKE=PASS_REAL_ENGINE_AND_JSC_EXECUTABLE
JSC_TARGET=ELF64_AARCH64
CMAKE_GSTREAMER=OFF
ROCKNIX_SYSROOT_USED=no
R36H_INSTALLABLE=no
```

Resultado diferente é bloqueio a investigar, não evidência de sucesso.

### Integração com outro agente

- **PR #40** executa compilador/sistema alvo **ROCKNIX 20260801, RK3326, GLIBC 2.41**. Esta PR **não** altera seus scripts `scripts/build-rocknix-rk3326-toolchain.sh` ou `.github/workflows/rocknix-rk3326-toolchain.yml`.
- O progresso de JSC Ubuntu ARM64 **não autoriza** instalar nenhuma destas bibliotecas no console.
- Após SDK real, reproduzir configuração minimalista com compilador/sysroot ROCKNIX e eventualmente compilar JSC e WebKit completos; auditar `DT_NEEDED`, `libgst*`, ELF/GLIBC/subprocessos, certificados TLS e Wayland.
- Primeiro teste real do navegador gráfico somente com o runtime WPE completo, em pasta isolada no **ext4 interno**, carregando `file://...` para `installer/www/primeiro-teste-r36h.html`; observar cores e `JS_OK` / `FRAME_OK` no display e testar botão A/Enter. Nada de substituir firmware nem `/usr/lib` ou gravar no exFAT externo.

**Importante:** a compilação do JavaScriptCore pode ser grande e exceder CPU/memória da CI; não contornar falha ignorando o código de saída, não chamar CMake configure de compilação do motor.
