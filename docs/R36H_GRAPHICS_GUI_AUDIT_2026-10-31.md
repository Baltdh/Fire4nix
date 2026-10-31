# Fire4Nix R36H — auditoria gráfica e integração da interface (31/10/2026)

## Escopo

Alvo: R36H / RK3326 / AArch64 / ROCKNIX, painel lógico 640×480. Este documento separa o que foi verificado no código e nos logs do que ainda depende de teste físico.

## Estado comprovado no repositório

### Caminho ativo do navegador

- `native/fire4nix_wpeplatform.cpp` é o launcher nativo WPEPlatform. Ele carrega a biblioteca WPE, consulta a API WPEPlatform, cria o WebKitWebView/WPEView, obtém o toplevel e executa o loop GLib.
- O launcher recebe `WPE_PLATFORM=wayland`; a integração com Wayland não depende do shell SDL antigo.
- `installer/www/inicio.html` é a página inicial visual do produto: endereço/pesquisa, atalhos, teclado virtual e CSS responsivo.
- O novo modo `--verify-home` testa essa página no próprio WPE: campo de endereço, submit sem navegação, teclado virtual, atalhos, CSS, viewport e foco por setas.
- O teste `--verify-offline` verifica DOM, JavaScript, CSS computado e evento de clique.
- A correção de HTML local usa `webkit_web_view_load_html()` para evitar depender da associação MIME `text/html` do sistema; a URI `file://` original é mantida como base para recursos relativos.

### Interface C++ anterior

- `source_r36h/Fire4Nix/src/gui/browser_bridge.cpp`: o `ShellBrowserBridge` atual registra comandos em um journal e retorna sucesso; não encaminha esses comandos ao WPE.
- `source_r36h/Fire4Nix/src/gui/gui_services.cpp`: `initialize()` apenas ativa o serviço e zera o acumulador de tempo.
- `source_r36h/Fire4Nix/src/fire4nix_framebuffer.cpp`: contém somente o scaffold de migração framebuffer/SHM.

Conclusão: essa camada C++ ainda não é a interface operacional do browser. Não se deve afirmar que `BrowserBridge`, `GuiServices` ou o framebuffer já controlam a página WPE.

## Pilha gráfica que deve permanecer sob controle do ROCKNIX

`Fire4Nix UI (HTML/CSS/JS) → WPE WebKit → WPEPlatform Wayland → Sway → EGL/GLES → Mali → painel`

O aplicativo não deve carregar cópias privadas de `libEGL`, `libGLESv2`, `libmali`, `libdrm`, `libgbm`, `libwayland-client`, `libc` ou do loader do sistema sem um motivo comprovado. A pilha gráfica e as bibliotecas de plataforma devem ser fornecidas pelo ROCKNIX; o runtime privado deve conter apenas a closure WPE necessária e auditada.

## Evidência específica do R36H

O relatório de 23/10/2026 registra:

- Mali userspace g29p1; `/dev/mali0` e `/dev/dri/card0` presentes; render node `renderD*` não confirmado.
- Extensões EGL anunciam Wayland e GBM; `EGL_MESA_platform_surfaceless` não foi anunciado.
- Com `MALI_DEFAULT_DISPLAY=wayland` e socket Wayland existente, `eglGetDisplay(EGL_DEFAULT_DISPLAY)` e `eglInitialize` tiveram sucesso.
- Isso ainda não prova criação de contexto GLES, criação de superfície Wayland, troca de buffers ou pixels no painel.

O socket Wayland existir também não prova que o WPE esteja apresentando uma janela visível.

## Evidência de CI versus hardware

- WPE ARM64 em headless valida carregamento de HTML, DOM, JavaScript, CSS, navegação e eventos.
- Weston headless com renderer Pixman valida o backend Wayland e a apresentação de pixels ao compositor de CI.
- O teste de captura de frame 640×480 verifica pixels de referência no Weston de CI.
- Nenhuma dessas etapas valida o driver Mali real, a ABI completa do rootfs ROCKNIX ou o painel físico do R36H.

## Correção de runtime incluída nesta revisão

