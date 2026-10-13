# ROCKNIX R36H — instalação de teste e coleta de falhas

## Arquivos
- Copie a **árvore completa** `source/` para `/storage/roms/ports/Fire4Nix/` (deve existir `scripts/run_browser.sh`).
- Copie `deploy/Fire4Nix-ROCKNIX.sh` para a pasta de scripts que seu menu EmulationStation realmente lê.
- **Não** copie apenas os scripts isolados, nem renomeie um ZIP para .sh.
- Alguns cartões ROCKNIX usam outra montagem para ROMs. Se o caminho real for diferente, edite `APP=` no lançador ou defina `FIRE4NIX_APP_DIR`.

## Diagnóstico
1. Inicie pelo menu.
2. Abra `/storage/fire4nix-launch.log`.
3. Se o navegador fechar, envie o log e `/storage/.config/fire4nix/logs/` se existir.
4. O lançador não instala bibliotecas e não prova que o binário é compatível. A inicialização real requer ambiente gráfico e bibliotecas WPE/SDL adequados.

## Cautelas
- Não use `sudo` para iniciar o navegador; privilégios elevados não resolvem bibliotecas ausentes.
- Não remova os backups ZIP antes de verificar seu conteúdo e os hashes.
- O script captura stdout/stderr, mas logs escritos diretamente pelo navegador em outros caminhos devem ser coletados separadamente.
