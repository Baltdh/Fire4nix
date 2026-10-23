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

## Bloqueios seguintes e correção do SDK de análise

A recuperação 39994402340 confirmou o ELF WPE real: SHA256
`742e19045a9c2b338051d31b6cca641f240f51e6c5c0e4da9d71f8bbb15c321c`,
156512944 bytes, GLIBC máximo 2.38, sem helpers GCC15 outlined indefinidos.
O próximo bloqueio expôs RUNPATH de build em fontconfig/gcrypt e links absolutos
apontando para a localização original do SDK. O SDK também só contém `usr/lib`,
enquanto os processos declaram `/lib/ld-linux-aarch64.so.1`.

O workflow passa a usar o overlay já auditado de seis arquivos (39714252160),
validando hashes de entrada/saída e SONAME/NEEDED/GLIBC via o preparador existente.
Um novo preparador copia o sysroot e relocaliza **apenas** links com o prefixo
absoluto observado no artefato original. Links de host, escapes e alvos ausentes
continuam proibidos. O alias privado `lib -> usr/lib` serve somente à análise;
não prova o layout nem o carregador do R36H. Os originais não são modificados.
Seis testes cobrem preservação da origem, links de host/escape/alvo ausente,
saída existente e sobreposição de diretórios. Total local: 167 testes aprovados.

## Fechamento real e portabilidade do pacote

A execução 39995227995 passou o fechamento estrito: 43 ELFs, 187 arestas de
 dependências, zero SONAMEs ausentes, zero dependências exclusivas do estágio
 e zero achados ABI. Incluiu 35 bibliotecas do SDK e validou todos os hashes.
O empacotador detectou em seguida `NON_PORTABLE_RPATH:libjpeg.so.8`: caminhos
padrão do sistema aceitos no SDK não são aceitos no pacote relocável.

`prepare-portable-sdk-rpaths.py` remove somente RPATH/RUNPATH compostos pelos
quatro diretórios padrão (`/lib`, `/lib64`, `/usr/lib`, `/usr/lib64`) em uma
nova cópia privada do estágio. Mantém caminhos relativos a `$ORIGIN`, rejeita
caminhos inesperados e verifica SONAME, NEEDED e GLIBC após cada alteração.
Registra hashes anteriores/posteriores. O fechamento e o empacotamento rodam
novamente depois da transformação, sem alterar o motor WPE original.

Integra também a verificação exata de exportações libatomic da main (#175).
Validação integrada local: 176 testes Python aprovados. A nova recuperação
real está em execução; o teste físico no R36H continua pendente.