O launcher agora:
1. Usa `$ROOT/runtime` por padrão; runtime em outro cartão só é aceito por `FIRE4NIX_RUNTIME_ROOT` explícito.
2. Descarta `LD_LIBRARY_PATH` herdado por padrão, mantendo o modo compatível apenas com `FIRE4NIX_INHERIT_LIBRARY_PATH=1`.
3. Verifica ELF64 little-endian AArch64 na biblioteca WPE e nos subprocessos antes de iniciar o carregador.
4. Recusa biblioteca inválida com código 79 antes de `dlopen`, em vez de permitir uma falha tardia e pouco informativa.
5. Mantém `--selftest` independente da existência do runtime WPE.

O diagnóstico:
- Só seleciona runtimes cuja biblioteca principal tem cabeçalho ELF64 AArch64 válido.
- Não trata arquivo apenas não vazio como biblioteca funcional.
- Registra `WPE_library=invalid_elf` e pula o pré-teste de carregamento quando o arquivo é inválido.
- Pode continuar a busca por outro runtime válido quando não há override explícito.
- Um override explícito inválido não é substituído silenciosamente por outro cartão.

O teste de regressão usa cabeçalhos ELF64 AArch64 mínimos gerados em diretório temporário; isso testa a guarda estática, não simula uma biblioteca WPE funcional.

## Arquitetura recomendada para a interface

### Fase 1 — consolidar a UI HTML dentro do WPE

Manter uma única WPEView/toplevel Wayland para a página inicial e os sites. A página inicial HTML será o chrome do navegador: endereço, início, voltar, avançar, atualizar, favoritos e estado de carregamento.

### Fase 2 — conectar comandos reais

Substituir o `ShellBrowserBridge` de journal por uma ponte nativa real. As ações da UI devem chegar ao processo WPE por uma interface explícita e validada (por exemplo, mensagens de script do WebKit ou uma fila de comandos GLib). O bridge não deve retornar sucesso se a navegação não tiver sido aceita.

### Fase 3 — controles físicos

Usar uma única rota de entrada para direcional, A/B, Start, Select e teclado. O perfil `installer/config/fire4nix.gptk` mapeia o D-pad para setas e A/B para Enter/Esc. Evitar executar dois mapeadores de gamepad simultaneamente. O teste `--verify-home` exercita ArrowDown/ArrowRight para confirmar o avanço de foco entre controles. Depois validar seleção, digitação, voltar, início, atualizar e sair no aparelho.

### Fase 4 — interface C++ opcional

Só reativar composição SDL/framebuffer depois de demonstrar um frame WPE Wayland real no aparelho. Não introduzir uma segunda janela ou copiar pixels entre compositores antes de medir memória, latência e estabilidade no RK3326.

## Portões de aceite

| Portão | Critério | Estado |
|---|---|---|
| G0 | Biblioteca e subprocessos ELF64 AArch64 válidos | Guarda adicionada; CI pendente |
| G1 | ABI WPEPlatform e dependências transitivas compatíveis com o ROCKNIX real | Pendente no aparelho |
| G2 | HTML local, DOM, JS, CSS, teclado virtual, formulário e foco D-pad | CI ARM64 pendente |
| G3 | WPEView Wayland e frame capturado em Weston | CI; não é Mali físico |
| G4 | EGL/GLES e superfície Wayland no R36H | Pendente |
| G5 | Primeiro frame visível no painel 640×480 | Pendente |
| G6 | Controles físicos, navegação e foco | Pendente |
| G7 | Sessão contínua de 10–20 minutos sem crash/OOM | Pendente |

## Fontes de referência

- ROCKNIX distribution: https://github.com/ROCKNIX/distribution
- WPE WebKit: https://wpewebkit.org/
- WPEPlatform (API 2.54): https://wpewebkit.org/blog/2026-10-06-wpe-platform.html
- WPE WebKit 2.54.1: https://wpewebkit.org/release/wpewebkit-2.54.1.html
- Fire4Nix PR #189 (Wayland frame capture): https://github.com/Baltdh/Fire4nix/pull/189
- Fire4Nix PR #190 (local HTML MIME fallback): https://github.com/Baltdh/Fire4nix/pull/190
