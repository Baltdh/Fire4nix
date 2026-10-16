# Fire4Nix 0.96 — recuperação segura, gamepad e arquivos de log únicos

## Problemas encontrados e corrigidos

### Colisão de logs e do teste de hardlink

A versão 0.95 usava um `$` literal como sufixo em dois caminhos do launcher/instalador. Em execuções concorrentes, a mesma string podia ser reutilizada por mais de um processo. A versão 0.96 usa `mktemp` para criar cada arquivo de log e `mktemp -d` para um diretório privado de verificação dos hardlinks, dispensando qualquer dependência de PID ou relógio de precisão. O instalador remove os testes temporários antes de prosseguir.

### Gamepad: não confundir a criação do processo com funcionamento

O auxiliar `gptokeyb`, quando disponível no ROCKNIX, é executado somente no modo gráfico e com o perfil `config/fire4nix.gptk`. A versão anterior registrava `gamepad=started` assim que criava o processo, mesmo se o programa encerrasse imediatamente por biblioteca ou permissão ausente. A nova versão aguarda brevemente e distingue `gamepad=running` de `gamepad=helper_exited_early exit_code=N` para falhas imediatas. O navegador continua abrindo mesmo que o auxiliar não esteja disponível.

Esta é **apenas uma verificação inicial do processo**, e não uma comprovação de que o teclado/mouse virtual está entregando eventos ao Wayland. O perfil continua opcional via `FIRE4NIX_GAMEPAD=0`, não instala drivers nem modifica `/dev/uinput`.

### Instalação de WebKit em espaço limitado

O instalador prefere hardlinks onde o sistema de arquivos permite e usa cópia independente no FAT/exFAT ou em outro cartão. A verificação inicial agora tem um segundo estágio: se o teste de hardlink passou, mas a ligação dos arquivos reais falhar, ele remove a árvore parcial e **verifica novamente a capacidade livre antes de iniciar a cópia integral do runtime WebKit**. Se não houver o espaço necessário, sai com código 6 sem substituir a versão anterior. Isso reduz risco de cartão cheio durante uma atualização.

## Testes automáticos

- Simular `gptokeyb` funcional, desativado, ausente e um processo que sai imediatamente com erro.
- Criar dois logs de pré-verificação em sequência e assegurar nomes distintos.
- Instalar a partir de mock WPE, atualizar somente HTML e configuração do gamepad, testar hardlinks disponíveis e indisponíveis.
- Simular sucesso do hardlink de prova com falha posterior de `cp -al`; exigir cópia de segurança independente quando houver espaço.
- Simular espaço disponível suficiente apenas para links, insuficiente para cópia do WPE; exigir código 6 e preservação da instalação antiga.
- Manter as provas de rollback, WPEPlatform, sinais do compositor e execução AArch64.

Os testes de integração de gamepad usam um socket Unix e um auxiliar **simulados**; não comprovam funcionamento físico da controladora ou da GPU.

## Como testar no R36H

1. Extraia `Fire4Nix-R36H-0.96-Estabilidade-ROCKNIX.zip` e execute `sh Instalar-Fire4Nix-Uma-Vez.sh`.
2. Execute `sh Diagnosticar-Fire4Nix.sh` (gera `/storage/Fire4Nix-Diagnostico-096.txt` quando possível).
3. Inicie a entrada Fire4Nix em **Ports**. Se não abrir, veja `/storage/Fire4Nix-ultimo-resultado.txt`.
4. No relatório, procure as linhas `WPEPlatform_preflight_exit`, `rocknix_gptokeyb`, `virtual_keyboard_uinput` e `gamepad=...`.

O ZIP contém executável ARM64, interface offline, configuração do controle e scripts; **não inclui** o WebKit de aproximadamente 174 MB já observado no cartão SD. O único teste definitivo de janela, controles e renderização Mali/Wayland continua sendo o aparelho real.
