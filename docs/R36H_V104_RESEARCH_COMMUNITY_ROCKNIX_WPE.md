# Pesquisa comunitária e auditoria ROCKNIX / WPE — 18/10/2026

## Problema confirmado no R36H

ROCKNIX 20261001, kernel 7.1.2, aarch64 RK3326, glibc 2.41. WPE `libWPEWebKit-2.0.so.1` de 174.006.016 bytes e processos auxiliares em armazenamento portátil. O diagnóstico registrado retornou 139 na pré-verificação (`--check-platform`), sem renderização e sem backtrace. Uma janela SDL de outro programa funcionou; **isso não é prova** de que a biblioteca WPE está correta.

## Pistas verificadas no código-fonte oficial

1. A configuração ROCKNIX de Sway para RK3326 define `WAYLAND_DISPLAY=wayland-1`, `XDG_RUNTIME_DIR=/var/run/0-runtime-dir`, `SDL_VIDEODRIVER=wayland`. Fonte: https://github.com/ROCKNIX/distribution/blob/next/projects/ROCKNIX/packages/wayland/compositor/sway/profile.d/050-sway.conf
2. O RK3326 suporta `mali panfrost`, `DISPLAYSERVER=wl`, `WINDOWMANAGER=swaywm-env`, `libmali` proprietário da família g29p1. Fonte: https://github.com/ROCKNIX/distribution/blob/next/projects/ROCKNIX/devices/RK3326/options
3. O `090-ui_service` da família RK3326 escreve `MALI_DEFAULT_DISPLAY=wayland`, `WSIALLOC_USE_GBM=1`, `WLR_DRM_AFBC_ALT_PRIMARY=1` para libmali e **remove** a antiga linha `MALI_WAYLAND_AFBC=0` de `/storage/mali_debug.config` durante a migração. Fonte: https://github.com/ROCKNIX/distribution/blob/next/projects/ROCKNIX/packages/hardware/quirks/platforms/RK3326/090-ui_service
4. A receita do Fontconfig no ROCKNIX **apaga /usr/bin do pacote** após a instalação. Logo, não encontrar `fc-list` não significa ausência de fontes. Fonte: https://github.com/ROCKNIX/distribution/blob/next/packages/x11/other/fontconfig/package.mk
5. O patch `001-map-loader-gap-at-runtime.patch` descreve um SIGSEGV de Vulkan/libmali causado por segmentos ELF com alinhamento de páginas diferente. Porém contém explicitamente `if (sizeof(void *) != 4) return;` e **não é aplicável ao launcher AArch64 (64 bits)**. Não usar a semelhança do erro como diagnóstico. Fonte: https://github.com/ROCKNIX/distribution/blob/next/projects/ROCKNIX/packages/graphics/libmali/patches/next/001-map-loader-gap-at-runtime.patch
6. O PortMaster do ROCKNIX distribui bibliotecas de compatibilidade em `/usr/lib/compat`; algumas dependências podem ser encontradas ali, mas acrescentá-las sem verificar ABI é arriscado. Fonte: https://github.com/ROCKNIX/distribution/blob/next/projects/ROCKNIX/packages/apps/portmaster/package.mk

## Pistas no WebKit upstream

- WPE WebKit 2.54 passou a preferir WPEPlatform (`WPE_PLATFORM=wayland|headless|drm`) sem depender de Cog para integrações novas: https://wpewebkit.org/blog/2026-10-06-wpe-platform.html
- WPE 2.54.1 corrigiu compatibilidade do backend Wayland com libwayland-client >=1.25. Essa nota **não demonstra** que é a causa de 139 no console: https://wpewebkit.org/release/wpewebkit-2.54.1.html
- FAQ: fontconfig sem fonte fallback pode ocasionar crash no início. MIME compartilhado afeta páginas locais: https://wpewebkit.org/about/faq.html
- Uma falha em `dlopen(..., RTLD_NOW|RTLD_GLOBAL)` pode ocorrer dentro dos inicializadores da própria biblioteca ou dependências **antes de retornar**. Portanto, captura de versão apenas após `dlopen` não funciona para todos os casos.

## Comunidade R36S e vídeos

- Reddit: usuário ROCKNIX conseguiu rodar port SDL substituindo `SDL_VIDEODRIVER=ksmdrm` por `wayland` e adicionando uma dependência ausente. Isso **não comprova** relação com o WPE: https://www.reddit.com/r/R36S/comments/1suzcv1/gta_sa_en_rocknix/
- Reddit: solução `swaymsg [app_id=...] fullscreen enable` após iniciar aplicação. Relevante somente **depois da janela abrir**: https://www.reddit.com/r/R36S/comments/1wz5x27/corre%C3%A7%C3%A3o_para_alguns_ports_rodando_em_janela_no/
- NetSurf apresentou falhas de inicialização em ArkOS, dependendo de biblioteca/runtime: https://www.reddit.com/r/R36S/comments/1ez8e64/web_browser_in_portmaster/
- Vídeo SjslTech, 30/05/2026: `Firefox Web Browser Addon for the R36S - Install Guide & Tests`, demonstra Fire4ArkOS em ArkOS/dArkOS, **não ROCKNIX**: https://www.youtube.com/watch?v=w6kol8Cjgyw
- Código do Fire4ArkOS usa Firefox, segundo README: https://github.com/Cheemsdoge28/fire4arkos. Alternativa de arquitetura caso um runtime WPE compatível seja inviável; exige avaliação de dependências/memória no ROCKNIX, não transplante direto.

## Mudanças derivadas desta pesquisa

- Removido o `export MALI_WAYLAND_AFBC=0` automático do launcher Fire4Nix. Respeitar a configuração ROCKNIX e qualquer escolha explicitamente definida pelo usuário.
- Diagnóstico Fontconfig não depende exclusivamente da ferramenta `fc-list`, que pode estar propositalmente ausente; quando necessário, examina arquivos .ttf/.otf/.ttc e informa que cache permanece sem verificação.
- Testes garantem que, sem uma variável `MALI_WAYLAND_AFBC` fornecida, Fire4Nix não a introduz e, quando fornecida, não a sobrescreve.

## Próxima hipótese prioritária

Coletar o **último checkpoint nativo** do novo pré-teste: diferenciar carregamento `dlopen`, chamada dos getters da versão e início da criação do WebView. Se o crash acontece no `dlopen`, auditar `NEEDED`, `RPATH`, `RUNPATH`, `GLIBC` e dependências transitivas reais do WPE em armazenamento portátil. Se acontece apenas na criação do WebView, aí sim avançar para EGL/GBM/Wayland, sandbox e fontes. Não alterar drivers do firmware nem desligar sandbox sem evidência.

**Conclusão:** nenhuma postagem ou vídeo pesquisado reproduziu comprovadamente o **mesmo** `WPEPlatform_preflight_exit=139` do R36H. Causas gerais por 'retornar ao menu' não identificam essa falha específica.
