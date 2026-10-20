# FIRE4NIX / R36H — DOSSIÊ DE CONTINUIDADE TÉCNICA
**Atualizado:** 19/10/2026, após os testes de 21:18 no R36H.
**Projeto:** https://github.com/Baltdh/Fire4nix
**Objetivo:** retomar o desenvolvimento do navegador no ROCKNIX sem perder evidências, diagnósticos e decisões de compatibilidade.
**Status atual:** pacote WebKit recuperado íntegro; carregamento dinâmico bloqueado por **GST_CAT_DEFAULT** na **libgstvideo-1.0.so.0**. Navegação, renderização e janela **ainda não foram comprovadas**.

> Este documento distingue o que as fotos e logs do dispositivo provam, o que foi relatado nas análises anteriores e o que permanece hipótese. Não apresenta nenhum mock ou teste estático como navegador operacional.

## 1. Hardware, sistema e restrições

| Item | Evidência ou decisão |
| --- | --- |
| Console | R36H, SoC RK3326, Cortex-A35; tela 640×480 |
| Arquitetura | aarch64 / ARM64, confirmada por uname e readelf |
| GPU | Mali G31, ROCKNIX com Wayland/Sway |
| Kernel informado pelo diagnóstico | 7.1.2 |
| glibc do dispositivo | 2.41 (getconf GNU_LIBC_VERSION) |
| Display de sessões anteriores | Wayland: wayland-1; XDG_RUNTIME_DIR=/var/run/0-runtime-dir |
| Método de testes | R36 Hub com terminal HTTP remoto autorizado a partir do celular; shell bash 5.3 |
| Execução pelo console | Menu ROCKNIX **Ports**; .sh no gerenciador de arquivos pode aparecer como View |
| Cartões | Interno e externo montados em /storage/games-internal e /storage/games-external |
| Meta de tamanho | ZIP ideal <100 MB, limite desejado 170 MB **comprimido**; instalado pode ser maior |
| Segurança de alterações | NÃO substituir glibc, /usr/lib, drivers Mali, firmware ou apagar a biblioteca anterior sem backup e prova de compatibilidade |
| Versão ROCKNIX | A glibc 2.41 bate com receita ROCKNIX 20260801, **mas a tag exata do firmware não foi confirmada** |

## 2. Arquivos e caminhos IMPORTANTES

**Instalação antiga, inválida (cartão interno):**

- /storage/games-internal/roms/tools/Fire4Nix/runtime/lib/libWPEWebKit-2.0.so.1
- /storage/games-internal/roms/tools/Fire4Nix/runtime/libexec/wpe-webkit-2.0/WPEWebProcess
- /storage/games-internal/roms/tools/Fire4Nix/runtime/libexec/wpe-webkit-2.0/WPENetworkProcess
- /storage/games-internal/roms/tools/Fire4Nix/runtime/libexec/wpe-webkit-2.0/WPEGPUProcess
- Executável lançador instalado: /storage/games-internal/roms/ports/Fire4Nix/bin/fire4nix-native-aarch64

**Recuperação íntegra, testada no cartão EXTERNO (NÃO sobrescreveu o antigo):**

- Pasta base R: /storage/games-external/roms/ports/Fire4Nix-RK3326-Resgate/Fire4Nix/runtime/aarch64
- Biblioteca principal: R/lib/libWPEWebKit-2.0.so.1
- Dependências do pacote: R/lib
- Subprocessos: R/libexec/wpe-webkit-2.0/
- Recurso: R/share/wpe-webkit-2.0/inspector.gresource
- Bundle: R/lib/wpe-webkit-2.0/injected-bundle/libWPEInjectedBundle.so
- Script de integridade: /storage/games-external/roms/ports/Fire4Nix-Resgate-Validar.sh
- Script original de ABI: /storage/games-external/roms/ports/Fire4Nix-Resgate-Testar-ABI.sh
- ZIP extraído no cartão externo: Fire4Nix-R36H-Resgate-Runtime-Validado.zip
- Relatório da integridade: /storage/Fire4Nix-Resgate-Verificacao.txt
- Relatório ABI original: /storage/Fire4Nix-Resgate-ABI.txt
- Relatórios de tentativas com paths ajustados: /storage/Fire4Nix-ABI2.txt, /storage/Fire4Nix-ABI3.txt (nome pode variar por teste)
- Relatório do inspetor ELF v1.08: /storage/Fire4Nix-ELF-ultimo.txt

**Pacotes já mencionados:**

