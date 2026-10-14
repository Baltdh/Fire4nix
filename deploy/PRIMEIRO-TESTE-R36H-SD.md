# Fire4Nix — primeiro teste no R36H (ROCKNIX)

## Objetivo

Testar a **abertura de uma página HTML local** no R36H real, pelo menu *Tools*, com a versão WPEPlatform ARM64. Esse teste é experimental, não uma release aprovada.

O pacote combinado para SD, entregue ao usuário nesta etapa, foi montado com dois artefatos verificáveis do GitHub Actions:

- Execução **38483124983** — `Fire4Nix-ROCKNIX-ARM64-Tools-launcher-only-EXPERIMENTAL`.
- Execução **36968610673** — `Fire4Nix-WPE-ARM64-library-experimental`, que inclui `libWPEWebKit-2.0.so.1.11.3`, `WPEWebProcess`, `WPENetworkProcess` e `WPEGPUProcess`.

O ZIP de primeiro teste contém `Tools/Fire4Nix.sh`, `Tools/Fire4Nix-Diagnostico.sh` e a pasta `Tools/Fire4Nix/`. A biblioteca WPE de origem Debian foi incluída como **arquivo regular** `runtime/lib/libWPEWebKit-2.0.so.1` para dispensar links simbólicos no cartão SD FAT/exFAT. Os processos ficam em `runtime/libexec/wpe-webkit-2.0/`, e o lançador exporta `WEBKIT_EXEC_PATH` e `LD_LIBRARY_PATH` exclusivamente para seu próprio processo.

### Como instalar

Extraia o conteúdo para a pasta Tools usada pelo ROCKNIX. Se a raiz do cartão já possuir `roms/tools/`, coloque lá o conteúdo de `Tools/`; evite `Tools/Tools/`. Execute `Fire4Nix.sh` no menu correspondente. O endereço inicial é um arquivo `inicio.html` offline, sem depender de rede.

Se não abrir, execute `Fire4Nix-Diagnostico.sh` e verifique os arquivos:
- `/storage/Fire4Nix-primeiro-teste.log`;
- `/storage/Fire4Nix-diagnostico.log`;
- `/storage/fire4nix-entry.log`.

Os scripts não instalam pacotes, não sobrescrevem bibliotecas do ROCKNIX, não usam sudo e não desativam o sandbox. O teste é bloqueado para outras arquiteturas que não AArch64.

### Critérios para o teste físico

1. Identificar arquitetura e bibliotecas do sistema (especialmente glibc, GLIBCXX/CXXABI e bibliotecas WPEPlatform/Wayland/Soup3).
2. Confirmar abertura visível da página HTML offline (640×480).
3. Verificar saída para o menu Tools ao fechar, sem travamento ou processo zumbi.
4. Confirmar persistência de logs em caso de falha.
5. Após esses resultados, validar sandbox e rede antes de considerar acesso à internet ou publicar release.

### Limitações explícitas

**Este não é um bundle autossuficiente.** A biblioteca WPE construída em Debian depende de várias bibliotecas dinâmicas externas, incluindo GLib, libsoup3, WPEPlatform Wayland, ICU, GStreamer e componentes gráficos. Não é garantido que existam com ABI compatível na instalação física do ROCKNIX; portanto a ausência de qualquer dependência pode impedir abertura. O artefato original contém a biblioteca WPE e subprocessos, mas não todas essas dependências.

O conjunto ARM64 do build usado no pacote tem requisito **GLIBC_2.38**; a versão exata do ROCKNIX instalado deve ser coletada do console, não inferida da branch de desenvolvimento. A branch `next` do ROCKNIX também não serve de prova de compatibilidade do firmware instalado.

O launcher experimental suporta EGL/Wayland, mas a qualificação final segue bloqueada pela validação do sandbox no hardware físico. Não substitua bibliotecas de sistema por arquivos da build Debian.

## Origem e licenças

- [Projeto e código do Fire4Nix](https://github.com/Baltdh/Fire4nix)
- [WebKit](https://github.com/WebKit/WebKit)
- [WPE WebKit](https://wpewebkit.org/)

A biblioteca foi construída com uma alteração no caminho dos subprocessos para aceitar `WEBKIT_EXEC_PATH`; referências à implementação e patch encontram-se no repositório Fire4Nix. Redistribuições futuras devem preservar avisos de licença e ofertas de código-fonte correspondentes.
