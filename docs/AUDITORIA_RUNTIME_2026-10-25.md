# Auditoria dos scripts de execução — 25/10/2026

Base: main a852f27d38ecb58741ac5262c55710c3cef8d0db (PRs 173, 176, 179 e 180
integrados). A compilação Mali/EGL 40033262653 concluiu com sucesso; isso não
comprova imagem física no R36H. Esta revisão não altera o motor compilado.

## Falhas reproduzidas e correções

- O resgate v2 truncava um único relatório a cada execução. Sessões simultâneas
  podiam misturar mensagens e alterar a classificação da tentativa. Agora cada
  sessão usa mktemp com XXXXXX no final e permissões privadas. O arquivo
  `ultimo.txt` é publicado por renomeação de uma cópia completa; a evidência
  individual permanece disponível no caminho FULL_REPORT.
- Um FIRE4NIX_ROOT explícito inválido podia ser ignorado e outra instalação
  iniciada. O caminho explícito agora é obrigatório e validado. Caminhos
  relativos válidos são convertidos em absolutos antes de compor file://.
- A verificação de ABI podia encerrar com erro e ainda receber classificação
  `abi_only_no_frame_proof`. Falhas agora têm classificação `diagnostic_failed_*`.
- Smoke/ABI dependiam de timers internos que podem nem iniciar se o driver
  travar na inicialização. Agora são executados com timeout externo de 30 s
  por tentativa, configurável de 1 a 300 por FIRE4NIX_RESCUE_TIMEOUT. Modos
  interativos continuam sem esse timeout. Ausência do utilitário bloqueia os
  testes automáticos em vez de executá-los sem limite externo.
- Mensagens gráficas podiam causar retry após códigos de interrupção. Saídas
  130/137/143 agora preservam o encerramento e não iniciam a variante CPU.
- Os atalhos do kit `.Fire4Nix-Teste-101` não encontravam o pacote padrão
  `ports/Fire4Nix` ao lado. A localização agora inclui essa pasta e os caminhos
  padrão de ROMs. O diagnóstico recebe o mesmo runtime escolhido para o teste,
  mantendo uma configuração explícita de diagnóstico quando fornecida.

## Verificação

- 206 testes Python aprovados localmente, incluindo sessões simultâneas,
  interrupção, timeout, preservação de modo interativo e atalhos reais do kit
  com executável simulado e diretórios contendo espaços.
- Antes da correção, os novos cenários reproduziram seleção incorreta,
  ausência de logs individuais, classificação incorreta, ausência de timeout
  e `SKIPPED_NO_INSTALLED_RUNTIME` no kit ao lado do pacote padrão.
- Inventário da base: 294 arquivos rastreados. Verificados sintaticamente os
  63 scripts shell, 52 arquivos Python e um JSON; quatro ZIPs históricos
  passaram na verificação de integridade. Os novos testes também foram executados.
- JavaScript da página offline aprovado em simulação DOM no host.

Esta é uma revisão de código e comportamento simulado. Não estabelece que
EGL/GLES, troca de buffers ou a página gráfica funcionem no aparelho físico.
Os arquivos já copiados para o R36H e os kits antigos não são atualizados por
um commit GitHub; precisam receber a revisão para usar as correções.
