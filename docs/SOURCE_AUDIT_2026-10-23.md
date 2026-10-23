# Auditoria Fire4Nix — 23/10/2026

Base examinada: `Baltdh/Fire4nix`, commit `b7156b819031d2bfb2c2d6b957a39c19fbbb9214`.
O repositório `BaltazarDun/Fire4nix` tinha somente `README.md` no momento da consulta.

## Escopo e limites

Inventário completo dos **270 arquivos versionados** da base: 62 scripts shell,
42 workflows YAML, 36 arquivos Python, 70 arquivos C++/cabeçalhos, 32 Markdown,
4 ZIPs e 24 outros arquivos de configuração, interface e recursos.
Foram verificadas a sintaxe dos 62 scripts com o interpretador de seu shebang,
a análise sintática de Python/YAML/JSON e a integridade CRC de todos os ZIPs.
A leitura técnica aprofundada concentrou-se na compilação, seleção de artefatos,
empacotamento, inicializadores, testes e componentes C++ de interface.
**Inventário e análise sintática não equivalem a revisão semântica linha a linha
de todo o código, nem de todo o conteúdo de terceiros dentro dos backups.**

Os quatro backups possuem respectivamente 204, 205, 820 e 725 entradas
(gui_wpe_bridge_v2, project_audit_v5, wpe_integration_cleaned e
wpe_integration_cleaned_with_launcher). Todos passaram CRC. Foram preservados
como históricos; correções foram aplicadas aos fontes atuais.

## Falhas reproduzidas e corrigidas

| Componente | Falha comprovada | Correção e regressão |
| --- | --- | --- |
| `scripts/package-first-r36h-ports-candidate.py` | O empacotador recebe `fire4nix-native-086-aarch64`, mas verificava o interpretador ELF somente para o nome final `fire4nix-native-aarch64`. Um executável AArch64 com carregador ausente, musl ou caminho da máquina de build passava essa etapa. | Verificar também o nome de entrada. Testes rejeitam três casos inválidos e aceitam os dois caminhos glibc já suportados. |
| `scripts/resolve-wpe-runtime-download.py` | `is_file()` seguia diretórios internos simbólicos; rejeitar apenas o arquivo final não impedia resolver bibliotecas, processos ou recursos fora do runtime. | Rejeitar links em cada componente interno do caminho obrigatório. Testes com `lib`, `libexec/wpe-webkit-2.0` e `share/wpe-webkit-2.0`. O materializador/empacotador possuem proteções adicionais; isso não comprova exploração do fluxo completo. |
| `source_r36h/Fire4Nix/Makefile` | O `break` saía do loop, mas ainda imprimia o fallback WPE. Com somente `wpe-webkit` disponível, a seleção virava `wpe-webkit wpe-webkit-2.0`, podendo invalidar pkg-config. | Encerrar a seleção após o primeiro pacote encontrado. Teste executa o Makefile real com um pkg-config controlado. |
| Mesmo Makefile | Alterar `.hpp` não recompilava `.o`, permitindo executar código antigo após uma alteração. `clean` também deixava o launcher WPE. | Gerar/incluir dependências `-MMD -MP`; limpar `.d` e launcher. Teste compila programa, muda cabeçalho e verifica mudança do código de saída de 1 para 2. |
| `src/gui/tab_strip.cpp` | Selecionar C em A/B/C/D e fechar A selecionava D, embora C continuasse aberta. | Ajustar índice quando uma aba anterior é removida. Teste C++ compilado cobre fechamento anterior, posterior, atual, última aba e índice inválido. Esta classe pertence à interface SDL histórica; não altera o motor WPE nativo. |

Antes das alterações, os novos casos reproduziram as cinco falhas. Depois,
**149 testes Python passaram**, incluindo os novos testes que compilam e
executam C++ e exercitam o Makefile.

## Lacuna da auditoria contínua corrigida

O workflow `audit-fire4nix-sources.yml` somente extraía um ZIP antigo e era
acionado por mudanças no próprio workflow. Não testava a árvore atual.
Agora roda em push/PR sobre fontes, scripts, testes, workflows e backups;
verifica sintaxe/integridade, toda a suíte Python, JavaScript offline e 11
suítes shell com fixtures. Usa permissão `contents: read`, limite de 15 minutos
e dependências de teste explícitas. Não compila WebKit nem declara sucesso
no console.

## Validação local

- 143 testes Python existentes passaram antes das mudanças; 149 após correção.
- Sintaxe dos 62 scripts shell da base: aprovada.
- Python, YAML e JSON versionados: análise sintática aprovada.
- Quatro ZIPs: CRC aprovado.
- Teste JavaScript offline: aprovado em simulação de DOM no host.
- Nove suítes shell aprovadas: isolated_loader, launcher_verified_gpu_profile,
  launcher_wpe_assets_paths, ports_installer_gpu_profile, runtime_diagnostic,
  runtime_prereqs, segv_stage_diagnostic, elf_guard e wpe_gstreamer_guard.
- `test_launch_gamepad.sh`: execução local bloqueada pela proibição de criar
  socket Unix neste ambiente. Não foi considerado aprovado nem foi afrouxado.
- `test_wpe_subprocess_target_guard.sh`: não executável localmente por ausência
  de Ninja. O workflow de auditoria instala Ninja e executa ambos os casos.
- A árvore C++ `source_r36h/Fire4Nix` compilou no host, com avisos de funções
  não utilizadas. Sem SDL/pkg-config neste ambiente, essa compilação usa
  compatibilidade/stubs e **não demonstra interface funcional ou build ARM64**.

## Pendências reais

1. Auditoria no GitHub aprovada na branch e na integração da PR #169;
   acompanhar novamente caso haja mudanças posteriores nos fontes.
2. Continuar validando o pacote WPE real e seus subprocessos com o SDK e
   artefatos correspondentes. Testes sintéticos não substituem esse processo.
3. Testar o mesmo ZIP no R36H físico: primeiro frame HTML/CSS/JS, controles,
   estabilidade, encerramento e HTTPS. Não foi acessado o console nesta auditoria.
4. A interface SDL antiga ainda contém implementações incompletas: por exemplo,
   `ShellBrowserBridge` grava comandos em journal e retorna sucesso; isso não
   comprova navegação real. Não substituir o launcher nativo atual por essa GUI.
5. `integrate-r36h.yml` é uma reconstrução histórica a partir do backup e
   escreve em uma branch antiga específica. Não usá-lo para regenerar os
   fontes atuais sem revisão do diff. Ele não foi executado nesta auditoria.

Nenhuma biblioteca, driver ou arquivo do console foi alterado. Esta auditoria
não estabelece que todos os defeitos possíveis foram eliminados.

## Confirmação posterior no GitHub

A auditoria completa passou na [branch](https://github.com/Baltdh/Fire4nix/actions/runs/39927235351)
e na [integração da PR #169](https://github.com/Baltdh/Fire4nix/actions/runs/39927269542).
As 11 suítes shell passaram no runner, incluindo sockets do gamepad e targets
Ninja que não puderam ser concluídos localmente. A combinação local com
`d2d3e0c` (PR #168, recebida durante a auditoria) passou **151 testes Python**
e o teste atualizado de isolamento do carregador; não houve conflito de merge.
Isso continua sem comprovar o primeiro frame no hardware.
