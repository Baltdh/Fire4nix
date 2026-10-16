# Fire4Nix 0.98 — compatibilidade de WPE 2.54.1 com ROCKNIX 20261001

## O que foi alterado de verdade

O executável ARM64 agora consulta as funções públicas `webkit_get_major_version()`, `webkit_get_minor_version()` e `webkit_get_micro_version()` **na biblioteca efetivamente carregada por `dlopen`**. Antes do primeiro WebView, registra:

- `[FIRE4NIX-ABI] wpe_version=2.54.1`, conforme o runtime real; ou `unknown` se essas funções não existem.
- Um alerta para versões anteriores a 2.54, quando a interface WPEPlatform era experimental ou podia estar desabilitada.
- Um alerta *não bloqueante* para WPE 2.54.0 sugerindo WPE 2.54.1 ou superior quando é necessário compatibilizar a compilação com Wayland 1.25+.

A checagem de API `--check-platform` continua exigindo `webkit_web_view_get_wpe_view`, separando bibliotecas legadas (código 78) de erros do carregador (127). Passar nessa checagem **não** comprova que o navegador criou uma janela, que o EGL funcionou ou que a página carregou. O diagnóstico independente `Diagnosticar-Fire4Nix.sh --screen` também apresenta a linha `WPE_version=` quando disponível.

A lógica atual de instalar um runtime já presente no cartão **permanece protegida**: é feita uma atualização atômica, rollback de falha e reutilização de WPE existente via hardlinks onde disponível. Quando um runtime completo for compilado e colocado em `Fire4Nix/runtime` dentro de um pacote, o instalador já tem suporte para preferir esse runtime à cópia instalada previamente e validará sua API antes de substituir a versão antiga.

## Caminho reprodutível para compilar WPE 2.54.1

Novo arquivo: `rocknix-integration/build-wpe-2.54.1.sh`. Ele será incluído no ZIP como `Preparar-WPE-ROCKNIX-2.54.1.sh`.

O roteiro é intencionalmente **para uma máquina de compilação com SDK/toolchain do ROCKNIX**, não para execução direta no R36H. Ele usa:

| Componente | Ponto de referência |
|---|---|
| Hardware | RK3326, AArch64 Cortex-A35, Mali G31 |
| ROCKNIX | Tag `20261001` |
| glibc da árvore ROCKNIX | 2.44 |
| Wayland da árvore ROCKNIX | 1.26.0 |
| WPE WebKit | Versão 2.54.1, source oficial verificado por SHA-256 |
| API | WPEPlatform e Wayland habilitados |
| Perfil inicial | Sem mídia avançada e áudio web, sem spellcheck, com backend headless para diagnósticos |

Fonte e SHA oficial `wpewebkit-2.54.1.tar.xz`:
`0de8bdfba011f9cd63ba9a9171fa6038dd2c08237894f4082abbb821f29d3fe9`.

**Importante:** o changelog WPE 2.54.1 confirma uma correção do backend integrado Wayland com `libwayland-client` >= 1.25, relacionada a compatibilidade de compilação. Não há evidência suficiente para afirmar que isso, sozinho, seja a causa do segfault do R36H. Também não se pode presumir que a biblioteca de 174 MB atualmente instalada seja 2.54.0; agora o código permite descobrir sua versão.

### Comandos no computador com SDK do ROCKNIX (não no R36H)

```sh
sh Preparar-WPE-ROCKNIX-2.54.1.sh --plan

export FIRE4NIX_WPE_ARCHIVE=/caminho/wpewebkit-2.54.1.tar.xz
export FIRE4NIX_ROCKNIX_TOOLCHAIN=/caminho/SDK/rocknix-toolchain.cmake
export FIRE4NIX_WPE_WORK=/caminho/build-wpe-2541
sh Preparar-WPE-ROCKNIX-2.54.1.sh --configure
sh Preparar-WPE-ROCKNIX-2.54.1.sh --build
```

O caminho do toolchain acima é **um exemplo que deve ser substituído pelo real**. A integração ainda precisará resolver as dependências WPE que o SDK disponibiliza, coletar as bibliotecas e os subprocessos corretos do resultado, empacotar o runtime e fazer uma validação gráfica no aparelho. A opção `--plan` não baixa nem altera nada. `--configure` recusa ferramentas ausentes e arquivo fonte com SHA-256 errado. Não oferecemos download de um runtime que ainda não foi efetivamente compilado.

### Testes automatizados incluídos

O CI ARM64 testa extração de versões 2.54.1, 2.54.0 e 2.50.0 em um WebKit mock, preflight da API (incluindo `wpe_view_get_display`), relatório por tela, alerta de compatibilidade e execução não destrutiva de `--plan`. Mantém os testes de instalação/rollback, keyboard/controller e estabilidade. A execução usa mock de WebKit e **não testa a GPU Mali física**.

## Fontes verificadas

- ROCKNIX `20261001` — RK3326: https://github.com/ROCKNIX/distribution/blob/20261001/projects/ROCKNIX/devices/RK3326/options
- ROCKNIX `20261001` — glibc e Wayland: https://github.com/ROCKNIX/distribution/blob/20261001/packages/devel/glibc/package.mk e https://github.com/ROCKNIX/distribution/blob/20261001/packages/wayland/wayland/package.mk
- WPE 2.54.1 release: https://wpewebkit.org/release/wpewebkit-2.54.1.html
- WPE API 2.54: https://wpewebkit.org/blog/2026-09-16-wpewebkit-2.54.html
- WPE 2.54 CMake: https://github.com/WebKit/WebKit/blob/webkitglib/2.54/Source/cmake/OptionsWPE.cmake
