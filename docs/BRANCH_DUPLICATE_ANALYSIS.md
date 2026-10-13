# Comparação verificável entre branches — 2026-10-13

Comparação via Git Trees (SHA-1 de blob, equivalência exata de conteúdo) de `codex/fire4nix-preparation` (4f87f8b) e `feature/extracted-source-audit` (antes deste relatório, e3f1484).

- 144 arquivos versionados na branch codex.
- 277 arquivos versionados na branch de auditoria (incluindo documentação e lançador novos).
- 103 pares de caminhos correspondentes após mapear `Fire4Nix/` para `source/`.
- **65 pares exatamente idênticos** por blob SHA.
- **38 pares diferentes**; não substituir automaticamente.
- Comparação **entre branches**, não significa duplicação de arquivos no mesmo pacote.

## Arquivos divergentes críticos
`Fire4Nix.sh`, `Install-Fire4Nix.sh`, `Makefile`, `scripts/run_browser.sh`, `scripts/fire4nix_env.sh`, `scripts/wpe_platform_launch.sh`, `firefox-framebuffer-wrapper.py`, `src/fire4nix_ipc.cpp` e outros arquivos C++.

## ZIPs históricos (tamanhos Git)
- gui_wpe_bridge_v2: 202988 bytes
- project_audit_v5: 193961 bytes
- wpe_integration_cleaned: 2355278 bytes
- wpe_integration_cleaned_with_launcher: 5476420 bytes

**Limite desta análise:** não foi feita extração nem comparação interna dos arquivos ZIP. Não há prova de que qualquer ZIP seja redundante. Nenhum foi excluído.

## Decisão de limpeza
1. Preservar as três branches e os quatro ZIPs.
2. Não promover código divergente com base apenas no tamanho.
3. Criar manifesto de arquivos internos dos ZIPs e hashes antes de remover backups.
4. Manter os lançadores e binários ARM64 até validar execução no hardware.
5. Evitar incluir `rocknix_reference/` completo no pacote final sem mapear quais arquivos são consumidos em runtime.
