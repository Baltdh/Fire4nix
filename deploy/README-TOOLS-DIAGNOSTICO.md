# Fire4Nix — diagnóstico no ROCKNIX (R36H)

Este arquivo documenta o **diagnóstico independente**. Ele não é o navegador, não instala bibliotecas e não altera o sandbox do WebKit.

## Como usar na pasta Tools

1. No GitHub Actions, abra **ROCKNIX environment simulation** e baixe o artefato `Fire4Nix-ROCKNIX-Tools-Diagnostico`. Ele contém um único arquivo: `Fire4Nix-WPE-Diagnostico.sh`.
2. Copie esse arquivo para a pasta `Tools`, ao lado da pasta `Fire4Nix` (ou `navegador-definitivo`), para permitir a descoberta automática.
3. Execute o script com `sh Fire4Nix-WPE-Diagnostico.sh` pelo terminal ou por um lançador que execute scripts `.sh`.
4. Consulte o relatório salvo em `/storage/fire4nix-wpe-diagnostic.log`. Quando `/storage` não estiver disponível, o destino padrão é `/tmp/fire4nix-wpe-diagnostic.log`.

O script mostra arquitetura, kernel, caminhos de aplicação, Wayland, presença de comandos como Cog, bibliotecas e processos WPE, além de dependências ELF ausentes quando houver `ldd`. É uma coleta **sem sudo, sem acesso à internet e sem modificação do sistema**; apenas o arquivo de relatório é escrito.

Se o aplicativo estiver em outro lugar, defina `FIRE4NIX_APP_DIR` para a pasta que contém `Fire4Nix.sh`. Para alterar o local do relatório, defina `FIRE4NIX_DIAGNOSTIC_LOG`.

## Como interpretar

- `Wayland socket: MISSING`: verificar `XDG_RUNTIME_DIR` e `WAYLAND_DISPLAY` na sessão usada pelo lançador.
- `command cog: MISSING`: não há fallback Cog disponível no `PATH` atual.
- `WARNING: unresolved shared libraries`: o executável apresentado pode não conseguir iniciar devido a dependências ausentes.
- `Fire4Nix.sh` ausente: o diagnóstico não encontrou a pasta da aplicação.

**Aprovação da simulação GitHub não equivale a teste em R36H.** O navegador WPE e suas bibliotecas precisam ser compatíveis com o ROCKNIX instalado no dispositivo; o artefato de diagnóstico não prova isso.
