# Fire4Nix — navegador para R36H (ROCKNIX)

[Auditoria dos fontes — 23/10/2026](docs/SOURCE_AUDIT_2026-10-23.md): inventário, falhas reproduzidas, correções e limites dos testes.

## Estado atual e critérios para terminar (22/10/2026)

O SDK ROCKNIX real e seu overlay de desenvolvimento passaram a auditoria **estática** estrita de 465 referências `DT_NEEDED` na [PR #110](https://github.com/Baltdh/Fire4nix/pull/110), mas isso **não valida um navegador instalável**. Ainda faltam completar WebCore/WebKit WPE 2.54.1, verificar ABI e símbolos do runtime final, integrar o pacote, abrir a interface no R36H físico e comprovar HTTPS/controles. Acompanhar as compilações em [#102](https://github.com/Baltdh/Fire4nix/pull/102), [#106](https://github.com/Baltdh/Fire4nix/pull/106), [#107](https://github.com/Baltdh/Fire4nix/pull/107) e [#108](https://github.com/Baltdh/Fire4nix/pull/108); não presumir resultado de workflow em andamento.

**Critérios detalhados e sequência de entrega:** [docs/R36H_RELEASE_GATES_2026-10-22.md](docs/R36H_RELEASE_GATES_2026-10-22.md). Enquanto G0–G7 não forem aprovados com o mesmo pacote, `R36H_INSTALLABLE=no`.


## Etapa 1 concluída — dependências AArch64 ROCKNIX consolidadas (21/10/2026)

- **15 artefatos** do compilador ROCKNIX RK3326 reunidos em um SDK de desenvolvimento privado, com proteção contra arquivos conflitantes e bibliotecas estrangeiras.
- **157 bibliotecas ELF compartilhadas** auditadas; **22/22 requisitos de metadados WPE 2.54.1** encontrados na configuração mínima (sem GStreamer).
- O último requisito `wayland-protocols` foi resolvido usando a receita efetiva ROCKNIX 1.44 (somente XML + pkg-config, sem ELF do Ubuntu).
- Execução CI aprovada: [GitHub Actions #39705580079](https://github.com/Baltdh/Fire4nix/actions/runs/39705580079) para o estágio de 15 artefatos; relatório consolidado em [docs/R36H_STEP1_UNIFIED_ROCKNIX_SDK.md](docs/R36H_STEP1_UNIFIED_ROCKNIX_SDK.md).
- **Atenção:** o estágio não contém WebKit compilado, não valida dependências transitivas completas, GIO/TLS, sandbox ou imagem gráfica no R36H. Não instalar no console. Os artefatos do GitHub Actions expiram e deverão ser reconstruídos para futuras builds.


## Revisão 1.07 — diagnóstico com WebKit e binário em cartões diferentes

- **Causa operacional comprovada**: no backup consolidado, o arquivo antigo `Fire4Nix/fire4nix` é ELF **x86-64** e não é compatível com o R36H **AArch64**. Use somente `Fire4Nix/bin/fire4nix-native-aarch64` dos pacotes atuais.
- A maioria das bibliotecas gráficas antigas do backup está em `armhf` (32 bits); não misture com o processo ARM64. O ZIP de lançamento continua sem os 174 MB do motor WebKit.
- `Fire4Nix-Investigar-139.sh` agora procura **separadamente** o executável nativo e o motor WPE no SD interno/externo (`roms/ports` e `roms/tools`); reporta `installed_root` e `wpe_runtime_root` distintos.
- Para caminhos não padrão podem ser usados `FIRE4NIX_BINARY_ROOT` e `FIRE4NIX_RUNTIME_ROOT`. O modo `--safe` não executa o motor; `Fire4Nix-Tracar-139.sh` é um teste controlado de ABI sem abrir páginas.
- A investigação técnica traz evidências e cenários: [Estudo de causas 1.07](docs/R36H_V107_DEEP_ROOT_CAUSE_STUDY.md). A correção do Wayland 1.25+ presente em WPE 2.54.1 é majoritariamente **de build** (bug [324760](https://bugs.webkit.org/show_bug.cgi?id=324760)), sem prova de curar SIGSEGV na inicialização.
- O R36H físico precisa produzir um novo relatório antes que uma causa raiz específica possa ser afirmada. Não foram instalados novos drivers ou bibliotecas de sistema.

## Revisão 1.06 — rastreamento independente do inicializador antigo

- O coletor `Fire4Nix-Investigar-139.sh --trace` agora executa **diretamente o ELF ARM64 já instalado**, com `LD_LIBRARY_PATH` restrito ao WPE selecionado e `LD_DEBUG` isolado. Não depende de atualizar previamente `Fire4Nix-Iniciar.sh` que estava no SD.
- Para uso **sem terminal**: extraia o ZIP 1.06, coloque `Fire4Nix-Investigar-139.sh` e `Fire4Nix-Tracar-139.sh` na pasta `roms/ports/` do cartão e execute pelo menu **Ports** do ROCKNIX. O primeiro gera auditoria segura; o segundo executa apenas a verificação offline ABI e captura a falha 139.
- O relatório fica em `/storage/Fire4Nix-Investigacao-139/Fire4Nix-139-ultimo.txt` quando `/storage` permite gravação. O motor WPE/WebKit de ~174 MB e os drivers do sistema **não são copiados nem modificados**. A renderização gráfica continua sem validação real.

## Revisão 1.05 — isolamento ELF e diagnóstico do travamento 139

- **Correção no launcher**: antes, o Fire4Nix herdava `LD_LIBRARY_PATH` de outros ports/cartões. Agora usa somente `runtime/lib` da instalação selecionada; modo de compatibilidade temporário: `FIRE4NIX_INHERIT_LIBRARY_PATH=1`. Não altera drivers ou `LD_PRELOAD` configurados pelo ROCKNIX.
- **Novo diagnóstico simples**: `Fire4Nix-Investigar-139.sh --safe` cria `/storage/Fire4Nix-Investigacao-139/Fire4Nix-139-ultimo.txt` sem carregar WebKit. Funciona a partir da pasta extraída ou em `roms/ports/`.
- **Rastreamento opt-in**: `sh Fire4Nix-Investigar-139.sh --trace` executa **apenas** `--check-platform`, com `LD_DEBUG=libs,versions,files` e sem abrir páginas. Registra se houve falha antes, durante ou depois de `dlopen` e anota as bibliotecas carregadas. Os rastros detalhados ficam restritos em subpasta local; revise caminhos privados antes de compartilhá-los.
- **CI ARM64**: novos testes verificam isolamento/compatibilidade de bibliotecas, código 139 preservado e que `--safe` não executa o binário.
- **Importante**: o WPE 2.54.1 corrige compatibilidade do backend Wayland com versões mais novas do Wayland. Isso é relevante **somente depois** de confirmar que o runtime chega à inicialização gráfica; o `--check-platform` não cria uma janela. A última biblioteca listada no rastreamento também não comprova, por si só, ser a responsável pelo crash.
- **O motor WPE de ~174 MB ainda não está incluído neste ZIP e a renderização física no R36H não está validada.**

Leia também: [investigação técnica anterior](docs/R36H_V104_RESEARCH_COMMUNITY_ROCKNIX_WPE.md) e [nota upstream WPE 2.54.1](https://wpewebkit.org/release/wpewebkit-2.54.1.html).

## Revisão 1.03 — compatibilidade e diagnóstico seguro

- **Motivo do navegador ainda não abrir:** o ZIP traz o lançador e o binário AArch64, **não** o motor WPE WebKit de aproximadamente 174 MB. O runtime existente do usuário passou por SIGSEGV 139 antes da janela. A causa interna **não** foi comprovada.
- `Fire4Nix-Direto.sh` agora ignora cópias incompletas (WPE sem `WPEWebProcess`, `WPENetworkProcess` ou `WPEGPUProcess`) e procura a próxima instalação no SD.
- `Diagnosticar-Fire4Nix.sh --safe` inspeciona **sem carregar WebKit**: fontes Fontconfig, banco MIME, presença do bwrap, potenciais conflitos de bibliotecas `libc`/EGL/Wayland e requisitos de símbolo GLIBC do ELF principal.
- Os avisos não são diagnóstico definitivo de SIGSEGV: dependências transitivas, ABI, sandbox, WebKit e GPU Mali requerem confirmação no console.
- Para relatório: execute `sh Diagnosticar-Fire4Nix.sh --safe` a partir da pasta extraída ou use o terminal R36 para ler `/storage/Fire4Nix-Diagnostico-103.txt`; o pacote inclui o relatório em texto para foto.

Fontes: [WPE FAQ de problemas no startup](https://wpewebkit.org/about/faq.html), [nova API WPEPlatform](https://wpewebkit.org/blog/2026-10-06-wpe-platform.html), [ROCKNIX Ports](https://rocknix.org/systems/ports/).


Desenvolvimento experimental do Fire4Nix para Rockchip RK3326/AArch64 e ROCKNIX 20261001, tela 640 × 480.

## Versão 1.02 — correções de inicialização

- [Pacotes de teste no GitHub Actions](https://github.com/Baltdh/Fire4nix/actions/workflows/r36h-oneinstall.yml): baixe o artefato `Fire4Nix-R36H-1.02-Ports-Direto` de uma execução bem-sucedida.
- `Fire4Nix-Direto.sh`: entrada independente para colocar em `roms/ports/`. Localiza a instalação em `roms/ports/fire4nix-completo` ou `roms/tools/Fire4Nix` no SD interno/externo sem mudar o diretório atual.
- O problema de menu de arquivos mostrar **View** não depende do WebKit. Inicie pelo menu **Ports** do EmulationStation; em sistemas Linux, preserve a permissão executável.
- Para investigar falhas, veja `/storage/Fire4Nix-PORTS-ultimo.txt` e `/storage/Fire4Nix-ultimo-resultado.txt`.

As alterações também corrigem um `exec` aplicado indevidamente a função de shell e evitam substituir o XDG_RUNTIME_DIR real da sessão Sway por um diretório privado sem socket Wayland.

**Estado real:** o navegador ainda **não foi confirmado funcionando no R36H físico**. Os logs mostram SIGSEGV 139 no pré-teste WPEPlatform; não há runtime WebKit ARM64 recompilado para o sistema no ZIP. O pacote inclui o binário nativo ARM64, scripts, diagnósticos e interface local, mas precisa de WPE/WebKit compatível já instalado. Os testes de CI utilizam WPE simulado, não a GPU Mali real.

Detalhes: [diagnóstico da falha 139](docs/R36H_V101_PESQUISA_CRASH139_ELF_ROCKNIX.md) · [correções 1.02](docs/R36H_V102_PORTS_WAYLAND_BOOT.md).
