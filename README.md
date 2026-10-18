# Fire4Nix — navegador para R36H (ROCKNIX)

## Revisão 1.05 — isolamento ELF e diagnóstico do travamento 139

- **Correção no launcher**: antes, o Fire4Nix herdava `LD_LIBRARY_PATH` de outros ports/cartões. Agora usa somente `runtime/lib` da instalação selecionada; modo de compatibilidade temporário: `FIRE4NIX_INHERIT_LIBRARY_PATH=1`. Não altera drivers ou `LD_PRELOAD` configurados pelo ROCKNIX.
- **Novo diagnóstico simples**: `Fire4Nix-Investigar-139.sh --safe` cria `/storage/Fire4Nix-Investigacao-139/Fire4Nix-139-ultimo.txt` sem carregar WebKit. Funciona a partir da pasta extraída ou em `roms/ports/`.
- **Rastreamento opt-in**: `sh Fire4Nix-Investigar-139.sh --trace` executa **apenas** `--check-platform`, com `LD_DEBUG=libs,versions,files` e sem abrir páginas. Registra se houve falha antes, durante ou depois de `dlopen` e anota as bibliotecas carregadas. Os rastros detalhados ficam restritos em subpasta local; revise caminhos privados antes de compartilhá-los.
- **CI ARM64**: novos testes verificam isolamento/compatibilidade de bibliotecas, código 139 preservado e que `--safe` não executa o binário.
- **Importante**: o WPE 2.54.1 corrige compatibilidade do backend Wayland com versões mais novas do Wayland. Isso é relevante **somente depois** de confirmar que o runtime chega à inicialização gráfica; o `--check-platform` não cria uma janela. A última biblioteca listada no rastreamento também não comprova, por si só, ser a responsável pelo crash.
- **O motor WPE de ~174 MB ainda não está incluído neste ZIP e a renderização física no R36H não está validada.**

Leia também: [investigação técnica anterior](docs/R36H_V104_RESEARCH_COMMUNITY_ROCKNIX_WPE.md) e [nota upstream WPE 2.54.1](https://wpewebkit.org/release/wpewebkit-2.54.1.html).

## Revisão 1.03 — compatibilidade e diagnóstico seguro

- **Motivo do navegador ainda não abrir:** o ZIP traz o lançador e o binário AArch64, **não** o motor WPE WebKit de aproximadamente 174 MB. O runtime existente do usuário passou por SIGSEGV 139 antes da janela. A causa interna **não** foi comprovada.
- `Fire4Nix-Direto.sh` agora ignora cópias incompletas (WPE sem `WPEWebProcess`, `WPENetworkProcess` ou `WPEGPUProcess`) e procura a próxima instalação no SD.
- `Diagnosticar-Fire4Nix.sh --safe` inspeciona **sem carregar WebKit**: fontes Fontconfig, banco MIME, presença do bwrap, potenciais conflitos de bibliotecas `libc`/EGL/Wayland e requisitos de símbolo GLIBC do ELF principal.
- Os avisos não são diagnóstico definitivo de SIGSEGV: dependências transitivas, ABI, sandbox, WebKit e GPU Mali requerem confirmação no console.
- Para relatório: execute `sh Diagnosticar-Fire4Nix.sh --safe` a partir da pasta extraída ou use o terminal R36 para ler `/storage/Fire4Nix-Diagnostico-103.txt`; o pacote inclui o relatório em texto para foto.

Fontes: [WPE FAQ de problemas no startup](https://wpewebkit.org/about/faq.html), [nova API WPEPlatform](https://wpewebkit.org/blog/2026-10-06-wpe-platform.html), [ROCKNIX Ports](https://rocknix.org/systems/ports/).


Desenvolvimento experimental do Fire4Nix para Rockchip RK3326/AArch64 e ROCKNIX 20261001, tela 640 × 480.

## Versão 1.02 — correções de inicialização

- [Pacotes de teste no GitHub Actions](https://github.com/Baltdh/Fire4nix/actions/workflows/r36h-oneinstall.yml): baixe o artefato `Fire4Nix-R36H-1.02-Ports-Direto` de uma execução bem-sucedida.
- `Fire4Nix-Direto.sh`: entrada independente para colocar em `roms/ports/`. Localiza a instalação em `roms/ports/fire4nix-completo` ou `roms/tools/Fire4Nix` no SD interno/externo sem mudar o diretório atual.
- O problema de menu de arquivos mostrar **View** não depende do WebKit. Inicie pelo menu **Ports** do EmulationStation; em sistemas Linux, preserve a permissão executável.
- Para investigar falhas, veja `/storage/Fire4Nix-PORTS-ultimo.txt` e `/storage/Fire4Nix-ultimo-resultado.txt`.

As alterações também corrigem um `exec` aplicado indevidamente a função de shell e evitam substituir o XDG_RUNTIME_DIR real da sessão Sway por um diretório privado sem socket Wayland.

**Estado real:** o navegador ainda **não foi confirmado funcionando no R36H físico**. Os logs mostram SIGSEGV 139 no pré-teste WPEPlatform; não há runtime WebKit ARM64 recompilado para o sistema no ZIP. O pacote inclui o binário nativo ARM64, scripts, diagnósticos e interface local, mas precisa de WPE/WebKit compatível já instalado. Os testes de CI utilizam WPE simulado, não a GPU Mali real.

Detalhes: [diagnóstico da falha 139](docs/R36H_V101_PESQUISA_CRASH139_ELF_ROCKNIX.md) · [correções 1.02](docs/R36H_V102_PORTS_WAYLAND_BOOT.md).
