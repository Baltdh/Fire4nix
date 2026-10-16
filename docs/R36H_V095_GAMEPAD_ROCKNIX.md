# Fire4Nix 0.95 — controles do R36H via rocknix-hotkey

## Objetivo

Usar as ferramentas do próprio ROCKNIX para que o controle físico possa navegar na interface HTML do Fire4Nix, sem compilar uma nova biblioteca de interface, sem alterar `/dev/input` ou os drivers e sem rodar um serviço residente fora da sessão do navegador.

O projeto ROCKNIX publica o programa `gptokeyb` em https://github.com/ROCKNIX/rocknix-hotkey, com mapeamentos configurados por arquivos `.gptk`. O Fire4Nix 0.95 traz `config/fire4nix.gptk` e utiliza `gptokeyb -c <perfil>` se o programa estiver instalado e executável. **A existência da ferramenta no seu firmware e o funcionamento da injeção de teclas no Sway precisam ser validados no aparelho.** O script registra o motivo caso não consiga iniciar o auxiliar.

## Controles mapeados no perfil

| Botão lógico SDL | Resultado |
|---|---|
| Direcional | Setas, com repetição para navegar pelos elementos |
| A ou Start | Enter / abrir item |
| B | Esc |
| X | Tab (próximo foco) |
| Y | Espaço |
| Analógico esquerdo | Ponteiro do mouse, sem copiar cursor do sistema |
| R3 | Clique esquerdo do mouse |
| L3 | Clique direito |
| L1 / R1 | Home / End |
| L2 / R2 | Page Up / Page Down |
| Select (hotkey) + A | Ctrl+H / início offline |
| Select + B | Ctrl+Q / sair do navegador |
| Select + X | Ctrl+R / recarregar página |
| Select + L1 / R1 | Alt+← / Alt+→ histórico |

O perfil usa os **nomes lógicos SDL** do `gptokeyb`, sem supor números físicos de botões específicos do R36H. O mapeamento real dependerá da configuração SDL_GameController do ROCKNIX. Os atalhos não usam o recurso `gptokeyb -k/-1` que encerraria processos pelo nome; a sessão só sinaliza e encerra o **processo auxiliar criado por ela**.

## Inicialização e proteção

- Durante a abertura gráfica (`--open`), se o perfil existe e `gptokeyb` está disponível, o launcher tenta iniciar o auxiliar em segundo plano e registra o PID.
- `--check-library`, `--check-platform`, `--smoke` e `--selftest` não criam o auxiliar.
- Quando o navegador fecha ou o launcher recebe um sinal, só o filho criado pela sessão é encerrado. Outro `gptokeyb` detectado por `pgrep` não é encerrado nem duplicado.
- Se o programa não existe, o navegador continua funcionando pelo teclado normalmente e registra `gamepad=gptokeyb_missing_or_not_executable`.
- `FIRE4NIX_GAMEPAD=0` desativa o auxiliar; `FIRE4NIX_GPTOKEYB=/caminho/para/gptokeyb` seleciona explicitamente um binário.
- Nenhum arquivo de sistema nem configuração global do ROCKNIX é alterado.

A interface 640×480 mantém o teclado virtual local e seus atalhos visuais. O arquivo `Diagnosticar-Fire4Nix.sh` relata a presença do perfil, disponibilidade do comando `gptokeyb` e acesso ao dispositivo `/dev/uinput`, mas **não lê entradas do usuário nem identifica dados pessoais**.

## Verificações automatizadas

GitHub Actions em Linux ARM64 continua verificando o binário AArch64, o WPEPlatform simulado, as instalações/atualizações de arquivo, o rollback e a integridade do ZIP. A nova prova de integração cria um socket Wayland simulado, um executável Fire4Nix falso e um `gptokeyb` falso. Confirma que o auxiliar inicia com o perfil, recebe encerramento ao sair do navegador, não inicia quando desativado e não inicia no modo de pré-verificação.

**Limites:** não comprovam que o controle físico está corretamente mapeado na unidade do usuário. O pacote ainda não contém a biblioteca WPE de aproximadamente 174 MB observada anteriormente no SD. Renderização Mali/Wayland real e entrada via uinput devem ser testadas no R36H para declarar compatibilidade plena.

## Procedimento de validação no R36H

1. Extraia `Fire4Nix-R36H-0.95-Gamepad-ROCKNIX.zip` e instale executando `sh Instalar-Fire4Nix-Uma-Vez.sh`.
2. Execute `sh Diagnosticar-Fire4Nix.sh`. Consulte `/storage/Fire4Nix-Diagnostico-095.txt`.
3. Abra o Fire4Nix em **Ports**. Teste o direcional e o botão A, em seguida Select+A.
4. Se algo não funcionar, compartilhe `/storage/Fire4Nix-ultimo-resultado.txt` e o diagnóstico. O teste pode detectar se a biblioteca WPE falta ou se o gptokeyb não está acessível, sem retirar o cartão.
