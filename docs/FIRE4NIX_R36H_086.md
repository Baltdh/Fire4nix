# Fire4Nix 0.86 — candidato nativo WPEPlatform para R36H

## Mudança de engenharia

Nos scripts originais, a inicialização chamava a API legada `webkit_web_view_new_with_context(webContext)`, incompatível com a assinatura WPE legada que exige `WebKitWebViewBackend*`, e diferente da interface WPEPlatform atual. No C++ do projeto o construtor foi substituído por `g_object_new(WEBKIT_TYPE_WEB_VIEW, "web-context", webContext, nullptr)`.

O novo candidato nativo `native/fire4nix_wpeplatform.cpp` é uma alternativa real para executar no RK3326 (aarch64). Ele carrega em tempo de execução a biblioteca **já instalada** `libWPEWebKit-2.0.so.1` e cria a visualização usando GObject/WPEPlatform, escolhendo o backend Wayland por ambiente. Oferece perfil conservador com WebGL, WebRTC e mídia avançada opcionais. Um retorno `0` no smoke significa evento `load-finished` observado, **não prova que a página apareceu no LCD**.

## Testes concluídos por CI

- Compilação C++ em runner `ubuntu-24.04-arm`, ELF AArch64, selftest.
- Falha por WPE inexistente preservada como 127.
- Mock do WPE com objeto GObject real criado/destruído e evento assíncrono de `load-finished`, smoke com código 0.
- Shell script POSIX validado.
- Arquivo ZIP com verificação de integridade e SHA-256.

**Limite:** não há confirmação de estabilidade Mali/EGL no R36H, suporte efetivo a WPEPlatform no binário WPE localizado no cartão, nem renderização real.

## Uso no aparelho — sem desinstalar nem substituir a versão 0.85

Baixe o artefato ZIP do workflow `fire4nix-native-086.yml` no GitHub e extraia **os dois executáveis na mesma pasta**, por exemplo Download. No Terminal R36 Tools:

```sh
sh Fire4Nix-086-Teste.sh --selftest
sh Fire4Nix-086-Teste.sh --check-library
sh Fire4Nix-086-Teste.sh --smoke
sh Fire4Nix-086-Teste.sh --open
```

Se a biblioteca não estiver na pasta padrão, use `FIRE4NIX_ROOT=/caminho/Fire4Nix sh Fire4Nix-086-Teste.sh --smoke`. O log é salvo em `/storage/Fire4Nix-086-Resultado.txt`, se gravável.

### Critérios de conclusão

1. `--selftest` imprime `AArch64`, sem crash.
2. `--check-library` retorna 0; 127 indica dependência ausente/incompatível.
3. `--smoke` retorna 0 com `load-event=3` para HTML local (se 124, terminou por timeout; se 139, abortou o processo).
4. `--open` **mostra efetivamente a página na tela**; abre link HTTPS leve e funciona com controles adequados à integração WPEPlatform.
5. Saída do jogo não corrompe o sistema, e teste de repetição não sofre SIGSEGV. Sandbox mantido ativo.

**Não promover para navegador padrão antes dos cinco testes no aparelho.** Separar `Terminal-R36-inicio.log` dos logs Fire4Nix; não usar o terminal como evidência de crash da engine.
