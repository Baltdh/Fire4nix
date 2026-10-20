# Fire4Nix 1.17 — bloqueio GStreamer confirmado no R36H (20/10/2026)

## Diagnóstico físico concluído

Após validar SHA-256 do ZIP e extrair o WebKit na partição **ext4 interna**, o R36H confirmou:

- ELF64 AArch64 válido no backup recuperado (diferentemente da biblioteca corrompida na instalação antiga).
- `libgstvideo-1.0.so` com símbolo `GST_CAT_DEFAULT` GLOBAL UND.
- `readelf -Ws /usr/lib/libgstreamer-1.0.so.0 /usr/lib/libgstbase-1.0.so.0` não encontrou definição/exportação desse símbolo.
- O `readelf -d libWPEWebKit-2.0.so.1` mostrou **nove DT_NEEDED**:
  1. `libgstreamer-1.0.so.0`
  2. `libgstallocators-1.0.so.0`
  3. `libgstapp-1.0.so.0`
  4. `libgstbase-1.0.so.0`
  5. `libgstpbutils-1.0.so.0`
  6. `libgstaudio-1.0.so.0`
  7. `libgsttag-1.0.so.0`
  8. `libgstvideo-1.0.so.0`
  9. `libgstgl-1.0.so.0`

**Diagnóstico:** retirar `libgstvideo` ou configurar somente `LD_LIBRARY_PATH` não converte essa cópia em motor sem GStreamer. Desativar os recursos é uma escolha de **compilação**, não de inicialização. Não substituir nada em `/usr/lib`. Uma referência UND isoladamente não comprova que nunca haverá provedor, mas neste aparelho os provedores principais pesquisados não o fornecem, e o runtime de resgate teve falha dinâmica associada.

## Mudanças na receita do novo WPE 2.54.1

- Confirmado no código-fonte da tag oficial `wpewebkit-2.54.1`: `GStreamerDependencies.cmake` vincula `ENABLE_VIDEO`, `ENABLE_WEB_AUDIO`, `ENABLE_SPEECH_SYNTHESIS` e `ENABLE_WEB_CODECS` a `USE_GSTREAMER`. `OptionsWPE.cmake` possui `ENABLE_WPE_PLATFORM` e `ENABLE_WPE_PLATFORM_WAYLAND`.
- Receita `build-wpe-2.54.1.sh` mantém `-DUSE_GSTREAMER=OFF`, suporte Wayland/WPEPlatform, desabilita as funções multimídia na primeira versão.
- **Novo verificador** `rocknix-integration/verify-wpe-media-cache.sh` valida o **CMakeCache realmente gerado**, exigindo OFF em GStreamer, vídeo, áudio, MediaStream, WebRTC, WebCodecs, MediaRecorder, documentação e introspecção; e ON em WPEPlatform/Wayland, OFF em API legada.
- O verificador roda logo após `--configure`, antes do `--build` e antes do `--stage`; falha se faltar variável ou houver divergência.
- O `stage-wpe-runtime.sh` já verifica se não restaram bibliotecas `libgst*` nos `DT_NEEDED` dos artefatos ELF publicados. **Duas etapas independentes** são necessárias: cache correto e link final sem GStreamer.
- CI: `native/tests/test_wpe_cmake_cache_gate.sh` testa cache válido, cache com `USE_GSTREAMER=ON`, variável ausente, diretório sem cache, e perfil full opt-in. Fixtures não são compilação WebKit.

## Bloqueio remanescente

**Ainda não foi compilado WebKit funcional para o ROCKNIX.** A receita requer o sysroot/cross-toolchain produzido do ROCKNIX compatível com GLIBC 2.41 no R36H. CMakeCache e ELF staged só podem ser validados de ponta a ponta quando esse SDK e dependências estiverem disponíveis. Os testes de CI atualmente compilam launchers/mocks ARM64, não o motor de aproximadamente centenas de megabytes.

Fontes oficiais:
- https://github.com/WebKit/WebKit/blob/wpewebkit-2.54.1/Source/cmake/GStreamerDependencies.cmake
- https://github.com/WebKit/WebKit/blob/wpewebkit-2.54.1/Source/cmake/OptionsWPE.cmake
- https://github.com/WebKit/WebKit/blob/wpewebkit-2.54.1/Source/cmake/GStreamerDefinitions.cmake

## Ao usuário
Manter o ZIP e os arquivos ext4 recuperados como referência. Não sobrescrever a biblioteca corrompida da instalação anterior, não tentar executar a cópia ainda, não fazer reparo de exFAT enquanto o cartão estiver montado. Não há necessidade de repetir diagnóstico de DT_NEEDED.
