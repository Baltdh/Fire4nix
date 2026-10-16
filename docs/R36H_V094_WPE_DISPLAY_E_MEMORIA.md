# Fire4Nix 0.94 — estabilidade da janela WPE e inicialização de configurações

## Objetivo

Fechar dois problemas fundamentais do launcher ARM64 no R36H com ROCKNIX: (a) o compositor Wayland pode perder a conexão enquanto o socket continua no sistema de arquivos; (b) o motor WebKit pode inicializar processos e cache antes de receber as opções de economia de memória. A referência usada é o código-fonte oficial do [WPE MiniBrowser](https://github.com/WebKit/WebKit/blob/main/Tools/MiniBrowser/wpe/main.cpp).

## Alterações verificadas

- Após obter `WPEView`, o Fire4Nix tenta resolver `wpe_view_get_display`. Quando há `WPEDisplay` e um sinal `disconnected`, conecta um callback que registra erro detalhado e fecha o GLib MainLoop com **código 71**. Sem o símbolo/sinal, mantém operação normal; a compatibilidade do WebKit não é presumida.
- Desconecta o handler antes de destruir o WebView, evitando que a callback referencie variáveis fora de seu tempo de vida.
- Cria `WebKitSettings` antes do WebView e aplica as opções de memória reduzida (sem WebGL, WebAudio, cache de página, WebRTC e mídia avançada). Se a propriedade GObject `settings` aceita escrita, passa o objeto como argumento construtor em `g_object_new`, como faz o MiniBrowser. Caso a API não exponha essa propriedade, utiliza `webkit_web_view_set_settings` quando disponível; sem essa função, registra o caso e continua.
- O perfil `FIRE4NIX_LOW_MEMORY=0` continua permitido. Nenhuma biblioteca GTK ou Qt foi adicionada.
- Metadados do launcher e do diagnóstico atualizados para 0.94.

## Testes CI

`native/tests/mock_wpewebkit.cpp` agora possui um `WPEDisplay` simulado que emite `disconnected`, além de uma propriedade `settings` somente de construção. O GitHub Actions verifica:

1. ELF ARM64 realmente compilado para Cortex-A35, `--selftest`, sintaxe dos scripts e página HTML.
2. Smoke do mock WebKit com configuração entregue na construção do WebView.
3. Perda de display após carregamento simulado: saída 71 e log explicativo, mesmo com o socket ainda presente.
4. Falha de renderer continua retornando 70; WebKit sem WPEPlatform retorna 78.
5. Instalação em uma etapa, atualização só de HTML, fallback em FAT/exFAT, rollback em falha de ativação.

Os testes usam a arquitetura ARM64, **não emulam a GPU Mali-G31, o DRM/EGL real nem a sessão Wayland do R36H**. Nenhum resultado falso de renderização é afirmado.

## Como testar no aparelho

1. Extraia o ZIP `Fire4Nix-R36H-0.94-Correcao-Janela.zip` e execute `sh Instalar-Fire4Nix-Uma-Vez.sh`.
2. Execute `sh Diagnosticar-Fire4Nix.sh`; o relatório padrão é `/storage/Fire4Nix-Diagnostico-094.txt`.
3. Abra em **Ports**; se sair ou exibir tela preta, consulte `/storage/Fire4Nix-ultimo-resultado.txt`.
4. Os códigos 71 e 70 agora distinguem desconexão de display e falha do subprocesso de renderização. Um código 0 em `--check-platform` **não** demonstra que a janela funcionou.

## Limitações

O ZIP não inclui os aproximadamente 174 MB de WebKit observados no cartão SD nem subprocessos; continua dependendo do runtime já existente. Controle pelo gamepad físico e renderização real permanecem pendentes. Não modifica drivers Mali, firmware, sistema nem sandbox.
