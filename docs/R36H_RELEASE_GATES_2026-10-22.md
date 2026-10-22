# Fire4Nix/R36H — critérios de conclusão e sequência de integração (22/10/2026)

> Documento de coordenação técnico. **Não é atestado de que existe um navegador pronto ou de que os artefatos de CI possam ser instalados.** Estado baseado no repositório `main` em `f23db5b` e nas PRs abertas em 22/10/2026.

## Estado confirmado

- Hardware-alvo: R36H, RK3326, AArch64, tela 640 × 480; sistema medido no aparelho com glibc 2.41 e Wayland `wayland-1`. O sysroot de build ROCKNIX **não é** prova do rootfs instalado.
- Toolchain genuíno ROCKNIX 20260801, 15 artefatos de dependências, 22/22 arquivos pkg-config requeridos para o perfil reduzido WPE 2.54.1.
- `main` inclui a [PR #110](https://github.com/Baltdh/Fire4nix/pull/110): CI [39715142726](https://github.com/Baltdh/Fire4nix/actions/runs/39715142726) passou auditoria **estática** estrita em um overlay privado: 465 `DT_NEEDED` resolvidos, 0 SONAMEs ausentes, 0 RUNPATH/RPATH inseguro, 0 GLIBC acima de 2.41. Resultado ainda equivale a **nomes de bibliotecas presentes**, não conformidade de símbolos ou prova de `dlopen`.
- WPE 2.54.1 já teve a configuração CMake Wayland com GStreamer/DRM/GBM desativados. Existem experimentos de WPEPlatform/JavaScriptCore e builds em andamento de WebCore; confirmar saída final do CI antes de marcar cada alvo como compilado.
- O runtime anterior do cartão tinha `libWPEWebKit-2.0.so.1` com cabeçalho que **não começava com ELF**; houve também erro `GST_CAT_DEFAULT` em biblioteca GStreamer de outro conjunto. O binário antigo `Fire4Nix/fire4nix` de backup era x86-64. **Não reutilizar ou publicar essas cópias como se fossem compatíveis.**

## Portões obrigatórios — P0 (bloqueiam disponibilizar instalador funcional)

| ID | Critério de aceite verificável | Estado em 22/10 |
| --- | --- | --- |
| G0 — procedência | Compilador genuíno e fontes com commit/versão e SHA verificáveis; nenhuma biblioteca x86-64/armhf/Ubuntu inserida no pacote do aparelho. | Preparação do SDK aprovada; release ainda não auditado |
| G1 — cadeia nativa | Compilar integralmente JavaScriptCore, WebCore, WPEPlatform e alvo WebKit/WPE 2.54.1 com o mesmo toolchain, obtendo `libWPEWebKit-2.0.so.1` **ELF64 AArch64 real** e subprocessos correspondentes. | **Pendente**; ver PRs #102, #106–#108 |
| G2 — ABI de release | Auditar **arquivos efetivos do pacote final**, não só o SDK: ELF header, SONAME, `DT_NEEDED`, GLIBC até 2.41, dependências transitivas, RPATH/RUNPATH, bibliotecas/provider de símbolos. Sem `not found`, símbolos incompatíveis ou paths temporários. | SDK passou auditoria SONAME (#110); release **pendente** |
| G3 — inicialização | Executável Fire4Nix deve ser AArch64 e carregar o motor e subprocessos isolados em um diretório privado; `--check-platform` retorna 0, sem SIGSEGV 139, abort ou `GST_CAT_DEFAULT`. | **Não demonstrado no R36H** |
| G4 — tela | Abre janela real no compositor Wayland do aparelho e mostra `www/inicio.html` offline em 640 × 480; reproduzir após reinicialização. | **Não demonstrado** |
| G5 — rede | Abrir página HTTP e HTTPS com DNS, certificados confiáveis e verificação TLS; erros exibidos de forma legível, sem desabilitar checagem de certificado. | **Não demonstrado** |
| G6 — instalação segura | Um pacote identificável e verificável, instalado em pasta do usuário/ROMS; backup/atualização atômica, caminho de rollback, sem tocar `/usr/lib`, rootfs, Mali ou alterar instalação antiga por engano. | Instalação/launchers têm testes prévios; pacote com WebKit real **pendente** |
| G7 — regressão física | Abrir, navegar, voltar, digitar URL via controles/teclado virtual, alternar rede, sair e reabrir; logs segregados; repetir em SD interno e externo. | **Pendente** |

**Somente declarar `R36H_INSTALLABLE=yes` quando G0–G7 tiverem evidências do mesmo pacote/revisão.** Nunca promover artefato de diagnóstico (toolchain, stage, ELF overlay ou objetos isolados) a instalador.

## Próxima sequência de trabalho

1. **Acompanhar os CI atuais** de JavaScriptCore [#102](https://github.com/Baltdh/Fire4nix/pull/102), WebCore primeiros objetos [#106](https://github.com/Baltdh/Fire4nix/pull/106) e WebCore completo [#107](https://github.com/Baltdh/Fire4nix/pull/107) / [#108](https://github.com/Baltdh/Fire4nix/pull/108). Tratar esses PRs como alternativas/branches empilhados, não mesclar mudanças conflitantes automaticamente. Registrar primeiro erro de compilação e corrigir no ramo correspondente.
2. **Completar o motor WebKit WPE**, inclusive link final e subprocessos, preservando o perfil inicial **sem GStreamer**. Não declarar que objetos `.o` isolados significam navegador completo.
3. **Reempacotar SDK e runtime reprodutivelmente** a partir de versões fixadas (artefatos do Actions expiram); conferir hashes e executar o gate ABI/ELF sobre o pacote final. O CI de SONAME do estágio não substitui o teste dinâmico no aparelho.
4. **Integrar o executável e a camada ROCKNIX Ports** com caminhos relativos ao diretório real, isolamento de `LD_LIBRARY_PATH`, inicialização Wayland correta e diretórios graváveis.
5. **Executar teste físico offline, depois HTTPS**, documentando códigos de saída e capturas mínimas de falha. Evitar instalar qualquer ELF no firmware; preservar backup e instrução de rollback.
6. **Validar usabilidade**: botões/analógicos, teclado virtual, favoritos/histórico se implementados, ajuste 640 × 480, baixo consumo e recuperação de travamentos.
7. **Publicar release de teste** apenas com relatório de CI + dispositivo, hash do pacote, versão do ROCKNIX, modo de instalação e limites conhecidos.

## Teste físico mínimo e registros separados

- Registrar `uname -m`, `getconf GNU_LIBC_VERSION`, build ROCKNIX e socket `WAYLAND_DISPLAY`, preservando só dados técnicos necessários.
- Executar diagnóstico estático/safe antes de executar motor. Se o cabeçalho da biblioteca WebKit não começar com bytes ELF `7f 45 4c 46`, **parar** e não testar `dlopen`.
- Em seguida, executar `--check-platform`, registrar saída/retorno, abrir a página `www/inicio.html`, testar HTTPS e saída limpa. Falha 139 deve ser tratada como bloqueio de release, não como sucesso de teste.
- Manter `Terminal-R36-inicio.log` **exclusivamente** para o terminal R36 e `fire4nix-*.log`, `Fire4Nix-*.log` para o navegador. Não publicar senhas, tokens, IPs ou dados de navegação sem revisão.

## P1/P2 — depois do primeiro navegador funcional

- P1: tempo de abertura, limite de memória, comportamento ao perder Wi-Fi, estabilidade após múltiplas páginas, teclas mapeadas, perfil econômico e logs curtos legíveis.
- P2: funções avançadas de perfis, favoritos, downloads e experiência refinada de navegação. Não devem bloquear um primeiro protótipo com renderização comprovada.

## Como atualizar este documento

Informar para cada gate: **revisão exata**, CI ou arquivo de log, **ambiente** (runner/ROCKNIX físico), resultado `PASS`/`FAIL` e limitações. Evitar substituir uma evidência física por mock de CI.
