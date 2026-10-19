# Fire4Nix 1.08 — compatibilidade ELF e GLIBC no R36H

## Evidências do hardware (19/10/2026)
Os logs do R36H mostram AArch64, glibc 2.41, Wayland wayland-1 e biblioteca WebKit de 174.006.016 bytes recusada por `invalid ELF header` com exit 127. Não confundir com antigos relatos de erro 139. A origem dos bytes inválidos não foi identificada.

## Mudanças efetivas
1. **Script de Ports `Fire4Nix-Inspecionar-ELF.sh`:** diagnóstico somente de leitura, com 64 bytes iniciais, assinatura ELF, formatos comuns (gzip, xz, zstd, ZIP, HTML, ponteiro Git LFS), links quebrados, tamanho, blocos alocados, subprocessos, símbolos GLIBC e dependências quando `readelf` existe. Não executa WebKit nem baixa nada. Relatório padrão em `/storage/Fire4Nix-ELF-ultimo.txt`. O modo `--hash` é opcional e lê os 174 MB, mas `--quick` é o padrão.
2. **Receita WPE 2.54.1:** alvo padrão ROCKNIX `20260801` Cortex-A35; a glibc 2.41 dessa árvore corresponde ao valor no dispositivo. Não prova que o firmware seja exatamente dessa tag. O destino `20261001` só pode ser selecionado explicitamente e sua receita utiliza glibc 2.44.
3. **Empacotador WPE:** verifica ELF AArch64 e recusa uso de `GLIBC` superior ao alvo nas bibliotecas candidatas e subprocessos. Limite padrão `GLIBC_2.41`; seleção de 2.44 exige auditoria real do firmware.
4. **CI:** testes com arquivos falsos, gzip, HTML, Git LFS, links quebrados e limite `GLIBC_2.41`; ZIP verificado e teto negociado de 170 MiB.

## Limitações e próximos critérios de aceitação
- CI usa mock de WebKit em alguns testes. O ZIP da versão 1.08 **não embute motor real WPE**. O navegador ainda não está funcional no hardware. Não afirmar o contrário.
- Uma biblioteca ELF ARM64 com GLIBC dentro do limite ainda pode exigir GLIB, C++/GLIBCXX, ICU, libsoup, GStreamer, GBM, EGL, fontes, MIME e outros símbolos incompatíveis. Nenhuma validação completa de dependências transitivas foi concluída.
- Não trocar glibc do sistema, drivers Mali ou bibliotecas de jogos; manter rollback.
- Primeiro coletar o pequeno relatório ELF via Ports, depois validar biblioteca, subprocessos, carregamento `--check-platform`, headless, Wayland e finalmente HTTP/HTTPS.

## Fontes oficiais
- ROCKNIX RK3326: https://github.com/ROCKNIX/distribution/blob/20260801/projects/ROCKNIX/devices/RK3326/options
- glibc 2.41 no ROCKNIX 20260801: https://github.com/ROCKNIX/distribution/blob/20260801/packages/devel/glibc/package.mk
- glibc 2.44 no ROCKNIX 20261001: https://github.com/ROCKNIX/distribution/blob/20261001/packages/devel/glibc/package.mk
- WPE 2.54 opções e dependências: https://github.com/WebKit/WebKit/blob/webkitglib/2.54/Source/cmake/OptionsWPE.cmake
- WPEPlatform CMake: https://github.com/WebKit/WebKit/blob/webkitglib/2.54/Source/WebKit/WPEPlatform/CMakeLists.txt
- WPE 2.54 estrutura de instalação: https://github.com/WebKit/WebKit/blob/webkitglib/2.54/Source/WebKit/PlatformWPE.cmake