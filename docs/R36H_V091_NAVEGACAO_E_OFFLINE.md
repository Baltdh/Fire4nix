# Fire4Nix 0.91 — navegação por teclado e início offline

## Melhorias

O executável ARM64 WPEPlatform agora intercepta os eventos `WPEView::event` (somente quando essa API é exportada pelo runtime) e fornece atalhos:

- `Ctrl+H`: retornar à página local `www/inicio.html`.
- `Ctrl+R`: recarregar.
- `Alt+←`/`Alt+→`: histórico (apenas quando houver página anterior/próxima).
- `F11`: alternar tela cheia e janela, consultando o estado atual do toplevel.
- `Ctrl+Q`: encerrar o aplicativo.

Teclas restantes continuam sendo passadas ao site, inclusive em formulários. Os símbolos dinâmicos são opcionais para não provocar encerramento quando o runtime não exporta comandos de navegação ou fullscreen. A compatibilidade WPEPlatform continua sendo verificada antes de instalar.

## Página inicial de 640×480

`installer/www/inicio.html` não necessita de recursos de internet: contém links grandes, campo de endereço/pesquisa e navegação entre elementos por setas. A pesquisa usa DuckDuckGo Lite; o navegador permite introduzir URLs com `https://` e `http://` ou endereços simples. Nenhuma fonte ou biblioteca remota é carregada pelo arquivo HTML.

O sistema ROCKNIX precisa enviar eventos de teclado ao WPE para que essas funções sejam usadas. **Não existe ainda mapeamento direto do gamepad via SDL/evdev**, logo os botões físicos do R36H não foram homologados.

## Validação

A CI compila e executa a build otimizada do Fire4Nix em runner Ubuntu 24.04 ARM64, com teste de API WPEPlatform e um backend *mock* que simula eventos GLib. Os testes verificam `Ctrl+H`, `Ctrl+R`, `Alt+←`, `Alt+→`, `F11` e `Ctrl+Q`, além do carregamento da página local e instalações com recuperação.

Esse ambiente de teste **não possui a GPU Mali nem a sessão Wayland física do R36H**. A GUI visível e a navegação pela controladora dependem de teste no dispositivo. A build usa o runtime de 174 MB já presente no SD; não é autossuficiente em cartão virgem.

## Referência

- API WPEPlatform/event e toplevel: https://wpewebkit.org/blog/2026-10-06-wpe-platform.html
- MiniBrowser oficial: https://github.com/WebKit/WebKit/blob/main/Tools/MiniBrowser/wpe/main.cpp
- Código WPEEvent público: https://github.com/WebKit/WebKit/blob/main/Source/WebKit/WPEPlatform/wpe/WPEEvent.h
