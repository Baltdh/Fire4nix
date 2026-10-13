# Pesquisa do ROCKNIX oficial para Fire4Nix (13/10/2026)

Fonte: https://github.com/ROCKNIX/distribution (branch `next`), árvore Git recursiva de 10826 entradas, sem truncamento.

## Achados verificados
- `projects/ROCKNIX/devices/RK3326/options`: aarch64 `cortex-a35`, Mali/Panfrost, `DISPLAYSERVER=wl`, `WINDOWMANAGER=swaywm-env`.
- `packages/wayland/compositor/sway/package.mk`: receita do Sway 1.12 e dependências Wayland/wlroots.
- Busca por nomes de caminho `wpe`, `webkit`, `cog` na árvore oficial: **nenhum pacote com esses nomes**. Isso **não prova ausência** em toda imagem de release ou instalação modificada.
- `packages/addons/browser/chromium/package.mk`: addon descontinuado, `PKG_ARCH=x86_64`; não é solução para RK3326.
- Projeto oficial Cog: https://github.com/Igalia/cog; Cog é lançador e depende de WPE WebKit e backend gráfico.

## Implicações
1. Compilar motor WPE WebKit e Cog/launcher para aarch64 com ABI compatível com a imagem ROCKNIX escolhida.
2. Validar os binários com `file`, `readelf -h`, `readelf -d`, `ldd` no alvo; registrar `NEEDED` e bibliotecas ausentes.
3. Usar Wayland/Sway já fornecidos pelo sistema; não iniciar compositor concorrente sem necessidade.
4. Não tratar wrappers `bin/browser.arm64` e `bin/fire4nix-wpe-platform` como binários ELF.
5. Confirmar versão do ROCKNIX no console antes de distribuir bibliotecas com glibc/libstdc++ incompatíveis.

## Limites
Não foram baixadas nem extraídas imagens completas de firmware; a pesquisa comprova as receitas e opções da branch oficial `next`, não o conteúdo exato da instalação do usuário.