- **Fire4Nix-R36H-1.08-Inspecao-ELF-ABI.zip**: cerca de 52 KB, contém launcher e diagnósticos; **NÃO inclui motor WebKit funcional**.
- **Fire4Nix-R36H-Resgate-Runtime-Validado.zip**: cerca de 86 MB comprimido (relato da geração); cerca de 232 MB extraído; contém WPE WebKit AArch64, subprocessos, lib complementares, recursos e verificadores.
- Foi utilizado um ZIP maior fornecido anteriormente, contendo um ZIP interno; inspeção anterior reportou SHA-256 consistente e cópias redundantes do WebKit. **Não presumir qual etapa corrompeu o pacote antigo no cartão**.
- A configuração do download original e SHA-256 específicos devem ser recuperados do próprio pacote/manifesto; **não inventar hash**.

## 3. Linha do tempo dos erros — provas coletadas NO DISPOSITIVO

### Fase A — instalação antiga: erro ELF, exit 127

- O executável Fire4Nix aarch64 iniciou, mas ao fazer dlopen da biblioteca antiga recebeu **invalid ELF header**.
- Biblioteca antiga: **174.006.016 bytes**; início **a0 a3 22 00**, e NÃO **7f 45 4c 46** (ELF).
- A 1 MiB, o comando od mostrou dados como **03 04 00 00 ...**, mas isso não repara o cabeçalho. Não concluir que todo arquivo foi preenchido com zero.
- Subprocessos antigos WPEWebProcess, WPENetworkProcess e WPEGPUProcess igualmente com cabeçalhos não-ELF; entre eles foram observados padrões 84 aa ca 00, zeros e 6b aa ca 00.
- Em uma busca limitada a /storage/games-internal/roms e /storage/games-external/roms, só foi encontrada a biblioteca antiga inválida.
- A origem precisa da alteração dos bytes **não está comprovada**; pode ter ocorrido durante geração, transferência, extração ou instalação, e não é prova de defeito no SD.
- Inspetor read-only v1.08 confirmou webkit_lib_verdict=BLOCK_NON_ELF.

### Fase B — recuperação e hashes: PASSOU

- O ZIP de recuperação foi extraído em **/storage/games-external/roms/ports**.
- Executado: sh /storage/games-external/roms/ports/Fire4Nix-Resgate-Validar.sh
- Todos os itens verificados mostraram **OK**, incluindo liborC, libpsl, libsoup, libtasn1, libwpe, pacote de recursos, libWPEInjectedBundle e 3 subprocessos.
- Resultado físico: **status=STATIC_INTEGRITY_PASS**.
- Isso confirma os arquivos extraídos conforme manifesto, **não** que o WebKit carregue, rode no Wayland ou navegue na web.

### Fase C — carregamento com o WebKit recuperado

1. Com R/lib no LD_LIBRARY_PATH, o dlopen inicialmente falhou em:
   **libxml2.so.2: cannot open shared object file** (native_preflight_exit=127).
2. Busca achou **/usr/lib/compat/libxml2.so.2**. readelf -h confirmou **ELF64 / AARCH64**.
3. Incluindo **/usr/lib/compat** no LD_LIBRARY_PATH, o loader avançou para:
   **/usr/lib/libGL.so.1: file too short** (exit 127).
4. Inspeção mostrou /usr/lib/libGL.so.1 -> libGL.so.1.7.0, cujo destino é **dispositivo de caracteres crw-rw-rw- 1,3** (equivalente a /dev/null, stat tamanho 0). Isso pode ser parte deliberada da imagem; NÃO é uma libGL ELF válida e **NÃO deve ser substituído em /usr/lib**.
5. Encontrada alternativa **/usr/lib/gl4es/libGL.so.1**: ELF64 AArch64, tipo DYN, **1.445.864 bytes**. Também há arquivos EGL e GLESv2 em /usr/lib e /usr/lib/mali. A existência da GL4ES não prova plena compatibilidade com todos os métodos OpenGL.
6. Incluindo **/usr/lib/gl4es** no LD_LIBRARY_PATH, o loader avançou para:
   **R/lib/libgstvideo-1.0.so.0: undefined symbol: GST_CAT_DEFAULT** e **RESULTADO=127**.
7. O WebKit não foi renderizado. O teste ficou em --check-platform e **não passou**.

### Fase D — exame específico de GStreamer: BLOQUEIO ATUAL

- readelf -Ws R/lib/libgstvideo-1.0.so.0 | grep GST_CAT_DEFAULT retornou literalmente uma entrada:
  **190: 0000000000000000 0 OBJECT GLOBAL DEFAULT UND GST_CAT_DEFAULT**
