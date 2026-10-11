# Fire4NIX — Critérios de conclusão dos testes

Este documento define critérios verificáveis de aceite. Uma etapa só recebe **PASSOU** com evidência (log, comando, resultado e commit). Caso não seja executada, registrar **NÃO TESTADO**; falha é **FALHOU**. Não confundir build bem-sucedido com funcionamento no R36H.

## Gate 1 — Código e integridade (CI)
- [ ] ZIP principal localizado, integridade verificada (SHA-256 registrado), extração concluída sem erros.
- [ ] Fontes próprios publicados em `source/`; backups originais mantidos.
- [ ] Nenhum caminho absoluto, `../`, symlink ou arquivo do ZIP escreve fora da pasta de extração.
- [ ] Mapa de pastas, pontos de entrada, licenças e dependências identificado.
- [ ] Scripts passam em validação sintática adequada (`bash -n`, `python -m compileall`, conforme aplicável).
- [ ] Não existem segredos ou credenciais incorporados ao código.
**Aceite:** todos os itens aprovados e evidências anexadas ao relatório.

## Gate 2 — Compilação reproduzível (CI)
- [ ] Arquitetura/ABI real do ROCKNIX no R36H confirmada antes de fixar target de compilação.
- [ ] Versões reais e origem de WPE WebKit, Cog, libwpe e demais dependências documentadas.
- [ ] Build limpo reproduzível a partir do commit e instruções publicadas, com código de saída 0.
- [ ] Binário inspecionado (`file`, `readelf -h`) para verificar arquitetura e formato.
- [ ] Dependências dinâmicas verificadas para a imagem-alvo; ausência de bibliotecas incompatíveis.
- [ ] Artefato gerado e disponibilizado com SHA-256; instalação e reversão documentadas.
**Aceite:** CI verde e artefato verificável. Isso **não** comprova funcionamento no console.

## Gate 3 — Teste no R36H real (manual obrigatório)
- [ ] Versão exata do ROCKNIX, arquitetura, kernel e ambiente gráfico registrados.
- [ ] Instalação e desinstalação realizadas sem sobrescrever dados de usuário ou arquivos críticos.
- [ ] Inicialização pela interface/launcher sem travar; logs de falhas coletados.
- [ ] Interface 640×480 legível, sem elementos essenciais cortados.
- [ ] Navegação por controles físicos: foco, confirmar, voltar, rolagem e saída.
- [ ] Abrir URL HTTP e HTTPS, voltar, avançar, atualizar e favoritos.
- [ ] Erros de rede, certificados e páginas inválidas tratados sem travamento.
- [ ] Uso contínuo por 30 minutos sem encerramento inesperado, congelamento ou vazamento de memória progressivo.
- [ ] Consumo de RAM/CPU observado e registrado durante navegação real; limites finais definidos com base em medições do hardware.
- [ ] Reinício do console e nova abertura do navegador bem-sucedidos.
**Aceite:** todos os testes críticos passam no dispositivo físico, com versão do sistema, passos de reprodução, capturas/logs e resultados documentados.

## Classificação de entrega
- **AUDITORIA CONCLUÍDA:** Gate 1 aprovado.
- **BUILD DISPONÍVEL PARA TESTE:** Gates 1 e 2 aprovados.
- **COMPATÍVEL COM R36H / PRONTO PARA USO:** Gates 1, 2 e 3 aprovados.
- **BLOQUEADO:** qualquer falha crítica; registrar causa, responsável pela correção e próximo teste.

## Modelo de relatório
| Teste | Estado (PASSOU/FALHOU/NÃO TESTADO) | Evidência | Commit/versão | Observações |
|---|---|---|---|---|
| Extração | NÃO TESTADO | — | — | |
| Build ARM | NÃO TESTADO | — | — | |
| Inicialização R36H | NÃO TESTADO | — | — | |

**Política:** nunca marcar teste manual como aprovado por inferência de logs de CI. Não declarar artefato instalável sem verificar seu formato, dependências e procedimento de instalação.
