# Fire4Nix — navegador para R36H (ROCKNIX)

Desenvolvimento experimental do Fire4Nix para Rockchip RK3326/AArch64 e ROCKNIX 20261001, tela 640 × 480.

## Versão 1.02 — correções de inicialização

- [Pacotes de teste no GitHub Actions](https://github.com/Baltdh/Fire4nix/actions/workflows/r36h-oneinstall.yml): baixe o artefato `Fire4Nix-R36H-1.02-Ports-Direto` de uma execução bem-sucedida.
- `Fire4Nix-Direto.sh`: entrada independente para colocar em `roms/ports/`. Localiza a instalação em `roms/ports/fire4nix-completo` ou `roms/tools/Fire4Nix` no SD interno/externo sem mudar o diretório atual.
- O problema de menu de arquivos mostrar **View** não depende do WebKit. Inicie pelo menu **Ports** do EmulationStation; em sistemas Linux, preserve a permissão executável.
- Para investigar falhas, veja `/storage/Fire4Nix-PORTS-ultimo.txt` e `/storage/Fire4Nix-ultimo-resultado.txt`.

As alterações também corrigem um `exec` aplicado indevidamente a função de shell e evitam substituir o XDG_RUNTIME_DIR real da sessão Sway por um diretório privado sem socket Wayland.

**Estado real:** o navegador ainda **não foi confirmado funcionando no R36H físico**. Os logs mostram SIGSEGV 139 no pré-teste WPEPlatform; não há runtime WebKit ARM64 recompilado para o sistema no ZIP. O pacote inclui o binário nativo ARM64, scripts, diagnósticos e interface local, mas precisa de WPE/WebKit compatível já instalado. Os testes de CI utilizam WPE simulado, não a GPU Mali real.

Detalhes: [diagnóstico da falha 139](docs/R36H_V101_PESQUISA_CRASH139_ELF_ROCKNIX.md) · [correções 1.02](docs/R36H_V102_PORTS_WAYLAND_BOOT.md).
