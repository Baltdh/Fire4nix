# Fire4Nix 1.12 — auditoria de empacotamento, runtime e dependências no R36H

Data: 20/10/2026. Complementa `docs/R36H_V109_GSTREAMER_ABI_MEDIA_FREE.md` e o dossiê do PR #31.

## Erros confirmados no código e correções

### 1. Staging do WebKit não incluía todos os artefatos
O antigo `rocknix-integration/stage-wpe-runtime.sh` copiava apenas arquivos `lib/*.so*` e três subprocessos. O instalador upstream do WebKit WPE 2.54 instala também:
- `lib/wpe-webkit-2.0/injected-bundle/libWPEInjectedBundle.so`
- `share/wpe-webkit-2.0/inspector.gresource`

A omissão gerava um staging formalmente bem-sucedido, mas incompleto. Corrigido:
- exige esses dois artefatos na árvore DESTDIR antes de criar saída;
- copia o diretório do injected-bundle e os recursos WPE para o runtime privado;
- verifica arquitetura AArch64 e versão máxima de GLIBC do bundle;
- inclui bundle e inspector no manifesto SHA256SUMS;
- verifica dependência `libgst*` do bundle também no modo `MEDIA_FREE`.

### 2. Lançador omitia caminhos ROCKNIX necessários à ABI
O teste real do R36H só avançou além de `libxml2.so.2` e `libGL.so.1: file too short` ao incluir `/usr/lib/compat` e `/usr/lib/gl4es`. O inicializador oficial isolava o `LD_LIBRARY_PATH` somente no runtime privado, fazendo o erro anterior reaparecer. Correção:
- usa apenas o runtime + diretórios de compatibilidade *que contenham os provedores ELF AArch64 verificados*;
- mantém o descarte do caminho herdado de outros Ports por padrão;
- rejeita provedores incompatíveis e registra o resultado;
- `FIRE4NIX_ROCKNIX_COMPAT_LIBS=0` permite desativar a seleção, sem tocar o sistema;
- `FIRE4NIX_ROCKNIX_XML2_PATH` / `FIRE4NIX_ROCKNIX_GL_PATH` permitem alterar candidatos explicitamente (úteis em testes).

**Importante:** isso não prova compatibilidade funcional GL4ES/Mali; só permite que o carregador encontre as duas bibliotecas verificadas. A falha GStreamer do ZIP resgatado permanece.

### 3. Receita mínima dependia de ferramentas de documentação
O código oficial de opções do WPE habilita GObject Introspection e documentação, que podem exigir `gobject-introspection` e `gi-docgen` no SDK. A receita de cross-build agora passa:
- `-DENABLE_INTROSPECTION=OFF`
- `-DENABLE_DOCUMENTATION=OFF`

Nenhuma dessas opções desativa navegação HTML/JS. A receita continua não compilada neste ambiente: precisa de sysroot/cross-toolchain ROCKNIX.

### 4. Stager aceitava substituir link simbólico pendente
O teste `[ ! -e "$OUT" ]` retornava verdadeiro para um *dangling symlink*. Agora o instalador recusa tanto diretório já existente quanto symlink, inclusive pendente, antes da extração.

## Cobertura de regressão
- `native/tests/test_runtime_staging.sh`: bundle e recurso obrigatórios; recusa bundle corrompido, runtime incompleto e output symlink; confirma SHA256SUMS, limites GLIBC, rejeição de GST.
- `native/tests/test_isolated_loader.sh`: confirma que a seleção de provedores ARM64 só inclui diretórios explicitamente verificados, sem importar `LD_LIBRARY_PATH` desconhecido.
- `.github/workflows/r36h-oneinstall.yml`: testes e pacote diagnóstico 1.12.

## Ainda não provado
- WebKit 2.54.1 compilado especificamente contra o sysroot do aparelho (glibc 2.41);
- dependências transitivas GLib, libsoup, ICU, WPEPlatform, DRM/GBM/Mali, GLIBCXX;
- ausência do erro de `GST_CAT_DEFAULT` em nova build real;
- sucesso `--check-platform`, HTML local, Wayland 640x480, HTTPS e navegação no R36H.

## Fontes oficiais
- WPE 2.54.1: https://wpewebkit.org/release/wpewebkit-2.54.1.html
- Código de instalação: https://github.com/WebKit/WebKit/blob/webkitglib/2.54/Source/WebKit/PlatformWPE.cmake
- Opções de configuração WPE: https://github.com/WebKit/WebKit/blob/webkitglib/2.54/Source/cmake/OptionsWPE.cmake
- Regras do carregador: https://man7.org/linux/man-pages/man8/ld.so.8.html

Não modificar `/usr/lib`, glibc, Mali, kernel ou firmware para testar esta PR. O runtime antigo permanece intacto. Este ZIP é **diagnóstico**; não inclui WebKit compilado.
