# Fire4Nix R36H — sonda ARM64 nativa (independente)

Construção experimental do GitHub Actions: [workflow](https://github.com/Baltdh/Fire4nix/actions/workflows/r36h-native-probe.yml).

O executável `fire4nix-wpe-probe-aarch64` é compilado em ambiente `ubuntu-24.04-arm` com GLib/GObject e carrega `libWPEWebKit-2.0.so.1` dinamicamente no dispositivo via `dlopen()`. **Ele não substitui `bin/fire4nix-wpe-platform`, não desativa sandbox e não instala bibliotecas no sistema.** A biblioteca WPE de aproximadamente 174 MB não está no repositório; deve existir na instalação atual do R36H.

## Passos para o aparelho

Descompacte o artefato **fora** da pasta do executável principal, com ambos os arquivos na mesma pasta. No Terminal R36 Tools:

```sh
sh Fire4Nix-WPE-Sonda-R36H.sh --check-library
sh Fire4Nix-WPE-Sonda-R36H.sh --check-view
sh Fire4Nix-WPE-Sonda-R36H.sh --load
```

A primeira etapa confirma se o carregador Linux consegue abrir o WPE; a segunda testa a construção de `WebKitWebView` e a descoberta de plataforma; a terceira tenta carregar o HTML local por no máximo 30 s. Execução que retorna 124 ao atingir o limite não é prova de renderização. O registro também identifica as fases por `stage=1..8` e tenta obter uma pilha de chamadas em erros nativos, se possível.

Para instalação em outro diretório:

```sh
FIRE4NIX_ROOT=/storage/games-internal/roms/tools/Fire4Nix sh Fire4Nix-WPE-Sonda-R36H.sh --check-library
```

O log completo e código de saída são registrados em `/storage/Fire4Nix-Sonda-WPE.txt` quando o armazenamento é gravável. Envie esse log para análise após verificar se há URLs privadas que devem ser ocultadas.

## Códigos de saída

- 0: biblioteca ou criação da janela funcionou para **a etapa solicitada**, não homologa renderização;
- 124: a execução com página ultrapassou 30 segundos sem encerrar (inconclusiva);
- 127: falha de carregamento da biblioteca ou símbolos dinâmicos;
- 139: sinal SIGSEGV; o log pode indicar a última etapa executada;
- outros: investigar o log.

## Restrições

A sonda foi compilada e executou `--selftest` em **Linux AArch64 no GitHub**, não no hardware RK3326. Sua ABI de GLib/GObject ainda depende das bibliotecas ROCKNIX instaladas. O WebKit 2.52 permite o uso inicial de WPEPlatform, mas os resultados no Mali real ainda precisam de teste. A sonda não repara automaticamente crashes no driver EGL, compositor, sandbox ou biblioteca WPE.
