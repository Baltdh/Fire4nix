# Fire4Nix 1.00 — kit de teste físico R36H / ROCKNIX 20261001

## Objetivo

Permitir testar o navegador e recolher evidências **no próprio R36H**, com o mínimo de comandos e sem depender de SSH, SFTP ou cópia posterior de logs entre cartões. O kit funciona para diagnósticos mesmo se o motor WPE estiver ausente ou incompatível. **Não inclui** o WebKit real de ~174 MB e **não declara** validação gráfica prévia.

Referência do ROCKNIX: na tag `20261001`, o arquivo `config/emulators/ports.conf` identifica o sistema `ports`, caminho `/storage/roms/ports` e extensão `.sh`; o perfil Sway RK3326 exporta `WAYLAND_DISPLAY=wayland-1` e `XDG_RUNTIME_DIR=/var/run/0-runtime-dir`. O kit usa o diretório ROMS detectado pelo ROCKNIX e permite substituir via `FIRE4NIX_ROMS`.

## Procedimento recomendado

1. Extraia **todo** o `Fire4Nix-R36H-1.00-Teste-ROCKNIX.zip`, mantendo a pasta `Fire4Nix` e os scripts na mesma pasta.
2. No **Terminal R36**, entre na pasta do pacote e execute `sh Fire4Nix-Teste.sh --screen`. Isso testa o executável AArch64 e examina a origem/versão do WPE, bibliotecas, subprocessos, Wayland, DRM e controle, **sem abrir janela e sem instalar nada**.
3. Opcionalmente execute `sh Habilitar-Teste-Ports.sh`: cria dois atalhos **independentes** no menu **Ports** (`Fire4Nix-Teste-100.sh` para diagnóstico e `Fire4Nix-Grafico-100.sh` para teste offline do motor já instalado). Não substitui `Fire4Nix.sh` e não copia o WebKit. Isso permite iniciar o teste via interface do console; depois de voltar ao menu, consulte o relatório.
4. Se o relatório indicar WPEPlatform presente (`WPEPlatform_preflight_exit=0`), execute `sh Instalar-Fire4Nix-Uma-Vez.sh` para instalar/atualizar o navegador normalmente, preservando a instalação anterior em caso de falha. Se o motor estiver ausente (127) ou for ABI incompatível (78), não force a instalação: os diagnósticos isolados já fornecem a evidência necessária.
5. Para testar a inicialização gráfica e o carregamento de HTML **offline** de forma limitada, execute `sh Fire4Nix-Teste.sh --visual`. Esse teste chama o motor instalado em modo smoke com seu temporizador interno; ele não acessa sites externos. Uma saída 0 indica recebimento de sinal de carga concluída, **não comprova que a imagem apareceu na tela**.
6. Para testar a janela persistente, botões do controle e navegação, abra **Fire4Nix** em Ports (se a instalação tiver passado). A confirmação visual e os botões funcionais precisam ser observados por uma pessoa no aparelho.

## Logs que queremos receber

A execução cria, preferencialmente em `/storage/Fire4Nix-Teste/`:

- `Fire4Nix-Ultimo-Teste.txt` — cópia do último relatório, estado da ABI e falhas da tentativa gráfica;
- `Fire4Nix-Diagnostico-100.txt` — diagnóstico detalhado do WPE, incluindo localização e versão;
- `Fire4Nix-Resumo-100.txt` — poucas linhas para fotografar no Terminal R36;
- `Fire4Nix-Teste-100-XXXXXX.txt` — relatórios de sessões anteriores.

O launcher convencional mantém `/storage/Fire4Nix-ultimo-resultado.txt` com último erro e status. Para foto, basta o resumo exibido ao executar `sh Fire4Nix-Teste.sh --screen`.

## Código de diagnóstico

| Resultado | Interpretação |
|---|---|
| `selftest_exit=0` | Executável ARM64 responde; não verifica WebKit |
| `WPE_library=missing` | Biblioteca não encontrada nos locais conhecidos |
| `WPEPlatform_preflight_exit=78` | API WPEPlatform necessária ausente |
| `WPEPlatform_preflight_exit=127` | Biblioteca ou dependência dinâmica indisponível |
| `visual_smoke_exit=124` | Carregamento não terminou antes do limite |
| `visual_smoke_exit=70` | Falha do subprocesso de renderização |
| `visual_smoke_exit=71` | Display WPE desconectado |
| `visual_test=SKIPPED_NO_INSTALLED_RUNTIME` | Sem instalação local de WPE para lançar um teste gráfico |
| `visual_smoke_exit=0` | WebKit informou fim do carregamento, mas ainda requer confirmação visual |

Um `SIGSEGV` geralmente resulta em código 139 quando um processo é encerrado por sinal 11. O código por si só não identifica se a causa é Mali, Wayland, ABI ou outro componente.

## Segurança e limitações

- Não instala driver gráfico, não altera o firmware, não desativa sandbox e não altera o mapeamento global do controle.
- Não lê entrada de teclado do usuário, senhas, contas, conversas, arquivos pessoais ou logs completos do Terminal R36; não envia dados pela Internet.
- Os atalhos de teste são versionados (`-100`) e não sobrescrevem entradas existentes; o script recusa colisões.
- O teste `--visual` possui timeout máximo externo de 25 segundos quando `timeout` estiver disponível e conserva os códigos de erro retornados.
- A compilação ARM64 e os testes automatizados do GitHub simulam a API WPE, não a GPU Mali G31 ou a sessão gráfica real.

## Critérios de encerramento do teste físico

Considerar o navegador funcional somente depois de observar: (a) instalação com ABI aprovada, (b) janela visível, (c) carregamento da página inicial local, (d) direcional e A funcionando, (e) abertura de uma página online quando houver rede e (f) encerramento sem processo preso. Falha em qualquer etapa deve ser registrada como pendente, sem declarar a versão final.