- **UND** significa referência dinâmica não resolvida nesse objeto. Em GStreamer, GST_CAT_DEFAULT normalmente é uma variável de categoria de logging em módulos. Uma dependência global não resolvida é suspeita de problema na construção/linkedição da biblioteca; **não basta presumir versão incompatível do sistema**.
- A única libgstvideo-1.0.so* encontrada na busca informada estava em **R/lib/libgstvideo-1.0.so.0**.
- **/usr/lib/libgstvideo-1.0.so.0** não foi encontrada pelo teste direto.
- **/usr/lib/libgstreamer-1.0.so.0** está presente e é **AARCH64**; readelf -Ws /usr/lib/libgstreamer-1.0.so.0 | grep GST_CAT_DEFAULT produziu **Nenhum resultado**.
- **R/lib/libgstreamer-1.0.so.0 NÃO existe**. Isso foi provado por tentativa de readelf nesse caminho, que informou No such file or directory.
- Último comando executado consultou readelf -d R/lib/libgstvideo-1.0.so.0 | grep NEEDED e símbolos de /usr/lib/libgstreamer-1.0.so.0.
- Última FOTO de 21:18 mostra trecho FINAL de NEEDED (entre outros nomes):
  **libglib-2.0.so.0, libm.so.6, liborc-0.4.so.0, libc.so.6, ld-linux-aarch64.so.1**.
  A captura está cortada acima, portanto não lista **TODAS** as NEEDED e não podemos inferir a lista integral só desta foto.
- A mesma foto mostra **SIMBOLO NO SISTEMA: Nao encontrado**, isto é, libgstreamer do sistema não exporta GST_CAT_DEFAULT. Isso reforça a análise do símbolo, mas **não demonstra que a falta de libgstreamer privado é, sozinha, a causa da referência UND**.
- **Não criar uma variável GST_CAT_DEFAULT artificial em preload**, não renomear libgstvideo de outra ABI, não mexer no GStreamer global do ROCKNIX.

## 4. Estado do projeto no GitHub

**Repositório:** https://github.com/Baltdh/Fire4nix

**PR anterior relacionado:** https://github.com/Baltdh/Fire4nix/pull/30 — melhorias v1.08 de diagnóstico ELF e guardas de compatibilidade GLIBC.

**Arquivos já confirmados na branch main em 19/10/2026:**

- installer/Fire4Nix-Inspecionar-ELF.sh — diagnóstico apenas leitura, subprocessos, magic, readelf e SHA opcional.
- rocknix-integration/build-wpe-2.54.1.sh — referência padrão ROCKNIX 20260801, Cortex-A35, WPE 2.54.1; não é prova de engine compilado para o dispositivo.
- rocknix-integration/stage-wpe-runtime.sh — verifica AArch64, símbolo WPEPlatform e limites diretos da glibc na fase de staging.
- docs/R36H_V108_ELF_GLIBC_COMPATIBILIDADE.md — relatório anterior, anterior aos achados da recuperação.
- native/tests/test_elf_guard.sh — testes automatizados com mocks. Testes verdes no GitHub **não substituem teste real no R36H**.
- Histórico dos diagnósticos 139 antigos e versão 1.07 deve permanecer separado do erro real 127 e do erro atual do GStreamer.

## 5. Diagnóstico e próximos passos RECOMENDADOS

**Objetivo imediato:** resolver com ABI consistente o símbolo GST_CAT_DEFAULT antes de testar interface e renderização. De preferência investigar offline o conjunto de dependências, em vez de fazer dezenas de tentativas isoladas.

