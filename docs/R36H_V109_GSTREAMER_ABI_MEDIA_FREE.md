# Fire4Nix v1.09 — investigação real de GST_CAT_DEFAULT e compilação sem multimídia

Atualização: 19/10/2026. Console R36H, RK3326 AArch64, ROCKNIX com glibc 2.41.

## Fato novo: auditoria REAL do ZIP de recuperação

Inspecionado o arquivo `Fire4Nix-R36H-Resgate-Runtime-Validado.zip` fornecido anteriormente, sem executar a biblioteca (ELF com readelf). Os seguintes componentes ARM64 do runtime `lib/` exportam **referência dinâmica indefinida `GST_CAT_DEFAULT`**, e não definem essa variável internamente:

- libgstvideo-1.0.so.0
- libgstapp-1.0.so.0
- libgstaudio-1.0.so.0
- libgstgl-1.0.so.0
- libgstpbutils-1.0.so.0
- libgsttag-1.0.so.0

**Total: 6 bibliotecas com a referência, mais 1 `libgstallocators` no pacote que não apresenta essa mesma falha específica.** Na leitura do último relatório físico, `readelf -Ws` mostrou `OBJECT GLOBAL DEFAULT UND GST_CAT_DEFAULT` em `libgstvideo`. A libgstreamer do sistema foi encontrada, mas não exporta esse símbolo; isso é esperado pois `GST_CAT_DEFAULT` costuma ser definido dentro de cada módulo de depuração, não como API global de libgstreamer.

**WebKit recuperado real:** `libWPEWebKit-2.0.so.1`, 174.006.016 bytes, AArch64. A própria biblioteca tem `DT_NEEDED` para `libgstreamer-1.0.so.0`, `libgstallocators`, `libgstapp`, `libgstbase`, `libgstpbutils`, `libgstaudio`, `libgsttag`, `libgstvideo` e `libgstgl`. Seu maior requisito direto `GLIBC_2.38` não exclui incompatibilidades com outras libs, mas está abaixo da 2.41 observada no aparelho. Portanto remover as bibliotecas GStreamer do pacote **já compilado** NÃO resolve o loader.

**Correção pretendida para nova compilação:** WPE 2.54.1 no SDK ROCKNIX compatível, sem GStreamer, como primeiro protótipo de navegação. A opção `USE_GSTREAMER` é oficialmente definida em `Source/cmake/GStreamerDefinitions.cmake`; os recursos associados estão documentados em `GStreamerDependencies.cmake`, que depende de ENABLE_VIDEO, ENABLE_WEB_AUDIO, ENABLE_SPEECH_SYNTHESIS e ENABLE_WEB_CODECS. O perfil `minimal` agora força essas opções e outras funcionalidades multimídia OFF, evitando o conjunto GStreamer defeituoso. O perfil `full` é opt-in e exige reconstrução coerente das dependências.

## Mudanças aplicadas nesta atualização

1. **rocknix-integration/audit-wpe-gstreamer.sh**: auditoria estática de todos os `libgst*.so*` (ELF, NEEDED, `GST_CAT_DEFAULT`), leitura apenas, identifica ausência do core no pacote, sem falsear status do motor. No R36H: `--audit` sempre gera relatório; `--strict` falha (código 6) em bibliotecas com referência indefinida e bloqueia empacotamento.
2. **native/tests/test_wpe_gstreamer_guard.sh**: testes reproduzíveis em GitHub Actions com ELF sintético mal vinculado, ELF inválido, symlink redundante e ELF simples válido. Esses mocks são somente testes de auditoria, não WebKit real.
3. **rocknix-integration/stage-wpe-runtime.sh**: executa auditoria GStreamer **antes** do estágio final. Para perfil `minimal` (`FIRE4NIX_REQUIRE_MEDIA_FREE=1`), rejeita qualquer DT_NEEDED direto `libgst*` nos binários do pacote e produz `MEDIA-PROFILE.txt`.
4. **rocknix-integration/build-wpe-2.54.1.sh**: opção `FIRE4NIX_MEDIA_PROFILE=minimal|full`. Padrão `minimal`, grava o perfil usado no CMake e rejeita empacotar o build com outro perfil sem recompilar/reconfigurar.
5. **.github/workflows/r36h-oneinstall.yml**: entrega o auditor no ZIP diagnóstico 1.09, executa testes de regressão no runner ARM64 e mantém limite ZIP de 170 MiB.

## Limitações atuais e critérios antes de declarar sucesso

- O perfil de compilação minimal é **código de preparação**, **NÃO** um WebKit 2.54.1 já compilado ou rodando no R36H. Requer um SDK/sysroot ROCKNIX que corresponda ao firmware. Não inventar uma lib WPE gerada pelo GitHub Actions se ela não existir.
- Navegação HTML/CSS/JavaScript ainda precisa de teste com janela real Wayland. Vídeo HTML5, áudio, WebCodecs e síntese de voz ficam desabilitados no protótipo minimal por decisão explícita; perfil full continua como plano futuro.
- Mesmo com media-free correto, libxml2 via /usr/lib/compat, GL4ES válida em /usr/lib/gl4es, GLIBCXX, Wayland, fonts, MIME e componentes Mali precisam de auditoria no sistema físico. Não alterar /usr/lib nem criar `GST_CAT_DEFAULT` falso ou shim LD_PRELOAD.
- O ZIP 1.09 de Actions **não contém o motor WebKit real**. O artefato é diagnóstico + compilação do lançador ARM64 e ferramentas.
- Os testes anteriores do dispositivo confirmaram o ZIP de recuperação `status=STATIC_INTEGRITY_PASS` e falha `libgstvideo: undefined symbol GST_CAT_DEFAULT`; a análise local da biblioteca agora reforça isso em mais cinco componentes.

## Como rodar auditor no R36H com o ZIP de recuperação já extraído

Copie somente `Fire4Nix-Auditar-GStreamer.sh` ou `rocknix-integration/audit-wpe-gstreamer.sh` para `roms/ports` do SD externo. Execute pelo R36 Hub:

```sh
sh /storage/games-external/roms/ports/Fire4Nix-Auditar-GStreamer.sh --audit
```

Ou com o caminho explícito `--audit /storage/games-external/roms/ports/Fire4Nix-RK3326-Resgate/Fire4Nix/runtime/aarch64`. O relatório fica em `/storage/Fire4Nix-GStreamer-Auditoria.txt`. **Não altera o runtime e nem o firmware**. Espera-se `status=BLOCK_GST_ABI` para as seis bibliotecas identificadas — isso é um diagnóstico, não a correção.

Fontes upstream:
- https://github.com/WebKit/WebKit/blob/webkitglib/2.54/Source/cmake/GStreamerDefinitions.cmake
- https://github.com/WebKit/WebKit/blob/webkitglib/2.54/Source/cmake/GStreamerDependencies.cmake
- https://github.com/WebKit/WebKit/blob/webkitglib/2.54/Source/cmake/GStreamerChecks.cmake
