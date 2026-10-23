# Recuperação do WPE compilado — 23/10/2026

A execução [39929101615](https://github.com/Baltdh/Fire4nix/actions/runs/39929101615)
concluiu a compilação (`WPE_SUBPROCESS_CMAKE_EXIT=0`), verificou WPEWebProcess e
WPENetworkProcess, instalou injected bundle/inspector e conferiu seus hashes.
Falhou **depois**, no empacotamento de dependências:
`TARGET_LIBATOMIC_MISSING_EXPORT:__atomic_load_16`.

O pré-teste da mesma execução havia encontrado as funções com `readelf --wide`.
O auditor compartilhado usava somente `readelf --dyn-syms`, que abrevia nomes
versionados, ocultando parte de `__atomic_load_16@@LIBATOMIC_1.0`. Um teste
que compila uma biblioteca mínima com exportações versionadas reproduziu a
mesma mensagem de erro; passou após acrescentar `--wide`. Esse teste usa ELF
nativo do host apenas para testar a leitura de símbolos; não executa o ELF.
As verificações ARM64, SONAME, versões GLIBC e caminhos continuam obrigatórias.

A recuperação usa a execução e SHA de origem fixos, preserva os binários e
reconstitui somente aliases com SHA256 já registrado. O novo modo explícito
`--unbundled` aceita um estágio anterior ao fechamento de dependências, sem
inventar `SDK-BUNDLE-REPORT.txt`; o modo padrão continua exigindo o relatório.
A biblioteca passa novamente pela inspeção de ELF/GCC15, pelo fechamento
recursivo com o SDK ROCKNIX e pelas verificações completas do empacotador.

Workflow: `r36h-recover-compiled-wpe-runtime.yml`, limitado à branch
`fix/wpe-build-continuation-20261023`. Reutiliza o SDK e estágio 1 das execuções
originais; não recompila WebKit, não executa binários ARM64 e não instala no
console. Só publica o candidato experimental se todas as verificações passarem.

Validação local: 161 testes Python aprovados, incluindo biblioteca versionada
real e recuperação de estágio bruto com hash incorreto, ausência de relatório
e tentativa de misturar relatório de fechamento com estágio bruto.
O resultado da recuperação real deve ser confirmado no GitHub Actions.
