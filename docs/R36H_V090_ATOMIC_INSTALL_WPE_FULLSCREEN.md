# Fire4Nix 0.90 — correções de instalação e janela WPE

## O que mudou

**Instalador:** substituição da pasta principal e do atalho em `Ports` passa a ser uma operação com preparação e recuperação. Antes de mover a instalação anterior, o instalador valida o executável ARM64 e `webkit_web_view_get_wpe_view`, cria o novo atalho em arquivo temporário e guarda o atalho antigo. Se ocorrer falha no `mv` de ativação, tenta restaurar a pasta anterior. Nomes temporários agora incluem o PID real (`$$`), evitando colisões por um `$` literal no código antigo.

**Atualização real:** a lógica idempotente não ignora um executável atualizado: compara o ELF e o script do launcher do pacote com os instalados antes de decidir que não há nada a fazer. Não recopia os arquivos de WebKit em execuções repetidas da mesma versão; se houver alteração, cria backup da versão anterior.

**Dois cartões:** ao identificar automaticamente onde instalar, prefere o cartão que já contém `tools/Fire4Nix/runtime/lib/libWPEWebKit-2.0.so.1`, desde que gravável. Pode-se continuar definindo `FIRE4NIX_ROMS` explicitamente.

**Comandos:** o script `Fire4Nix-Iniciar.sh` aceita uma URL diretamente como primeiro argumento, além de `--open URL`; opções inválidas continuam rejeitadas.

**Janela Wayland:** quando a biblioteca WPEPlatform fornece `wpe_view_get_toplevel` e `wpe_toplevel_fullscreen`, o launcher solicita tela cheia ao compositor Sway e atualiza o título da janela. Configurável por `FIRE4NIX_FULLSCREEN=0`. A ausência desses símbolos não bloqueia um WebKit que ainda consiga criar uma janela.

## Testes adicionados

- Compilação C++ otimizada para AArch64/Cortex-A35 e verificação ELF.
- Cópia local simulada do WPE e recusa segura se estiver ausente.
- Segunda instalação idêntica não executa cópia integral.
- Nova versão do binário causa atualização real, com backup.
- Simulação de falha no `mv` após retirada da instalação anterior e comprovação de recuperação.
- Simulação de WPEPlatform Wayland com chamada ao fullscreen e carregamento de HTML.
- WPE legado sem a API retorna código 78, sem iniciar renderização equivocada.
- Verificação de sintaxe shell e integridade do arquivo ZIP.

## Limitações importantes

- O pacote **ainda não inclui** os aproximadamente 174 MB de WPE WebKit e seus subprocessos observados no cartão; só instala se existirem.
- O funcionamento de fullscreen e renderização no R36H real depende do compositor, EGL/Mali e do WPE efetivo do aparelho; o mock em Actions não os substitui.
- Uma falha de energia durante o rename de diretórios continua sendo um caso especial: backups podem estar presentes sem o destino original. Não se declara uma transação de filesystem completamente atômica em dispositivos FAT/exFAT.
- O browser é um candidato mínimo: navegação por controle físico e teclado virtual ainda não estão homologados.

## Teste do aparelho

Extraia o ZIP. Execute `sh Instalar-Fire4Nix-Uma-Vez.sh`. Depois abra **Fire4Nix** na seção **Ports**. Para logs, veja `/storage/Fire4Nix-ultimo-resultado.txt`; é separado dos logs do Terminal R36 Tools. Os comandos `--check-platform` e `--smoke` podem ser usados sem alterar a instalação anterior.
