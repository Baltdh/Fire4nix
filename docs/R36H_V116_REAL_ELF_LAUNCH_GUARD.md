# Fire4Nix 1.16 — bloqueio de WebKit inválido antes de executar no R36H

## Diagnóstico físico (20/10/2026)
O usuário executou o teste 1.15 no R36H ROCKNIX já recuperado da tela preta e recebeu:

- `arch=aarch64`, `kernel=7.1.2`, `glibc=glibc 2.41`.
- `wayland_socket=present`, `gamepad_mapper=present`, `drm_render=not_found`. A ausência desse nó DRM não comprova ausência de suporte gráfico Mali/Wayland.
- `/storage` é ext4 (mmcblk1p2), mas o cartão externo `/storage/games-external` e o alias `/storage/roms` são exFAT (mmcblk0p1); `external_sd_warning=EXFAT_UNCLEAN_UNMOUNT`.
- O WPE encontrado em `/storage/games-internal/roms/tools/Fire4Nix/runtime/lib/libWPEWebKit-2.0.so.1` tem **174006016 bytes**, mas `readelf -h` não reconheceu o cabeçalho como AArch64 (`webkit_elf=BAD_HEADER_OR_NOT_AARCH64`). `wpeplatform_symbol=absent_or_unreadable` não prova que símbolo está ausente, pois o arquivo já é ilegível.
- Os três subprocessos WPE existem. `gst_cat_default=NOT_CHECKED_NO_GSTVIDEO` não é aprovação ABI; o `libgstvideo` não estava nesse diretório.

## Correções implementadas
1. `installer/Fire4Nix-Iniciar.sh` agora usa o template de `mktemp` compatível com BusyBox, terminando em `-XXXXXX`, e não `-XXXXXX.log`.
2. Antes do carregamento do WebKit (todos os modos exceto `--selftest`), `readelf -h` verifica a arquitetura AArch64. Se o ELF estiver ausente/corrompido ou não houver `readelf`, recusa o lançamento com código **65** e registra `runtime_elf_status` no log. Nenhuma modificação de sistema.
3. Faz inspeção estática de `libgstvideo/libgstapp/libgstaudio/libgstgl/libgstpbutils/libgsttag` caso existam, recusando bibliotecas com `GST_CAT_DEFAULT` indefinido para evitar a falha real de carregamento anterior.
4. Regressões CI atualizadas para usar um ELF mock AArch64 real em vez de texto comum e para verificar rejeição explícita de ELF corrompido e GST indefinido. Os mocks **não são um WebKit funcional**.

## Próxima coleta — read-only
No terminal R36 Hub, sem modificar ou reconstruir a biblioteca:

```sh
od -An -tx1 -N16 '/storage/games-internal/roms/tools/Fire4Nix/runtime/lib/libWPEWebKit-2.0.so.1'
```

Cabeçalho ELF esperado começa com `7f 45 4c 46`. Se divergir, existe corrupção/incompletude no arquivo (mesmo com tamanho esperado). Não sobrescrever o original até comprovar integridade da nova fonte, preferencialmente do ZIP intacto no celular, e evitar gravar no SD externo exFAT até backup e reparo OFFLINE. Corrigir somente o inicializador **não torna o navegador funcional**; ainda falta construir WPE 2.54.1 minimizado contra SDK ROCKNIX verdadeiro.
