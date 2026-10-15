# Fire4Nix 0.89 — otimizações e verificação de compatibilidade WPEPlatform

## R36H / ROCKNIX 20261001

Esta versão otimiza o **launcher ARM64 nativo** e o **instalador de uma única etapa**. O sistema de arquivos e firmware ROCKNIX permanecem inalterados. O navegador só terá renderização confirmada depois de rodar no R36H real.

## Correções aplicadas

1. **Detecção de API:** um arquivo `libWPEWebKit-2.0.so.1` existente não prova que WPEPlatform foi habilitado. O novo `--check-platform` procura explicitamente `webkit_web_view_get_wpe_view`; falta da API retorna código 78 antes da criação de uma janela que poderia terminar com SIGSEGV. Não garante conexão efetiva com Sway nem funcionamento de módulos GPU.
2. **Fechamento correto:** o encerramento pelo compositor Wayland é sinalizado em `WPEView::closed`, não no evento de fechamento de página de `WebKitWebView`. O launcher liga este sinal ao ciclo GLib, com fallback para SIGTERM/SIGINT.
3. **Perfil de memória RK3326:** o valor padrão de `FIRE4NIX_LOW_MEMORY=1` desativa WebGL, WebAudio, cache de páginas anteriores, WebRTC e funcionalidades de mídia avançadas quando presentes; exige gesto do usuário para iniciar reprodução. `FIRE4NIX_LOW_MEMORY=0` restaura as opções normais. Esta é uma configuração de economia, não uma medição de consumo no hardware.
4. **Erro sem falsos positivos:** processo web encerrado não é reportado como SIGSEGV do processo nativo; código 70 distinto. Carregamento mínimo agora aceita até 30s antes do timeout 124; não equipara `load-finished` com página visível.
5. **Instalação idempotente:** uma instalação já válida pode ser reutilizada sem copiar novamente a biblioteca WebKit de ~174 MB. Verifica o espaço disponível para cópia antes da instalação e deixa os arquivos anteriores intactos caso falhe.
6. **Entrada Ports segura:** registra backup de entrada `Fire4Nix.sh` existente antes de substituí-la, escrevendo o novo atalho em arquivo temporário.
7. **ELF Cortex-A35:** compilação ARM64 com `-Os -flto -mtune=cortex-a35`, eliminação de seções não utilizadas e remoção de símbolos de depuração no pacote. Validação `readelf` AArch64 e `--selftest` mantida.

## Testes automatizados

Em runner `ubuntu-24.04-arm`:

- build ARM64 e autoteste;
- biblioteca WPE falsa com API WPEPlatform: `--check-platform` 0, `--smoke` 0 após sinal assíncrono `load-finished`;
- biblioteca WPE legada sem WPEPlatform: `--check-platform` 78;
- instalação sem biblioteca recusada, sem criar um lançamento inválido;
- migração local simulada com três subprocessos, sem apagar o runtime origem;
- nova execução do instalador não recria 174 MB de arquivos.

**O mock não equivale ao navegador no aparelho**: ainda faltam sinais reais WPE/GPU, dependências e controles do R36H. Não declarar o programa como versão final nem runtime autossuficiente.

## Como testar

1. Extrair o ZIP `Fire4Nix-R36H-0.89-Instalacao-Unica-Otimizada.zip`.
2. Se a biblioteca WPE já estiver no cartão, executar `sh Instalar-Fire4Nix-Uma-Vez.sh` **uma única vez**.
3. Se a verificação nativa registrar código **78**, o WebKit antigo não oferece WPEPlatform. O instalador cancela com código **5**, mantendo a instalação anterior. Nesse caso será preciso um backend legado ou WebKit compatível — só alterações nos scripts não resolvem.
4. Com sucesso, iniciar o Fire4Nix em **Ports** na interface ROCKNIX.
5. Se fechar, enviar `/storage/Fire4Nix-ultimo-resultado.txt`.

## Documentação consultada

- WPEPlatform desde WPE 2.54: https://wpewebkit.org/blog/2026-10-06-wpe-platform.html
- WebKitSettings / `enable-page-cache`: https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/glib/WebKitSettings.cpp
- ROCKNIX 20261001 RK3326 options: https://github.com/ROCKNIX/distribution/blob/20261001/projects/ROCKNIX/devices/RK3326/options
