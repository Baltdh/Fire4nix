# Fire4Nix 1.02 — Ports direto e sessão Wayland no R36H

## Evidências do aparelho
- ROCKNIX 20261001 / aarch64 RK3326 / kernel 7.1.2 / glibc 2.41 / aproximadamente 1 GB RAM.
- Wayland `/var/run/0-runtime-dir/wayland-1` foi observado.
- Runtime no SD tem `libWPEWebKit-2.0.so.1` de 174.006.016 bytes e três processos auxiliares. Ter os arquivos não implica renderização.
- A tentativa de verificar a API WPEPlatform falhou com **139 (SIGSEGV)** antes da janela. A etapa específica do crash continua sem comprovação por backtrace. Outras tentativas anteriores tiveram 127 por biblioteca não encontrada.
- O terminal SDL é outro aplicativo; seu funcionamento não valida o WebKit.

## Correções aplicadas
1. `source_r36h/Fire4Nix/scripts/wpe_platform_launch.sh`: substitui `exec fire4nix_launch_engine` por chamada válida de função Bash, preservando o código de saída. `exec` só aceita executáveis/comandos, não uma função desta forma.
2. `source_r36h/Fire4Nix/scripts/run_browser.sh`: localiza o socket da sessão ROCKNIX antes de usar uma pasta privada para `XDG_RUNTIME_DIR`. Evita perder `wayland-1` em inicializações pelo menu/fora da pasta original.
3. `installer/Fire4Nix-Direto.sh`: entrada `.sh` única para a categoria **Ports**, executada de qualquer diretório atual. Procura `fire4nix-completo` em SD interno/externo e o layout anterior `tools/Fire4Nix`, priorizando o pacote WPE nativo. Não replica os ~174 MB de WebKit. Aceita `FIRE4NIX_ROOT=/caminho` para seleção explícita. O resultado e os erros são registrados em `/storage/Fire4Nix-PORTS-ultimo.txt` quando disponível.
4. `native/tests/test_ports_direct.sh`: verifica lançamento por caminho com espaços, diretório atual diferente, códigos 0/139/127 e integridade sintática Bash/sh.
5. CI `r36h-oneinstall.yml` inclui `Fire4Nix-Direto.sh` no ZIP 1.02 e executa o novo teste no runner ARM64.

## Instalar/abrir
- Baixe o artefato `Fire4Nix-R36H-1.02-Ports-Direto` de Actions.
- Extraia o pacote e mantenha o browser completo instalado em `roms/ports/fire4nix-completo/`, ou no layout anterior `roms/tools/Fire4Nix/`.
- Coloque **apenas** `Fire4Nix-Direto.sh` no diretório `roms/ports/` do cartão de jogos e atualize a lista de jogos/Ports no EmulationStation.
- Abra a entrada **Fire4Nix-Direto** na categoria Ports; o gerenciador de arquivos pode mostrar `View` e não precisa ser utilizado para executar. Em filesystem Linux, o arquivo deve ter permissão de execução (`chmod +x`); o pacote ZIP preserva esta permissão para ambientes compatíveis.
- Se não abrir, leia `/storage/Fire4Nix-PORTS-ultimo.txt` e `/storage/Fire4Nix-ultimo-resultado.txt`.

## Limitações reais
**Ainda não é uma correção comprovada do SIGSEGV 139 do WebKit.** A falha ocorre até no pré-teste de API, portanto uma mudança na entrada Ports não elimina necessariamente falhas dentro da biblioteca. O pacote **não** inclui novo runtime de 174 MB nem substitui drivers Mali, `glibc`, firmware ou sandbox. O próximo teste físico precisa mostrar a etapa exata do crash do `--screen`, verificar a ABI e, se o runtime for incompatível, gerar WebKit para o SDK real do ROCKNIX antes de afirmar que o navegador funciona.