1. **Capturar NEEDED COMPLETO e símbolos do GStreamer no aparelho** em relatório pequeno; não pedir ZIP de 174 MB novamente.
2. Inspecionar readelf -d e readelf --dyn-syms dos binários do runtime recuperado e do libgstvideo, verificando SONAME, RUNPATH, RPATH, dependências transitivas e variáveis UND.
3. Conferir se esse libgstvideo foi compilado por uma cadeia GStreamer consistente; GST_CAT_DEFAULT **normalmente não é um símbolo de API global exportado por libgstreamer**. Se a referência indevida estiver dentro do ELF original, solução correta é **recompilar libgstvideo/gst-plugins-base com as flags e o código corrigidos**, ou compilar o WPE sem a dependência multimídia se tecnicamente possível. Desabilitar áudio/vídeo em um runtime **já compilado** não elimina DT_NEEDED.
4. Evitar usar libgstvideo de outro firmware/ABI ou inventar símbolo via preload. Jamais modificar /usr/lib.
5. Planejar um runtime WPE 2.54.1 AArch64 com sysroot/SDK auditado do ROCKNIX compatível com **glibc 2.41**, com libsoup 3, ICU, GLib, libxml2, GStreamer opcional e dependências Wayland/Mali previstas e empacotadas de forma coerente.
6. Após carregar WPE: executar --check-platform (símbolos básicos e adicionais); depois headless HTML local; depois Sway/Wayland janela 640×480; depois input de botões; depois página HTTPS, certificados, DNS, fontes, banco MIME. Cada fase com log e rollback.
7. Na distribuição final incluir SHA256SUMS, verificação da assinatura ELF e bibliotecas transitivas, cópia atômica e respeito ao limite **170 MB ZIP**. Não alterar o runtime antigo até validação.

### Um comando útil e seguro para coletar próximos dados

Este comando **somente lê** os ELF e grava um relatório curto em /storage; pode ser colado como uma única linha no terminal remoto (ideal não dividir comandos bash pela interface):

~~~sh
R=/storage/games-external/roms/ports/Fire4Nix-RK3326-Resgate/Fire4Nix/runtime/aarch64; { echo "DATA="; date; echo "ARCH="; uname -m; echo "GLIBC="; getconf GNU_LIBC_VERSION; echo "GSTVIDEO_NEEDED="; readelf -d "$R/lib/libgstvideo-1.0.so.0" | grep -E "NEEDED|RPATH|RUNPATH"; echo "GSTVIDEO_BAD_SYMBOL="; readelf -Ws "$R/lib/libgstvideo-1.0.so.0" | grep GST_CAT_DEFAULT; echo "GST_SYSTEM="; ls -l /usr/lib/libgstreamer-1.0.so.0; echo "GST_SYMBOL_ON_SYSTEM="; readelf -Ws /usr/lib/libgstreamer-1.0.so.0 | grep GST_CAT_DEFAULT || true; echo "GST_PRIVATE_EXISTENCE="; ls -l "$R/lib/libgstreamer-1.0.so.0" 2>&1 || true; } > /storage/Fire4Nix-GStreamer-Auditoria.txt 2>&1; cat /storage/Fire4Nix-GStreamer-Auditoria.txt
~~~

Este comando não invoca o WebKit, não acessa a internet, não altera /usr/lib e não grava nos cartões dentro da pasta do navegador.

### Comando original de pré-verificação reproduzindo o erro (somente quando necessário)

~~~sh
R=/storage/games-external/roms/ports/Fire4Nix-RK3326-Resgate/Fire4Nix/runtime/aarch64; LC_ALL=C LD_LIBRARY_PATH="$R/lib:/usr/lib/compat:/usr/lib/gl4es" WEBKIT_EXEC_PATH="$R/libexec/wpe-webkit-2.0" WPE_PLATFORM=wayland /storage/games-internal/roms/ports/Fire4Nix/bin/fire4nix-native-aarch64 --check-platform > /storage/Fire4Nix-ABI3.txt 2>&1; rc=$?; tail -n 25 /storage/Fire4Nix-ABI3.txt; echo "RESULTADO=$rc"
~~~

Observação: o usuário relatou avisos LC_ALL=C.UTF-8 indisponível no shell; um aviso de locale não deve ser confundido com erros do carregador.

## 6. Retomada em uma nova conversa

Anexe **este dossiê** e diga:

> Continue o Fire4Nix para R36H/ROCKNIX no GitHub Baltdh/Fire4nix a partir deste dossiê. O ZIP de recuperação no cartão externo passou STATIC_INTEGRITY_PASS; com LD_LIBRARY_PATH incluindo /usr/lib/compat e /usr/lib/gl4es, --check-platform falha com undefined symbol GST_CAT_DEFAULT em libgstvideo-1.0.so.0. Analise e corrija a cadeia de bibliotecas do runtime sem alterar /usr/lib. Priorize coleta read-only, correção reproduzível no GitHub e pacote ZIP de no máximo 170 MB. Não declarar navegador funcional sem teste real.

**PONTO DE RETOMADA EXATO:** confirmar a lista completa de NEEDED da libgstvideo, verificar referência UND de GST_CAT_DEFAULT, investigar flags/código de compilação da cadeia GStreamer e decidir entre recompilar coerentemente ou remover GStreamer do build WPE. O estado físico do ROCKNIX deve permanecer intacto até o teste isolado aprovar.
