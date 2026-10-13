# Fire4Nix — Inventário e política de limpeza (2026-10-13)

## Estado verificado
- `main`: quatro arquivos ZIP históricos e documentação/diagnóstico.
- `codex/fire4nix-preparation`: 144 arquivos versionados.
- `feature/extracted-source-audit`: 274 arquivos versionados, com código extraído em `source/`.
- Comparação por SHA de blob Git **dentro de cada branch**: nenhum par de arquivos distintos possui conteúdo binário idêntico. Isto **não** significa ausência de duplicação funcional ou cópias dentro dos ZIPs.
- Os ZIPs históricos **não foram abertos nem comparados internamente** nesta auditoria; não são candidatos seguros à exclusão.

## Fonte de verdade proposta
- `source/`: árvore de código extraído para triagem.
- `docs/`: decisões, documentação e critérios de aceite.
- `.github/workflows/`: verificação automática.
- ZIPs na raiz: backups históricos preservados até inventário de hashes e conteúdo interno.

## Regras para remoção
1. Nunca remover um arquivo somente por semelhança do nome ou tamanho.
2. Gerar SHA-256 de cada arquivo extraído dos ZIPs e comparar bytes.
3. Antes de excluir código duplicado funcional, mapear referências em Makefile, scripts, includes e workflows.
4. Conservar artefatos ARM64 e bibliotecas WPE enquanto não houver build reproduzível validado.
5. Só promover uma versão instalável após testar lançamento, dependências e logs no R36H.

## Próximos passos
- Auditar arquivos internos dos quatro ZIPs e gerar manifesto por caminho, hash e função.
- Consolidar `source/` com alterações da branch `codex/fire4nix-preparation`, preservando as duas histórias.
- Corrigir a entrada do menu ROCKNIX, diretórios de instalação e captura de erros do launcher.
- Testar o pacote no hardware; falhas de Wayland e WPE não podem ser consideradas resolvidas sem essa etapa.
