# Fire4Nix v1.10 — inventário ELF/DT_NEEDED do WebKit recuperado (R36H)

Data: 19/10/2026. Continuação do dossiê do PR #31 e da auditoria GStreamer v1.09.

## Evidência preservada
- O ZIP de resgate passou em SHA/ELF no R36H: `STATIC_INTEGRITY_PASS`.
- O carregamento real `--check-platform` falha na `libgstvideo-1.0.so.0` com `undefined symbol: GST_CAT_DEFAULT`, saída 127.
- A v1.09 encontrou a mesma referência dinâmica `UND GST_CAT_DEFAULT` em seis bibliotecas libgst* do pacote; o WebKit recuperado possui DT_NEEDED direto de GStreamer. Portanto, **não** basta apagar bibliotecas GST desse WPE já compilado.
- O aparelho tem `/usr/lib/compat/libxml2.so.2` e `/usr/lib/gl4es/libGL.so.1`; o caminho normal `/usr/lib/libGL.so.1` aponta para um *character device* e não pode ser tratado como ELF.
- Nenhum desses dados comprova que a recompilação minimal WPE 2.54.1 tenha ocorrido.

## Novo auditor estático
`rocknix-integration/inspect-wpe-dependencies.sh` percorre as bibliotecas ELF privadas e três subprocessos do runtime recuperado; preserva a lista completa de `DT_NEEDED`, SONAME, RPATH/RUNPATH, arquitetura e sinaliza `GST_CAT_DEFAULT` indefinido. O script também modela a seleção de provedores em caminhos *privados* e *sistema* com prioridade para `/usr/lib/compat` e `/usr/lib/gl4es`, recusando ELF inválidos e dispositivos de caracteres. Usa somente `readelf`, `awk`, `grep` e shell; **não executa** as bibliotecas, **não** chama `ldd` e **não escreve** em `/usr/lib`.

Esse resultado é uma **aproximação de resolução de SONAMEs diretos**, não uma prova da ordem exata usada pelo carregador ELF, nem uma verificação de *símbolos*, versões, plugins GStreamer ou dependências transitivas de bibliotecas do sistema. A ordem real ainda depende de `LD_LIBRARY_PATH`, RUNPATH/RPATH, cache do loader e flags. `--strict` retorna 6 se faltar ELF/NEEDED ou houver símbolos GST suspeitos; isso bloqueia publicação, sem corrigir o motor.

## Uso no R36H sem remover o cartão ou alterar o firmware
Copie **somente** `Fire4Nix-Auditar-Dependencias.sh` (gerado pelo workflow 1.10) para `roms/ports` no cartão externo, se ainda não estiver lá. No terminal HTTP R36 Hub:

```sh
sh /storage/games-external/roms/ports/Fire4Nix-Auditar-Dependencias.sh --audit
```

Relatório: `/storage/Fire4Nix-Dependencias-ELF.txt`. O modo `--audit` retorna 0 se conseguir gerar o relatório, mesmo que encontre bloqueios. O modo `--strict` retorna 6 para bloqueios. NÃO executar o WebKit em modo diagnóstico nessa etapa.

## Testes implementados
`native/tests/test_wpe_dependency_audit.sh` cria pequenos objetos ELF **de teste** no runner ARM64. Valida mapeamento de `NEEDED`, detecção de link para `/dev/null`, arquivo corrompido e códigos de saída. Esses fixtures não simulam renderização no RK3326.

## Próximo passo após coletar o relatório
1. Identificar SONAMEs ausentes/incompatíveis e quaisquer avisos `GST_CAT_DEFAULT`.
2. Comparar ABI com a imagem ROCKNIX exata (glibc 2.41 isoladamente não identifica o firmware).
3. Compilar WPE 2.54.1 minimal com SDK/sysroot correto, `USE_GSTREAMER=OFF` e opções multimídia desligadas; auditar todas as dependências novas.
4. Só declarar sucesso quando `--check-platform` sair com código 0 **no dispositivo**, seguido por HTML local, Wayland 640x480 e HTTPS.

**Status real:** auditor e testes preparados; **motor WPE não foi recompilado ou validado graficamente** nesta etapa.


## Atualização 1.11 — correção do falso positivo de resolução ELF (20/10/2026)

### Defeito encontrado em 1.10
Quando a auditoria encontrava um candidato ELF inválido em um diretório mais cedo na busca, ela continuava procurando candidatos posteriores. Isso podia registrar \`RESOLVED\` incorretamente. Um teste controlado confirmou que um symlink para \`/dev/null\` precedendo uma biblioteca ELF válida resulta em \`file too short\` e retorno 127 ao executar o loader Linux. A presença da cópia válida posterior **não** garante que ela seja utilizada.

### Mudança real
- \`inspect-wpe-dependencies.sh\`: registra \`BLOCKED_FIRST_CANDIDATE\` e bloqueia \`--strict\` (exit 6), em vez de saltar para outra biblioteca.
- Entradas \`DT_NEEDED\` contendo \`/\` agora são marcadas como não suportadas pela aproximação de busca SONAME; não são falsamente consideradas resolvidas.
- Analisa também \`lib/wpe-webkit-2.0/injected-bundle/libWPEInjectedBundle.so\`, presente no ZIP recuperado.
- Testes de regressão cobrem o primeiro ELF inválido com outro válido posteriormente, além do bundle.
- Nenhuma alteração em \`/usr/lib\`, no navegador instalado, glibc, GL4ES ou Mali.

### Fontes primárias consultadas
- Linux manual do carregador dinâmico, inclusive prioridades DT_RPATH, LD_LIBRARY_PATH, DT_RUNPATH e cache: https://man7.org/linux/man-pages/man8/ld.so.8.html
- Documentação oficial GstInfo: \`GST_CAT_DEFAULT\` é macro normalmente definido por módulo, não é uma API global de \`libgstreamer-1.0\`: https://gstreamer.freedesktop.org/documentation/gstreamer/gstinfo.html
- Dependências das opções GStreamer no WebKit: https://github.com/WebKit/WebKit/blob/webkitglib/2.54/Source/cmake/GStreamerDependencies.cmake

### Implicações e pendências
- \`--audit\` continua sendo estático, sem prova de execução, porque não simula com fidelidade total \`RPATH/RUNPATH\`, cache, \`$ORIGIN\` e dependências transitivas.
- **Não é necessário repetir** o SHA do ZIP recuperado, salvo se for alterado. Falta corrigir o WPE executável, não sua integridade.
- Na próxima compilação WPE minimal, verificar a configuração CMake gerada e \`DT_NEEDED\` real antes de instalar em um diretório novo. A compilação cruzada não ocorreu nesta PR.
