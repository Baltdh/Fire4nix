# Fire4Nix 0.93 — compatibilidade WPE e instalação econômica no ROCKNIX

## O que foi corrigido

**Detecção de atualizações:** a decisão de ignorar uma instalação repetida antes comparava somente o executável ARM64 e o launcher. Agora também compara os arquivos `www/inicio.html` (teclado e página inicial) e `Diagnosticar-Fire4Nix.sh`. Assim, uma correção exclusivamente de interface ou de diagnóstico não fica bloqueada.

**Instalação com menos espaço:** no mesmo sistema de arquivos Linux que suporte hardlinks, o instalador verifica essa capacidade e pode criar links físicos para os arquivos existentes da biblioteca WPE no novo diretório de instalação. Cada arquivo compartilha os mesmos dados existentes no disco, mas mantém um nome e caminho independente. **Não** são links simbólicos nem arquivos baixados. Quando o filesystem não aceita hardlink — comum no FAT/exFAT ou entre cartões SD — usa `cp -a` para produzir uma cópia completa. Em ambos os casos a instalação anterior é preservada e há recuperação de falhas de ativação.

**Limitação de hardlinks:** alterações *in place* nos arquivos do runtime WPE compartilhado refletiriam em todas as referências. O Fire4Nix não modifica o runtime durante atualização, e essa estratégia pressupõe que arquivos WPE instalados são tratados como imutáveis. Em caso de falha da cópia por links, limpa a árvore parcialmente montada e copia os arquivos para arquivos independentes. A economia de armazenamento ocorre **somente** onde os hardlinks são realmente suportados.

**Diagnóstico WPEPlatform:** `--check-platform` continua fazendo `dlopen` e verificando os símbolos básicos necessários; agora também imprime a biblioteca de onde foi carregado `webkit_web_view_get_wpe_view` e relata `present/absent` para APIs relevantes de janela e navegação (`wpe_view_get_toplevel`, fullscreen, entrada por teclado, recarregar e voltar). Assim podemos distinguir falhas de ABI de falhas na sessão Wayland sem alegar que um teste de símbolos prove renderização. `dlclose` libera a biblioteca nas verificações que não criam uma janela.

**Assinaturas oficiais:** corrigido o tipo de retorno de `wpe_toplevel_fullscreen` e `wpe_toplevel_unfullscreen` para `gboolean`, conforme a API pública WPEPlatform. O mock dos testes também passa a respeitar esse contrato.

## Execução no R36H

1. Extraia `Fire4Nix-R36H-0.93-Otimizado-Para-Teste.zip`.
2. Execute o script `Instalar-Fire4Nix-Uma-Vez.sh` pelo Terminal R36.
3. Execute `Diagnosticar-Fire4Nix.sh` para gerar o relatório do aparelho.
4. Tente abrir **Fire4Nix** em Ports. Se falhar, compartilhe o relatório e `/storage/Fire4Nix-ultimo-resultado.txt`.

**Ainda não é uma versão autossuficiente em cartão limpo**: o ZIP inclui o binário ARM64 e os scripts, mas precisa reutilizar o WebKit de aproximadamente 174 MB do SD existente. A API WPEPlatform e a renderização real sob Sway/Mali precisam de teste físico no R36H. Os símbolos legados ou ausentes geram erro e não são convertidos artificialmente em êxito.

## Verificações CI

Em GitHub Actions Linux ARM64: build do executável Cortex-A35; integridade do ZIP; homepage HTML/JavaScript; criação de instalação limpa a partir de WPE simulado; instalação idêntica ignorada; alteração exclusivamente HTML aplicada; compartilhamento de inode por hardlinks quando disponível; fallback completo quando a operação de hardlink é proibida; rollback após falha injetada na ativação; presença/ausência de símbolos WPEPlatform e teste de fechamento do renderer.

Esses testes utilizam um **mock ABI**, não um aparelho RK3326 real. Não cobrem GPU Mali, Wayland físico, drivers proprietários, conteúdo HTTPS nem compatibilidade completa com a biblioteca de 174 MB do usuário.

## Fontes de API e distribuição

- WPEPlatform e eventos: https://wpewebkit.org/blog/2026-10-06-wpe-platform.html
- WPEPlatform `WPEToplevel.h`: https://github.com/WebKit/WebKit/blob/main/Source/WebKit/WPEPlatform/wpe/WPEToplevel.h
- ROCKNIX RK3326: https://github.com/ROCKNIX/distribution/blob/20261001/projects/ROCKNIX/devices/RK3326/options
